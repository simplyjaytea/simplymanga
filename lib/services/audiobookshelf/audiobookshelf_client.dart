// HTTP client for a self-hosted Audiobookshelf server.
//
// Deliberately knows nothing about Riverpod, widgets or storage: it takes the
// base URL and token, and an injected `http.Client` so tests can answer
// without a network. See https://api.audiobookshelf.org for the contract.
import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:http/http.dart' as http;

import 'audiobookshelf_models.dart';

/// The failures a caller can tell apart, each with a sentence to show.
sealed class AbsException implements Exception {
  const AbsException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => '$runtimeType: $message';
}

/// The server could not be reached at all: wrong address, nothing listening,
/// a timeout, or no route from this network.
final class AbsUnreachableException extends AbsException {
  const AbsUnreachableException(super.message);
}

/// The server answered 401 or 403: the token is wrong or revoked.
final class AbsUnauthorizedException extends AbsException {
  const AbsUnauthorizedException(super.message, {super.statusCode});
}

/// The server answered with an error of its own, or with something that is not
/// the JSON the API documents.
final class AbsServerErrorException extends AbsException {
  const AbsServerErrorException(super.message, {super.statusCode});
}

/// The server answered 404 for an item, library or endpoint.
final class AbsNotFoundException extends AbsException {
  const AbsNotFoundException(super.message, {super.statusCode});
}

class AudiobookshelfClient {
  AudiobookshelfClient({
    required String baseUrl,
    required String token,
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 15),
  }) : baseUrl = normalizeBaseUrl(baseUrl),
       token = token.trim(),
       _http = httpClient ?? http.Client(),
       _ownsHttpClient = httpClient == null;

  /// The URL the user typed, ready to append API paths to: a scheme if they
  /// left it out (self-hosted servers are usually plain HTTP on a LAN), no
  /// trailing slash, no accidental query or fragment.
  ///
  /// A path prefix is kept, so `http://host/abs` resolves items under
  /// `/abs/api/...`. Throws [ArgumentError] when nothing usable is left.
  static String normalizeBaseUrl(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(raw, 'baseUrl', 'The server URL is empty.');
    }
    var value = trimmed;
    if (!value.contains('://')) value = 'http://$value';
    final uri = Uri.tryParse(value);
    if (uri == null || uri.host.isEmpty) {
      throw ArgumentError.value(
        raw,
        'baseUrl',
        'Enter a server URL such as http://192.168.1.10:13378.',
      );
    }
    var path = uri.path;
    while (path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }
    return uri.replace(path: path, query: null, fragment: null).toString();
  }

  final String baseUrl;
  final String token;
  final Duration timeout;
  final http.Client _http;
  final bool _ownsHttpClient;

  /// The id this app presents to the server. Stable for one server + token, so
  /// the server recognises the same device between launches without storing
  /// another secret.
  String get deviceId => 'simplymanga-${_fnv1a('$baseUrl\u0000$token')}';

  Map<String, String> get _headers => {
    'Authorization': 'Bearer $token',
    'Accept': 'application/json',
  };

  Uri _uri(String path, [Map<String, String>? query]) {
    final base = Uri.parse(baseUrl);
    final prefix = base.path;
    final suffix = path.startsWith('/') ? path : '/$path';
    return base.replace(path: '$prefix$suffix', queryParameters: query);
  }

  /// `GET /api/ping`: reachability only, no token involved.
  Future<void> ping() async {
    final uri = _uri('/api/ping');
    final response = await _run(() => _http.get(uri), uri);
    _ensureOk(response, uri);
    final body = _decode(response);
    if (body['success'] == false) {
      throw AbsServerErrorException(
        'The server answered but is not ready yet.',
        statusCode: response.statusCode,
      );
    }
  }

  /// `GET /api/me`: the credential check. The user's name is what the
  /// connection screen shows once it succeeds.
  Future<AbsUser> me() async {
    final uri = _uri('/api/me');
    final response = await _run(() => _http.get(uri, headers: _headers), uri);
    _ensureOk(response, uri);
    return AbsUser.fromJson(_decode(response));
  }

  /// `GET /api/libraries`. Both book and non-book libraries are returned; the
  /// screen decides which can be opened.
  Future<List<AbsLibrary>> libraries() async {
    final uri = _uri('/api/libraries');
    final response = await _run(() => _http.get(uri, headers: _headers), uri);
    _ensureOk(response, uri);
    final body = _decode(response);
    final raw = body['libraries'];
    if (raw is! List) {
      throw AbsServerErrorException(
        'The server did not return a library list.',
        statusCode: response.statusCode,
      );
    }
    return raw
        .whereType<Map<String, dynamic>>()
        .map(AbsLibrary.fromJson)
        .toList(growable: false);
  }

  /// One page of a library's items, sorted by title.
  Future<AbsItemsPage> libraryItems(
    String libraryId, {
    int page = 0,
    int limit = 50,
  }) async {
    final uri = _uri('/api/libraries/$libraryId/items', {
      'limit': '$limit',
      'page': '$page',
      'sort': 'media.metadata.title',
      'minified': '1',
    });
    final response = await _run(() => _http.get(uri, headers: _headers), uri);
    _ensureOk(response, uri);
    return AbsItemsPage.fromJson(_decode(response));
  }

  /// The full item, including the track list that [startPlayback]'s session
  /// usually repeats.
  Future<AbsItem> item(String id) async {
    final uri = _uri('/api/items/$id');
    final response = await _run(() => _http.get(uri, headers: _headers), uri);
    _ensureOk(response, uri);
    return AbsItem.fromJson(_decode(response));
  }

  /// Opens a playback session. The response's `contentUrl`s are relative;
  /// turn each into a playable URL with [streamUri].
  Future<AbsPlaybackSession> startPlayback(String id) async {
    final uri = _uri('/api/items/$id/play');
    final body = {
      'deviceInfo': {
        'deviceId': deviceId,
        'clientName': 'simplyMANGA',
        'clientVersion': '0.9.97',
        'manufacturer': 'Apple',
        'model': 'iPhone',
      },
      'mediaPlayer': 'media_kit',
      'forceDirectPlay': true,
      'supportedMimeTypes': const [
        'audio/mpeg',
        'audio/mp4',
        'audio/aac',
        'audio/flac',
        'audio/ogg',
        'audio/opus',
      ],
    };
    final response = await _run(
      () => _http.post(
        uri,
        headers: {..._headers, 'Content-Type': 'application/json'},
        body: jsonEncode(body),
      ),
      uri,
    );
    _ensureOk(response, uri);
    return AbsPlaybackSession.fromJson(_decode(response));
  }

  /// Reports where the reader is, in seconds. Best-effort: a failure must not
  /// interrupt playback or take down the screen, so it is logged at debug level
  /// and dropped.
  Future<void> saveProgress(
    String id, {
    required double currentTime,
    required double duration,
    bool isFinished = false,
  }) async {
    final uri = _uri('/api/me/progress/$id');
    try {
      final response = await _run(
        () => _http.patch(
          uri,
          headers: {..._headers, 'Content-Type': 'application/json'},
          body: jsonEncode({
            'currentTime': currentTime,
            'duration': duration,
            'isFinished': isFinished,
          }),
        ),
        uri,
      );
      _ensureOk(response, uri);
    } on AbsException catch (error) {
      developer.log(
        'progress for $id was not saved: ${error.message}',
        name: 'audiobookshelf',
        level: 500,
      );
    }
  }

  /// The cover image, with the token in the query because image widgets cannot
  /// set an Authorization header.
  Uri coverUri(String id) => _uri('/api/items/$id/cover', {'token': token});

  /// Resolves a session's relative `contentUrl` against [baseUrl], keeping a
  /// path prefix, and appends `?token=` for media_kit, which cannot set
  /// headers either.
  Uri streamUri(String relativeContentUrl) {
    final raw = relativeContentUrl.trim();
    final parsed = Uri.tryParse(raw);
    late final Uri uri;
    if (parsed != null && parsed.hasScheme) {
      uri = parsed;
    } else {
      uri = _uri(parsed?.path.isNotEmpty == true ? parsed!.path : raw);
    }
    final query = <String, String>{
      ...?parsed?.queryParameters,
      ...uri.queryParameters,
      'token': token,
    };
    return uri.replace(queryParameters: query);
  }

  void close() {
    if (_ownsHttpClient) _http.close();
  }

  Future<http.Response> _run(
    Future<http.Response> Function() send,
    Uri uri,
  ) async {
    try {
      return await send().timeout(timeout);
    } on AbsException {
      rethrow;
    } on TimeoutException {
      throw AbsUnreachableException(
        'Could not reach the Audiobookshelf server at $baseUrl. '
        'Check the address and that the server is running.',
      );
    } on http.ClientException catch (error) {
      throw AbsUnreachableException(
        'Could not reach the Audiobookshelf server at $baseUrl '
        '(${error.message}).',
      );
    } on Object catch (error) {
      throw AbsUnreachableException(
        'Could not reach the Audiobookshelf server at $baseUrl ($error).',
      );
    }
  }

  void _ensureOk(http.Response response, Uri uri) {
    final status = response.statusCode;
    if (status >= 200 && status < 300) return;
    if (status == 401 || status == 403) {
      throw AbsUnauthorizedException(
        'The server rejected the token (HTTP $status). '
        'Check the API token in the Audiobookshelf settings.',
        statusCode: status,
      );
    }
    if (status == 404) {
      throw AbsNotFoundException(
        'The server has no such item (HTTP 404).',
        statusCode: status,
      );
    }
    if (status >= 500) {
      throw AbsServerErrorException(
        'The Audiobookshelf server failed (HTTP $status).',
        statusCode: status,
      );
    }
    throw AbsServerErrorException(
      'The server answered HTTP $status for ${uri.path}.',
      statusCode: status,
    );
  }

  Map<String, dynamic> _decode(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) return decoded;
    } on FormatException {
      // Falls through to the error below.
    }
    throw AbsServerErrorException(
      'The server returned an unexpected response.',
      statusCode: response.statusCode,
    );
  }

  static String _fnv1a(String input) {
    var hash = 0x811c9dc5;
    for (final byte in utf8.encode(input)) {
      hash ^= byte;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }
}
