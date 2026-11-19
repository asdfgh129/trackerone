import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trackerone/core/privacy/background_location_consent.dart';

class _FakeBackgroundLocationConsentStore
    implements BackgroundLocationConsentStore {
  bool agreed = false;

  @override
  Future<bool> read() async => agreed;

  @override
  Future<void> write(bool value) async {
    agreed = value;
  }
}

void main() {
  late _FakeBackgroundLocationConsentStore store;
  late ProviderContainer container;

  setUp(() {
    store = _FakeBackgroundLocationConsentStore();
    container = ProviderContainer(
      overrides: [
        backgroundLocationConsentStoreProvider.overrideWithValue(store),
      ],
    );
    addTearDown(container.dispose);
  });

  Future<bool> read() =>
      container.read(backgroundLocationConsentProvider.future);

  test('未同意时后台定位授权为 false', () async {
    expect(await read(), isFalse);
  });

  test('同意后写入并放行', () async {
    await container.read(backgroundLocationConsentProvider.notifier).agree();
    expect(store.agreed, isTrue);
    expect(await read(), isTrue);
  });

  test('撤回后回到未授权状态', () async {
    await container.read(backgroundLocationConsentProvider.notifier).agree();
    await container.read(backgroundLocationConsentProvider.notifier).revoke();
    expect(store.agreed, isFalse);
    expect(await read(), isFalse);
  });
}
