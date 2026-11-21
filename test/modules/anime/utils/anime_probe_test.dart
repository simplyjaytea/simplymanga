import 'package:flutter_test/flutter_test.dart';
import 'package:mangayomi/modules/anime/utils/anime_probe.dart';
import 'package:mangayomi/src/rust/api/anime_engine.dart';
import 'package:mangayomi/src/rust/engine/classify.dart';

void main() {
  group('buildProbeRequest', () {
    test('defaults to GET with the given url', () {
      final req = buildProbeRequest('https://host.example/a');
      expect(req.url, 'https://host.example/a');
      expect(req.method, 'GET');
    });

    test('honours an explicit method', () {
      expect(buildProbeRequest('https://h/', method: 'HEAD').method, 'HEAD');
    });
  });

  group('mapHttpResponse', () {
    test('lowercases header keys so the classifier can match them', () {
      final resp = mapHttpResponse(
        status: 403,
        headers: {'CF-Mitigated': 'challenge', 'Server': 'cloudflare'},
      );
      expect(resp.status, 403);
      expect(resp.headers, contains(('cf-mitigated', 'challenge')));
      expect(resp.headers, contains(('server', 'cloudflare')));
      expect(resp.error, isNull);
    });

    test('carries a body snippet for challenge detection', () {
      final resp = mapHttpResponse(
        status: 503,
        headers: const {},
        bodySnippet: 'Just a moment...',
      );
      expect(resp.bodySnippet, 'Just a moment...');
    });
  });

  group('mapProbeError', () {
    test('records the error string with no status', () {
      final resp = mapProbeError(StateError('dns lookup failed'));
      expect(resp.status, isNull);
      expect(resp.error, contains('dns lookup failed'));
      expect(resp.headers, isEmpty);
    });
  });

  group('bodySnippetOf', () {
    test('returns short bodies unchanged', () {
      expect(bodySnippetOf('hello'), 'hello');
    });

    test('truncates long bodies to the cap', () {
      final long = 'x' * 5000;
      expect(bodySnippetOf(long, maxChars: 512).length, 512);
    });
  });

  group('liveServerUrls', () {
    RankedServer r(String s, FailureClass c, double score) =>
        RankedServer(server: s, class_: c, score: score, latencyMs: 10);

    test('keeps only ok servers, preserving engine ranking order', () {
      final ranked = [
        r('https://best/', FailureClass.ok, 900),
        r('https://cf/', FailureClass.challenge, 800),
        r('https://good2/', FailureClass.ok, 700),
        r('https://dead/', FailureClass.deadHost, 100),
      ];
      expect(liveServerUrls(ranked), ['https://best/', 'https://good2/']);
    });

    test('empty when nothing is playable', () {
      expect(liveServerUrls([r('https://cf/', FailureClass.challenge, 1)]),
          isEmpty);
    });

    test('isPlayableClass is true only for ok', () {
      expect(isPlayableClass(FailureClass.ok), isTrue);
      expect(isPlayableClass(FailureClass.challenge), isFalse);
      expect(isPlayableClass(FailureClass.timeout), isFalse);
    });
  });
}
