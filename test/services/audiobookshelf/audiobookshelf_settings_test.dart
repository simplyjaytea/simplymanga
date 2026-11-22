import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mangayomi/services/audiobookshelf/audiobookshelf_settings.dart';

class _MemoryStore implements AbsCredentialsStore {
  AbsCredentials? saved;
  int clears = 0;

  _MemoryStore([this.saved]);

  @override
  Future<AbsCredentials?> read() async => saved;

  @override
  Future<void> save(AbsCredentials credentials) async => saved = credentials;

  @override
  Future<void> clear() async {
    clears++;
    saved = null;
  }
}

void main() {
  group('AbsSettingsNotifier', () {
    test('starts empty when nothing is stored', () async {
      final store = _MemoryStore();
      final container = ProviderContainer(
        overrides: [absCredentialsStoreProvider.overrideWithValue(store)],
      );
      addTearDown(container.dispose);

      expect(await container.read(absSettingsProvider.future), isNull);
    });

    test('loads stored credentials', () async {
      final store = _MemoryStore(
        const AbsCredentials(baseUrl: 'http://host:13378', token: 'tok'),
      );
      final container = ProviderContainer(
        overrides: [absCredentialsStoreProvider.overrideWithValue(store)],
      );
      addTearDown(container.dispose);

      final credentials = await container.read(absSettingsProvider.future);

      expect(credentials?.baseUrl, 'http://host:13378');
      expect(credentials?.token, 'tok');
    });

    test('save normalizes the URL and publishes the new state', () async {
      final store = _MemoryStore();
      final container = ProviderContainer(
        overrides: [absCredentialsStoreProvider.overrideWithValue(store)],
      );
      addTearDown(container.dispose);
      await container.read(absSettingsProvider.future);

      await container
          .read(absSettingsProvider.notifier)
          .save('http://host:13378/', ' tok ');

      expect(store.saved?.baseUrl, 'http://host:13378');
      expect(store.saved?.token, 'tok');
      expect(container.read(absSettingsProvider).value?.token, 'tok');
    });

    test('clear removes the stored credentials and the state', () async {
      final store = _MemoryStore(
        const AbsCredentials(baseUrl: 'http://host:13378', token: 'tok'),
      );
      final container = ProviderContainer(
        overrides: [absCredentialsStoreProvider.overrideWithValue(store)],
      );
      addTearDown(container.dispose);
      await container.read(absSettingsProvider.future);

      await container.read(absSettingsProvider.notifier).clear();

      expect(store.clears, 1);
      expect(container.read(absSettingsProvider).value, isNull);
    });
  });

  group('SecureAbsCredentialsStore', () {
    setUp(() => FlutterSecureStorage.setMockInitialValues({}));

    test('round-trips the URL and token through secure storage', () async {
      const store = SecureAbsCredentialsStore(storage: FlutterSecureStorage());

      await store.save(
        const AbsCredentials(baseUrl: 'http://host:13378', token: 'tok'),
      );
      final read = await store.read();

      expect(read?.baseUrl, 'http://host:13378');
      expect(read?.token, 'tok');

      await store.clear();

      expect(await store.read(), isNull);
    });

    test('a half-written pair reads as no configuration', () async {
      FlutterSecureStorage.setMockInitialValues({
        'abs_base_url': 'http://host:13378',
      });
      const store = SecureAbsCredentialsStore(storage: FlutterSecureStorage());

      expect(await store.read(), isNull);
    });
  });
}
