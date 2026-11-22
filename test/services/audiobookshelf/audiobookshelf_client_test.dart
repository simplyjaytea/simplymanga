import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mangayomi/services/audiobookshelf/audiobookshelf_client.dart';

AudiobookshelfClient _client(
  Future<http.Response> Function(http.Request request) handler, {
  String baseUrl = 'http://abs.local:13378',
  String token = 'tok-123',
  Duration timeout = const Duration(seconds: 15),
}) {
  return AudiobookshelfClient(
    baseUrl: baseUrl,
    token: token,
    httpClient: MockClient(handler),
    timeout: timeout,
  );
}

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

Map<String, dynamic> _itemJson({String id = 'item-1'}) => {
  'id': id,
  'media': {
    'metadata': {
      'title': 'The Hobbit',
      'authorName': 'J. R. R. Tolkien',
      'coverPath': '/metadata/items/$id/cover.jpg',
    },
    'duration': 3600.5,
    'numTracks': 3,
    'tracks': [
      {
        'ino': '100',
        'contentUrl': '/api/items/$id/file/100',
        'mimeType': 'audio/mpeg',
        'duration': 1200.5,
        'metadata': {'title': 'Chapter 1'},
      },
      {
        'ino': '101',
        'contentUrl': '/api/items/$id/file/101',
        'mimeType': 'audio/mpeg',
        'duration': 1200.0,
        'metadata': {'title': 'Chapter 2'},
      },
      {
        'ino': '102',
        'contentUrl': '/api/items/$id/file/102',
        'mimeType': 'audio/mpeg',
        'duration': 1200.0,
        'metadata': {'title': 'Chapter 3'},
      },
    ],
  },
};

void main() {
  group('normalizeBaseUrl', () {
    test('adds a scheme and strips trailing slashes', () {
      expect(
        AudiobookshelfClient.normalizeBaseUrl('192.168.1.10:13378/'),
        'http://192.168.1.10:13378',
      );
      expect(
        AudiobookshelfClient.normalizeBaseUrl('  http://host:13378///  '),
        'http://host:13378',
      );
      expect(
        AudiobookshelfClient.normalizeBaseUrl('https://abs.example.com/abs/'),
        'https://abs.example.com/abs',
      );
    });

    test('keeps plain http, as a LAN server usually has no certificate', () {
      expect(
        AudiobookshelfClient.normalizeBaseUrl('http://192.168.0.4:13378'),
        'http://192.168.0.4:13378',
      );
    });

    test('rejects an empty URL', () {
      expect(
        () => AudiobookshelfClient.normalizeBaseUrl('   '),
        throwsArgumentError,
      );
    });
  });

  group('requests', () {
    test('me sends the bearer token and reads the user', () async {
      late http.Request captured;
      final client = _client((request) async {
        captured = request;
        return _json({
          'id': 'user-1',
          'username': 'ada',
          'email': 'ada@example.com',
        });
      });

      final user = await client.me();

      expect(captured.method, 'GET');
      expect(captured.url.toString(), 'http://abs.local:13378/api/me');
      expect(captured.headers['authorization'], 'Bearer tok-123');
      expect(user.id, 'user-1');
      expect(user.username, 'ada');
      expect(user.email, 'ada@example.com');
    });

    test('ping does not require a token, and surfaces reachability', () async {
      late http.Request captured;
      final client = _client((request) async {
        captured = request;
        return _json({'success': true});
      });

      await client.ping();

      expect(captured.url.path, '/api/ping');
      expect(captured.headers.containsKey('authorization'), isFalse);
    });

    test('libraries keeps book libraries and their media type', () async {
      final client = _client((request) async {
        expect(request.url.path, '/api/libraries');
        expect(request.headers['authorization'], 'Bearer tok-123');
        return _json({
          'libraries': [
            {'id': 'lib-1', 'name': 'Audiobooks', 'mediaType': 'book'},
            {'id': 'lib-2', 'name': 'Podcasts', 'mediaType': 'podcast'},
          ],
        });
      });

      final libraries = await client.libraries();

      expect(libraries, hasLength(2));
      expect(libraries.first.name, 'Audiobooks');
      expect(libraries.first.isBooks, isTrue);
      expect(libraries.last.isBooks, isFalse);
    });

    test('libraryItems asks for a page and parses the envelope', () async {
      late http.Request captured;
      final client = _client((request) async {
        captured = request;
        return _json({
          'results': [
            {
              'id': 'item-1',
              'media': {
                'metadata': {
                  'title': 'The Hobbit',
                  'authorName': 'J. R. R. Tolkien',
                  'coverPath': null,
                },
                'duration': 3600.5,
                'numTracks': 3,
              },
            },
            {
              'id': 'item-2',
              'media': {
                'metadata': {'title': 'Untitled draft'},
                'duration': 0,
                'numTracks': 0,
              },
            },
          ],
          'total': 120,
          'limit': 50,
          'page': 1,
        });
      });

      final page = await client.libraryItems('lib-1', page: 1);

      expect(captured.url.path, '/api/libraries/lib-1/items');
      expect(captured.url.queryParameters['page'], '1');
      expect(captured.url.queryParameters['limit'], '50');
      expect(captured.url.queryParameters['minified'], '1');
      expect(captured.url.queryParameters['sort'], 'media.metadata.title');
      expect(page.items, hasLength(2));
      expect(page.items.first.title, 'The Hobbit');
      expect(page.items.first.author, 'J. R. R. Tolkien');
      expect(page.items.first.coverPath, isNull);
      expect(page.items.first.duration, 3600.5);
      expect(page.items.first.numTracks, 3);
      // No author in the payload is not a crash: the row shows the fallback.
      expect(page.items.last.author, '');
      expect(page.total, 120);
      expect(page.page, 1);
      expect(page.hasMore, isTrue);
    });

    test('the last page has no more', () async {
      final client = _client(
        (request) async =>
            _json({'results': [], 'total': 50, 'limit': 50, 'page': 0}),
      );

      final page = await client.libraryItems('lib-1');

      expect(page.hasMore, isFalse);
    });
  });

  group('playback', () {
    test('startPlayback posts the device and player capabilities', () async {
      late http.Request captured;
      final client = _client((request) async {
        captured = request;
        return _json({
          'id': 'session-1',
          'currentTime': 42.5,
          'duration': 3600.5,
          'audioTracks': [
            {
              'contentUrl': '/api/items/item-1/file/100',
              'mimeType': 'audio/mpeg',
              'duration': 1200.5,
              'title': 'Chapter 1',
            },
          ],
        });
      });

      final session = await client.startPlayback('item-1');

      expect(captured.method, 'POST');
      expect(captured.url.path, '/api/items/item-1/play');
      expect(captured.headers['authorization'], 'Bearer tok-123');
      final body = jsonDecode(captured.body) as Map<String, dynamic>;
      final device = body['deviceInfo'] as Map<String, dynamic>;
      expect(device['deviceId'], startsWith('simplymanga-'));
      expect(device['clientName'], 'simplyMANGA');
      expect(device['clientVersion'], '0.9.97');
      expect(body['mediaPlayer'], 'media_kit');
      expect(body['forceDirectPlay'], isTrue);
      expect(
        (body['supportedMimeTypes'] as List).cast<String>(),
        containsAll(['audio/mpeg', 'audio/mp4', 'audio/flac']),
      );
      expect(session.id, 'session-1');
      expect(session.currentTime, 42.5);
      expect(session.duration, 3600.5);
      expect(session.audioTracks.single.title, 'Chapter 1');
    });

    test('the device id is stable for the same server and token', () {
      final a = _client((_) async => _json({}));
      final b = _client((_) async => _json({}));

      expect(a.deviceId, b.deviceId);
      expect(a.deviceId, startsWith('simplymanga-'));
    });

    test('item parses metadata and every track', () async {
      final client = _client((request) async {
        expect(request.url.path, '/api/items/item-1');
        return _json(_itemJson());
      });

      final item = await client.item('item-1');

      expect(item.title, 'The Hobbit');
      expect(item.author, 'J. R. R. Tolkien');
      expect(item.tracks, hasLength(3));
      expect(item.tracks.first.ino, '100');
      expect(item.tracks.first.contentUrl, '/api/items/item-1/file/100');
      expect(item.tracks.first.title, 'Chapter 1');
      expect(item.tracks.first.duration, 1200.5);
    });

    test('contentUrl resolves under the base path and carries the token', () {
      final client = _client(
        (_) async => _json({}),
        baseUrl: 'http://host:13378/abs',
      );

      expect(
        client.streamUri('/api/items/item-1/file/100').toString(),
        'http://host:13378/abs/api/items/item-1/file/100?token=tok-123',
      );
      expect(
        client.streamUri('api/items/item-1/file/100?x=1').toString(),
        'http://host:13378/abs/api/items/item-1/file/100?x=1&token=tok-123',
      );
    });

    test('an absolute contentUrl is used as is', () {
      final client = _client((_) async => _json({}));

      expect(
        client.streamUri('https://cdn.example/audio/1.mp3').toString(),
        'https://cdn.example/audio/1.mp3?token=tok-123',
      );
    });

    test('coverUri adds the token query', () {
      final client = _client((_) async => _json({}));

      expect(
        client.coverUri('item-1').toString(),
        'http://abs.local:13378/api/items/item-1/cover?token=tok-123',
      );
    });

    test('saveProgress PATCHes the exact payload', () async {
      late http.Request captured;
      final client = _client((request) async {
        captured = request;
        return _json({});
      });

      await client.saveProgress(
        'item-1',
        currentTime: 90.25,
        duration: 3600.5,
        isFinished: false,
      );

      expect(captured.method, 'PATCH');
      expect(captured.url.path, '/api/me/progress/item-1');
      expect(captured.headers['authorization'], 'Bearer tok-123');
      expect(jsonDecode(captured.body), {
        'currentTime': 90.25,
        'duration': 3600.5,
        'isFinished': false,
      });
    });

    test('saveProgress failures are best-effort and swallowed', () async {
      final client = _client((_) async => _json({'error': 'boom'}, 500));

      await expectLater(
        client.saveProgress('item-1', currentTime: 1, duration: 2),
        completes,
      );
    });
  });

  group('errors', () {
    test('401 maps to unauthorized with a readable message', () async {
      final client = _client((_) async => _json({'error': 'no'}, 401));

      await expectLater(
        client.me(),
        throwsA(
          isA<AbsUnauthorizedException>().having(
            (e) => e.message,
            'message',
            contains('token'),
          ),
        ),
      );
    });

    test('403 also maps to unauthorized', () async {
      final client = _client((_) async => _json({}, 403));

      await expectLater(
        client.libraries(),
        throwsA(isA<AbsUnauthorizedException>()),
      );
    });

    test('404 maps to notFound', () async {
      final client = _client((_) async => _json({}, 404));

      await expectLater(
        client.item('missing'),
        throwsA(isA<AbsNotFoundException>()),
      );
    });

    test('5xx maps to serverError with its status code', () async {
      final client = _client((_) async => _json({}, 503));

      await expectLater(
        client.me(),
        throwsA(
          isA<AbsServerErrorException>().having(
            (e) => e.statusCode,
            'statusCode',
            503,
          ),
        ),
      );
    });

    test('a timeout maps to unreachable', () async {
      final client = _client(
        (_) async => throw TimeoutException('slow'),
        timeout: const Duration(milliseconds: 5),
      );

      await expectLater(
        client.ping(),
        throwsA(
          isA<AbsUnreachableException>().having(
            (e) => e.message,
            'message',
            contains('reach'),
          ),
        ),
      );
    });

    test('a transport failure maps to unreachable', () async {
      final client = _client(
        (_) async => throw http.ClientException('connection refused'),
      );

      await expectLater(client.ping(), throwsA(isA<AbsUnreachableException>()));
    });

    test('malformed JSON maps to serverError', () async {
      final client = _client((_) async => http.Response('not json', 200));

      await expectLater(
        client.libraries(),
        throwsA(isA<AbsServerErrorException>()),
      );
    });
  });
}
