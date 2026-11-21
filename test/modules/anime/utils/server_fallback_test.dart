import 'package:flutter_test/flutter_test.dart';
import 'package:mangayomi/modules/anime/utils/server_fallback.dart';
import 'package:mangayomi/modules/anime/utils/video_prefs.dart';
import 'package:mangayomi/src/rust/api/anime_engine.dart';
import 'package:media_kit/media_kit.dart';

VideoPrefs _server(String url) => VideoPrefs(
  videoTrack: VideoTrack(url, url, url),
  isLocal: false,
);

void main() {
  group('shouldRouteToServerFallback', () {
    test('routes HTTP / transport / buffering failures', () {
      expect(shouldRouteToServerFallback('403 Forbidden'), isTrue);
      expect(
        shouldRouteToServerFallback('Failed to open https://x (timeout)'),
        isTrue,
      );
      expect(shouldRouteToServerFallback('Connection refused'), isTrue);
      expect(shouldRouteToServerFallback('error while buffering'), isTrue);
    });

    test('does NOT route audio-decoder errors (handled by audio fallback)', () {
      expect(
        shouldRouteToServerFallback(
          "Failed to initialize a decoder for codec 'eac3'",
        ),
        isFalse,
      );
      expect(shouldRouteToServerFallback('error decoding audio'), isFalse);
    });

    test('ignores empty / whitespace', () {
      expect(shouldRouteToServerFallback(''), isFalse);
      expect(shouldRouteToServerFallback('   '), isFalse);
    });
  });

  group('serverFallbackCandidates', () {
    final options = [
      _server('https://a'),
      _server('https://b'),
      _server('https://c'),
      VideoPrefs(videoTrack: VideoTrack.auto(), isLocal: true),
    ];

    test('excludes current server and local tracks, preserves order', () {
      final c = serverFallbackCandidates(
        options: options,
        currentUrl: 'https://a',
      );
      expect(c.map(serverUrlOf).toList(), ['https://b', 'https://c']);
    });

    test('excludes already-tried servers', () {
      final c = serverFallbackCandidates(
        options: options,
        currentUrl: 'https://a',
        triedUrls: {'https://b'},
      );
      expect(c.map(serverUrlOf).toList(), ['https://c']);
    });

    test('empty when everything tried', () {
      final c = serverFallbackCandidates(
        options: options,
        currentUrl: 'https://a',
        triedUrls: {'https://b', 'https://c'},
      );
      expect(c, isEmpty);
    });
  });

  group('planFromEngineAction', () {
    final options = [_server('https://a'), _server('https://b')];

    test('play maps to switching to that server', () {
      final plan = planFromEngineAction(
        const EngineAction.play(server: 'https://b'),
        options,
      );
      expect(plan, isA<SwitchServer>());
      expect(serverUrlOf((plan as SwitchServer).prefs), 'https://b');
    });

    test('retry maps to switching to that server', () {
      final plan = planFromEngineAction(
        const EngineAction.retry(server: 'https://a'),
        options,
      );
      expect(plan, isA<SwitchServer>());
    });

    test('awaitChallenge surfaces the challenge, never skips', () {
      final plan = planFromEngineAction(
        const EngineAction.awaitChallenge(server: 'https://a'),
        options,
      );
      expect(plan, isA<AwaitChallenge>());
      expect((plan as AwaitChallenge).server, 'https://a');
    });

    test('fail is an honest exhausted state', () {
      final plan = planFromEngineAction(
        const EngineAction.fail(reason: 'all servers failed'),
        options,
      );
      expect(plan, isA<FallbackExhausted>());
    });

    test('idle is a no-op', () {
      expect(
        planFromEngineAction(const EngineAction.idle(), options),
        isA<NoFallback>(),
      );
    });

    test('play for an unknown server is exhausted, not a crash', () {
      final plan = planFromEngineAction(
        const EngineAction.play(server: 'https://missing'),
        options,
      );
      expect(plan, isA<FallbackExhausted>());
    });
  });
}
