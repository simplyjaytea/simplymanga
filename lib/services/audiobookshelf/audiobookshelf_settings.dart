// Where the Audiobookshelf server and its API token live, and the providers
// screens read them through.
//
// The token is a credential, so it goes through the OS secure storage the rest
// of the app uses, not SharedPreferences. [AbsCredentialsStore] is the seam:
// tests substitute an in-memory implementation, and [SecureAbsCredentialsStore]
// is the real one.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:mangayomi/services/audiobookshelf/audiobookshelf_client.dart';
import 'package:mangayomi/services/secure_storage.dart';

const absBaseUrlKey = 'abs_base_url';
const absTokenKey = 'abs_token';

class AbsCredentials {
  const AbsCredentials({required this.baseUrl, required this.token});

  final String baseUrl;
  final String token;

  bool get isConfigured => baseUrl.trim().isNotEmpty && token.trim().isNotEmpty;

  @override
  bool operator ==(Object other) =>
      other is AbsCredentials &&
      other.baseUrl == baseUrl &&
      other.token == token;

  @override
  int get hashCode => Object.hash(baseUrl, token);

  @override
  String toString() =>
      'AbsCredentials($baseUrl, token: ${token.isEmpty ? '' : '***'})';
}

abstract class AbsCredentialsStore {
  /// The stored pair, or null when nothing (or only half of it) is stored.
  Future<AbsCredentials?> read();

  Future<void> save(AbsCredentials credentials);

  Future<void> clear();
}

class SecureAbsCredentialsStore implements AbsCredentialsStore {
  const SecureAbsCredentialsStore({this.storage = secureStorage});

  final FlutterSecureStorage storage;

  @override
  Future<AbsCredentials?> read() async {
    final url = (await storage.read(key: absBaseUrlKey))?.trim() ?? '';
    final token = (await storage.read(key: absTokenKey))?.trim() ?? '';
    if (url.isEmpty || token.isEmpty) return null;
    return AbsCredentials(baseUrl: url, token: token);
  }

  @override
  Future<void> save(AbsCredentials credentials) async {
    await storage.write(key: absBaseUrlKey, value: credentials.baseUrl);
    await storage.write(key: absTokenKey, value: credentials.token);
  }

  @override
  Future<void> clear() async {
    await storage.delete(key: absBaseUrlKey);
    await storage.delete(key: absTokenKey);
  }
}

final absCredentialsStoreProvider = Provider<AbsCredentialsStore>(
  (ref) => const SecureAbsCredentialsStore(),
);

/// The saved server, loaded once. Screens watch this for both "is the app set
/// up?" and the values to edit.
final absSettingsProvider =
    AsyncNotifierProvider<AbsSettingsNotifier, AbsCredentials?>(
      AbsSettingsNotifier.new,
    );

class AbsSettingsNotifier extends AsyncNotifier<AbsCredentials?> {
  @override
  Future<AbsCredentials?> build() =>
      ref.read(absCredentialsStoreProvider).read();

  Future<void> save(String baseUrl, String token) async {
    final credentials = AbsCredentials(
      baseUrl: AudiobookshelfClient.normalizeBaseUrl(baseUrl),
      token: token.trim(),
    );
    await ref.read(absCredentialsStoreProvider).save(credentials);
    state = AsyncData(credentials);
  }

  Future<void> clear() async {
    await ref.read(absCredentialsStoreProvider).clear();
    state = const AsyncData(null);
  }
}

/// How a [AudiobookshelfClient] is built for a saved pair. Tests override this
/// to hand back a client whose `http.Client` is a fake.
final absClientFactoryProvider =
    Provider<AudiobookshelfClient Function(AbsCredentials)>(
      (ref) =>
          (credentials) => AudiobookshelfClient(
            baseUrl: credentials.baseUrl,
            token: credentials.token,
          ),
    );

/// The client for the saved server, or null before setup.
final absClientProvider = Provider<AudiobookshelfClient?>((ref) {
  final credentials = ref.watch(absSettingsProvider).value;
  if (credentials == null || !credentials.isConfigured) return null;
  final client = ref.watch(absClientFactoryProvider)(credentials);
  ref.onDispose(client.close);
  return client;
});
