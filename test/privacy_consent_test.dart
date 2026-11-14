import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trackerone/core/map/map_privacy_consent.dart';
import 'package:trackerone/core/privacy/privacy_consent.dart';
import 'package:trackerone/core/push/push_gateway.dart';
import 'package:trackerone/core/push/push_service.dart';
import 'package:trackerone/features/push/application/push_registration_controller.dart';

class _FakePrivacyConsentStore implements PrivacyConsentStore {
  int version = 0;

  @override
  Future<int> readAcceptedVersion() async => version;

  @override
  Future<void> writeAcceptedVersion(int version) async {
    this.version = version;
  }

  @override
  Future<void> clear() async {
    version = 0;
  }
}

class _FakeMapConsentStore implements MapPrivacyConsentStore {
  final Map<String, bool> values = {};

  @override
  Future<bool> read(String providerId) async => values[providerId] ?? false;

  @override
  Future<void> write(String providerId, bool agreed) async {
    values[providerId] = agreed;
  }
}

class _FakePushGateway implements PushGateway {
  int deleteAliasCalls = 0;

  @override
  String get id => 'fake';

  @override
  Future<void> initialize({required String alias}) async {}

  @override
  Future<void> updateAlias(String alias) async {}

  @override
  Future<void> deleteAlias() async {
    deleteAliasCalls++;
  }

  @override
  Stream<PushMessage> get messages => const Stream<PushMessage>.empty();

  @override
  Future<PushMessage?> takeInitialMessage() async => null;

  @override
  Future<void> dispose() async {}
}

void main() {
  late _FakePrivacyConsentStore consentStore;
  late _FakeMapConsentStore mapStore;
  late _FakePushGateway pushGateway;

  ProviderContainer createContainer() {
    return ProviderContainer(
      overrides: [
        privacyConsentStoreProvider.overrideWithValue(consentStore),
        mapPrivacyConsentStoreProvider.overrideWithValue(mapStore),
        pushGatewayProvider.overrideWithValue(pushGateway),
      ],
    );
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    consentStore = _FakePrivacyConsentStore();
    mapStore = _FakeMapConsentStore();
    pushGateway = _FakePushGateway();
  });

  test('未同意时授权状态为 false', () async {
    final container = createContainer();
    addTearDown(container.dispose);

    expect(await container.read(privacyConsentProvider.future), isFalse);
  });

  test('同意后写入政策版本并放行', () async {
    final container = createContainer();
    addTearDown(container.dispose);

    await container.read(privacyConsentProvider.notifier).agree();

    expect(container.read(privacyConsentProvider).valueOrNull, isTrue);
    expect(consentStore.version, PrivacyConsentNotifier.policyVersion);
  });

  test('撤回同意会清空状态、地图授权并解绑推送', () async {
    final container = createContainer();
    addTearDown(container.dispose);

    await container.read(privacyConsentProvider.notifier).agree();
    await mapStore.write(MapPrivacyConsentNotifier.providerId, true);

    await container.read(privacyConsentProvider.notifier).revoke();

    expect(container.read(privacyConsentProvider).valueOrNull, isFalse);
    expect(consentStore.version, 0);
    expect(mapStore.values[MapPrivacyConsentNotifier.providerId], isFalse);
    expect(pushGateway.deleteAliasCalls, 1);
  });

  test('撤回时即使清理失败也必须回到未授权状态', () async {
    final container = createContainer();
    addTearDown(container.dispose);

    await container.read(privacyConsentProvider.notifier).agree();

    await container.read(privacyConsentProvider.notifier).revoke();

    expect(container.read(privacyConsentProvider).valueOrNull, isFalse);
  });

  test('推送服务在未同意时不注册别名', () async {
    final container = createContainer();
    addTearDown(container.dispose);

    // 先让授权状态落地，避免控制器在依赖加载中构建。
    await container.read(privacyConsentProvider.future);
    final state = await container.read(pushRegistrationProvider.future);

    expect(state.registered, isFalse);
    expect(state.providerId, 'fake');
    expect(pushGateway.deleteAliasCalls, 0);
  });
}
