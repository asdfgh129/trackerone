import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:trackerone/core/localization/localization.dart';
import 'package:trackerone/core/push/inbox_api.dart';
import 'package:trackerone/core/push/inbox_store.dart';
import 'package:trackerone/domain/entities/inbox_message.dart';
import 'package:trackerone/domain/entities/models.dart';
import 'package:trackerone/domain/entities/server_profile.dart';
import 'package:trackerone/domain/failures.dart';
import 'package:trackerone/features/auth/application/session_controller.dart';
import 'package:trackerone/features/inbox/application/inbox_controller.dart';
import 'package:trackerone/l10n/app_localizations.dart';

import 'package:flutter/widgets.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const server = ServerProfile(
    name: 'Demo',
    apiBaseUrl: 'https://traccar.example.com',
    reportUrl: 'https://traccar.example.com:5055',
  );
  const account = Account(id: 9, name: 'Tester', email: 't@example.com');
  const session = SessionState(
    server: server,
    token: 'token-1',
    account: account,
  );

  InboxMessage message(String id, {int minutesAgo = 0}) {
    return InboxMessage(
      id: id,
      kind: InboxKind.notice,
      title: 'title-$id',
      createdAt: DateTime.utc(
        2026,
        11,
        19,
        10,
      ).subtract(Duration(minutes: minutesAgo)),
    );
  }

  ProviderContainer createContainer({
    required _FakeInboxApi api,
    required _FakeInboxStore store,
    SessionState? sessionState = session,
  }) {
    final container = ProviderContainer(
      overrides: [
        sessionProvider.overrideWith(
          () => _FakeSession(sessionState ?? const SessionState()),
        ),
        inboxApiProvider.overrideWithValue(api),
        inboxStoreProvider.overrideWithValue(store),
        appLocalizationsProvider.overrideWithValue(
          lookupAppLocalizations(const Locale('en')),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  group('InboxController.build', () {
    test('loads the page, acknowledges and restores read state', () async {
      final api = _FakeInboxApi(
        pages: [
          InboxPage(
            messages: [message('a'), message('b', minutesAgo: 5)],
            nextCursor: 'c1',
          ),
        ],
      );
      final store = _FakeInboxStore()..readIds = {'b'};
      final container = createContainer(api: api, store: store);

      final state = await container.read(inboxProvider.future);

      expect(api.requestedCursors, [null]);
      expect(api.acked, ['a', 'b']);
      expect(state.messages.map((m) => m.id), ['a', 'b']);
      expect(state.unread, 1);
      expect(state.isUnread(message('a')), isTrue);
      expect(state.isUnread(message('b')), isFalse);
      expect(state.error, isNull);
      expect(state.gatewayMissing, isFalse);
      expect(container.read(inboxUnreadProvider), 1);
    });

    test('does not fetch without an authenticated session', () async {
      final api = _FakeInboxApi();
      final store = _FakeInboxStore();
      final container = createContainer(
        api: api,
        store: store,
        sessionState: const SessionState(),
      );

      final state = await container.read(inboxProvider.future);

      expect(api.requestedCursors, isEmpty);
      expect(state.messages, isEmpty);
      expect(state.gatewayMissing, isFalse);
    });

    test('reports a missing gateway instead of failing', () async {
      final api = _FakeInboxApi(enabled: false);
      final store = _FakeInboxStore();
      final container = createContainer(api: api, store: store);

      final state = await container.read(inboxProvider.future);

      expect(api.requestedCursors, isEmpty);
      expect(state.gatewayMissing, isTrue);
      expect(state.error, isNull);
    });

    test('keeps local read state when the fetch fails', () async {
      final api = _FakeInboxApi(
        failure: const AppFailure(
          FailureKind.network,
          'boom',
          messageKey: 'errorNetwork',
        ),
      );
      final store = _FakeInboxStore()..readIds = {'a'};
      final container = createContainer(api: api, store: store);

      final state = await container.read(inboxProvider.future);

      expect(state.messages, isEmpty);
      expect(state.readIds, {'a'});
      expect(state.error, isNotNull);
      expect(state.error, contains('Cannot reach the server'));
    });
  });

  group('InboxController.sync', () {
    test(
      'merges new messages, dedupes by id and advances the cursor',
      () async {
        final api = _FakeInboxApi(
          pages: [
            InboxPage(
              messages: [
                message('a', minutesAgo: 10),
                message('b', minutesAgo: 5),
              ],
              nextCursor: 'c1',
            ),
            InboxPage(
              messages: [message('b', minutesAgo: 5), message('c')],
              nextCursor: 'c2',
            ),
          ],
        );
        final store = _FakeInboxStore();
        final container = createContainer(api: api, store: store);
        await container.read(inboxProvider.future);

        await container.read(inboxProvider.notifier).sync();

        final state = container.read(inboxProvider).requireValue;
        expect(state.messages.map((m) => m.id), ['c', 'b', 'a']);
        expect(state.cursor, 'c2');
        expect(api.requestedCursors, [null, 'c1']);
        expect(api.acked, ['a', 'b', 'b', 'c']);
        expect(state.syncing, isFalse);
        expect(state.unread, 3);
      },
    );

    test('force ignores the stored cursor', () async {
      final api = _FakeInboxApi(
        pages: [
          InboxPage(messages: [message('a')], nextCursor: 'c1'),
          InboxPage(messages: [message('a')], nextCursor: 'c1'),
        ],
      );
      final container = createContainer(api: api, store: _FakeInboxStore());
      await container.read(inboxProvider.future);

      await container.read(inboxProvider.notifier).sync(force: true);

      expect(api.requestedCursors, [null, null]);
    });

    test('tolerates acknowledgement failures', () async {
      final api = _FakeInboxApi(
        pages: [
          InboxPage(messages: [message('a')], nextCursor: 'c1'),
        ],
        ackError: const AppFailure(FailureKind.network, 'ack failed'),
      );
      final store = _FakeInboxStore();
      final container = createContainer(api: api, store: store);

      final state = await container.read(inboxProvider.future);

      expect(state.messages, hasLength(1));
      expect(state.error, isNull);
    });

    test('keeps existing messages and surfaces the error', () async {
      final api = _FakeInboxApi(
        pages: [
          InboxPage(messages: [message('a')], nextCursor: 'c1'),
        ],
      );
      final container = createContainer(api: api, store: _FakeInboxStore());
      await container.read(inboxProvider.future);
      api.failure = const AppFailure(FailureKind.timeout, 'timeout');

      await container.read(inboxProvider.notifier).sync();

      final state = container.read(inboxProvider).requireValue;
      expect(state.messages.map((m) => m.id), ['a']);
      expect(state.error, isNotNull);
      expect(state.syncing, isFalse);
    });
  });

  group('command result linkage', () {
    test('pending item is local, not unread, and resolved by result', () async {
      final result = InboxMessage(
        id: 'result-1',
        kind: InboxKind.notice,
        data: const {
          'eventType': 'commandResult',
          'deviceId': 7,
          'result': 'success',
          'success': true,
        },
        createdAt: DateTime.now(),
      );
      final api = _FakeInboxApi(
        pages: [
          const InboxPage(messages: []),
          InboxPage(messages: [result]),
        ],
      );
      final container = createContainer(api: api, store: _FakeInboxStore());
      await container.read(inboxProvider.future);

      final notifier = container.read(inboxProvider.notifier);
      notifier.noteCommandDispatched(deviceId: 7, command: 'engineStop');

      var state = container.read(inboxProvider).requireValue;
      expect(state.messages, hasLength(1));
      expect(state.messages.single.isCommandPending, isTrue);
      expect(state.unread, 0);
      expect(container.read(inboxUnreadProvider), 0);

      await notifier.sync();

      state = container.read(inboxProvider).requireValue;
      expect(state.messages.map((m) => m.id), ['result-1']);
      expect(state.messages.single.isCommandResult, isTrue);
    });

    test('pending item for another device is kept', () async {
      final result = InboxMessage(
        id: 'result-1',
        kind: InboxKind.notice,
        data: const {'eventType': 'commandResult', 'deviceId': 8},
        createdAt: DateTime.now(),
      );
      final api = _FakeInboxApi(
        pages: [
          const InboxPage(messages: []),
          InboxPage(messages: [result]),
        ],
      );
      final container = createContainer(api: api, store: _FakeInboxStore());
      await container.read(inboxProvider.future);

      final notifier = container.read(inboxProvider.notifier);
      notifier.noteCommandDispatched(deviceId: 7, command: 'engineStop');
      await notifier.sync();

      final state = container.read(inboxProvider).requireValue;
      expect(state.messages.where((m) => m.isCommandPending), hasLength(1));
      expect(state.messages.where((m) => m.isCommandResult), hasLength(1));
    });
  });

  group('read state', () {
    test('markRead persists and updates the badge', () async {
      final api = _FakeInboxApi(
        pages: [
          InboxPage(messages: [message('a'), message('b', minutesAgo: 5)]),
        ],
      );
      final store = _FakeInboxStore();
      final container = createContainer(api: api, store: store);
      await container.read(inboxProvider.future);

      await container.read(inboxProvider.notifier).markRead('a');

      expect(store.readIds, {'a'});
      expect(container.read(inboxUnreadProvider), 1);
      expect(
        container.read(inboxProvider).requireValue.isUnread(message('b')),
        isTrue,
      );
    });

    test('markAllRead clears the badge', () async {
      final api = _FakeInboxApi(
        pages: [
          InboxPage(messages: [message('a'), message('b', minutesAgo: 5)]),
        ],
      );
      final store = _FakeInboxStore()..readIds = {'a'};
      final container = createContainer(api: api, store: store);
      await container.read(inboxProvider.future);

      await container.read(inboxProvider.notifier).markAllRead();

      expect(store.readIds, {'a', 'b'});
      expect(container.read(inboxUnreadProvider), 0);
    });
  });
}

class _FakeSession extends SessionController {
  _FakeSession(this.session);

  final SessionState session;

  @override
  Future<SessionState> build() async => session;
}

class _FakeInboxApi implements InboxApi {
  _FakeInboxApi({
    List<InboxPage>? pages,
    this.enabled = true,
    this.failure,
    this.ackError,
  }) : pages = pages ?? [];

  final List<InboxPage> pages;
  final AppFailure? ackError;
  @override
  bool enabled;

  AppFailure? failure;

  final List<String?> requestedCursors = [];
  final List<String> acked = [];
  int _index = 0;

  @override
  Future<InboxPage> fetch({
    required String token,
    String? cursor,
    int limit = 50,
  }) async {
    requestedCursors.add(cursor);
    final error = failure;
    if (error != null) throw error;
    if (pages.isEmpty) return const InboxPage(messages: []);
    final index = _index < pages.length ? _index : pages.length - 1;
    _index += 1;
    return pages[index];
  }

  @override
  Future<void> ack({required String token, required String id}) async {
    final error = ackError;
    if (error != null) throw error;
    acked.add(id);
  }
}

class _FakeInboxStore implements InboxStore {
  Set<String> readIds = {};

  @override
  Future<Set<String>> readReadIds(String scope) async => {...readIds};

  @override
  Future<void> writeReadIds(String scope, Set<String> ids) async {
    readIds = {...ids};
  }

  @override
  Future<void> clearAll() async {
    readIds = {};
  }
}
