import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' as riv;
import 'package:flutter_test/flutter_test.dart';
import 'package:mangayomi/models/video.dart' as vid;
import 'package:mangayomi/modules/anime/mixins/anime_track_selection_mixin.dart';
import 'package:mangayomi/modules/anime/utils/video_prefs.dart';
import 'package:mangayomi/src/rust/api/anime_engine.dart';
import 'package:media_kit/media_kit.dart';

/// Regression tests for the server-reliability integration in
/// [AnimeTrackSelectionMixin] (findings E-01, E-02, E-05, E-11).
///
/// The native FRB bridge is unavailable headless, so the harness overrides
/// the mixin's engine-creation seam with [_BudgetFakeEngine], which mirrors
/// the FIXED Rust semantics (rust/src/engine/state.rs + api report_class):
/// every report counts the failed attempt (start-before-error), a server
/// gets at most 2 tries, transient errors retry within budget, hard failures
/// advance in first-seen order (never re-picking the failed id), duplicates
/// are deduped, and exhaustion returns Fail.
void main() {
  const urlA = 'https://a.example/stream';
  const urlB = 'https://b.example/stream';

  vid.Video video(String url, String quality) => vid.Video(url, quality, url);

  group('E-01 — bounded retry budget on the wired path', () {
    testWidgets('two timeouts on one server retry once then switch, not loop', (
      tester,
    ) async {
      final engine = _BudgetFakeEngine([urlA, urlB]);
      final state = await _pumpHarness(
        tester,
        videos: [video(urlA, '1080p'), video(urlB, '720p')],
        engine: engine,
      );

      state.reportPlaybackError('tcp: Connection timed out');
      await _flush(tester);
      // Attempt 1 of 2: retry the SAME server (budget not yet spent).
      expect(engine.reports, hasLength(1));
      expect(state.opened.last.videoTrack!.id, urlA);

      state.reportPlaybackError('tcp: Connection timed out');
      await _flush(tester);
      // Attempt 2 of 2: budget spent -> advance to B, never reopen A again.
      expect(engine.reports, hasLength(2));
      expect(state.opened.last.videoTrack!.id, urlB);

      // A third failure on B must not resurrect an endless A<->B loop:
      // B gets its own bounded budget, then honest exhaustion.
      state.reportPlaybackError('tcp: Connection timed out');
      await _flush(tester);
      state.reportPlaybackError('tcp: Connection timed out');
      await _flush(tester);
      expect(engine.reports, hasLength(4));
      expect(state.opened, hasLength(4)); // initial + retry A + B + retry B
      expect(state.opened.last.videoTrack!.id, urlB);
    });

    testWidgets('a lone server exhausts after 2 tries instead of retrying '
        'forever', (tester) async {
      final engine = _BudgetFakeEngine([urlA]);
      final state = await _pumpHarness(
        tester,
        videos: [video(urlA, '1080p')],
        engine: engine,
      );

      state.reportPlaybackError('tcp: Connection timed out');
      await _flush(tester);
      expect(state.opened.last.videoTrack!.id, urlA); // one bounded retry

      state.reportPlaybackError('tcp: Connection timed out');
      await _flush(tester);
      // Fail: no further reopen of the same URL.
      expect(engine.reports, hasLength(2));
      expect(state.opened, hasLength(2)); // initial + the single retry
    });
  });

  group('E-02 — start watchdog (<2s switch contract)', () {
    testWidgets('a stalled open reports a timeout at ~2s and falls back', (
      tester,
    ) async {
      final engine = _BudgetFakeEngine([urlA, urlB]);
      final state = await _pumpHarness(
        tester,
        videos: [video(urlA, '1080p'), video(urlB, '720p')],
        engine: engine,
      );
      // Open A; playback never reaches playing (stalled stream). mpv's own
      // network-timeout is 5s — the watchdog must beat it.
      await state.openMediaFromTrackSelection(prefsFor(video(urlA, '1080p')));
      await tester.pump();

      await tester.pump(const Duration(milliseconds: 1900));
      expect(engine.reports, isEmpty, reason: 'watchdog must not fire early');

      await tester.pump(const Duration(milliseconds: 200)); // t = 2.1s
      await _flush(tester);
      expect(engine.reports, hasLength(1));
      expect(engine.reports.first.error.toLowerCase(), contains('timed out'));
      // First timeout spends attempt 1 -> bounded retry of A.
      expect(state.opened.last.videoTrack!.id, urlA);

      // The retry stalls too; the re-armed watchdog fires again ~2s later
      // and the budget is now spent -> switch to B well under mpv's 5s.
      await tester.pump(const Duration(seconds: 2));
      await _flush(tester);
      expect(engine.reports, hasLength(2));
      expect(state.opened.last.videoTrack!.id, urlB);
    });

    testWidgets('confirmed playing cancels the watchdog', (tester) async {
      final engine = _BudgetFakeEngine([urlA, urlB]);
      final state = await _pumpHarness(
        tester,
        videos: [video(urlA, '1080p'), video(urlB, '720p')],
        engine: engine,
      );
      // _pumpHarness already opened server A; confirm playback starts.
      state.player.playingValue = true;
      state.player.controls.playingController.add(true);
      await tester.pump();

      await tester.pump(const Duration(seconds: 10));
      expect(engine.reports, isEmpty);
      expect(state.opened, hasLength(1)); // never switched
    });

    testWidgets('dispose cleans the watchdog up (no late timeout)', (
      tester,
    ) async {
      final engine = _BudgetFakeEngine([urlA, urlB]);
      final state = await _pumpHarness(
        tester,
        videos: [video(urlA, '1080p'), video(urlB, '720p')],
        engine: engine,
      );
      await state.openMediaFromTrackSelection(prefsFor(video(urlA, '1080p')));
      await tester.pump();

      await tester.pumpWidget(
        const riv.ProviderScope(child: SizedBox.shrink()),
      );
      await tester.pump(const Duration(seconds: 10));
      expect(engine.reports, isEmpty);
    });
  });

  group('E-05 — engine reset on reselect; duplicate dedup', () {
    testWidgets('manual quality reselection rebuilds the engine with a fresh '
        'budget', (tester) async {
      final engines = <_BudgetFakeEngine>[];
      final state = await _pumpHarness(
        tester,
        videos: [video(urlA, '1080p'), video(urlB, '720p')],
        engineFactory: (servers) async {
          final e = _BudgetFakeEngine(servers);
          engines.add(e);
          return e;
        },
      );

      // Spend A's budget and land on B.
      state.reportPlaybackError('tcp: Connection timed out');
      await _flush(tester);
      state.reportPlaybackError('tcp: Connection timed out');
      await _flush(tester);
      expect(state.opened.last.videoTrack!.id, urlB);
      expect(engines, hasLength(1));

      // Manually reselect A through the TV quality list.
      final option = state.buildTvQualityOptions().firstWhere(
        (o) => o.label == '1080p',
      );
      option.onSelect();
      await _flush(tester);
      expect(state.opened.last.videoTrack!.id, urlA);

      // The reselect must have reset the machine: a fresh engine is built
      // on the next failure and A gets a full new budget (retry, not Fail).
      state.reportPlaybackError('tcp: Connection timed out');
      await _flush(tester);
      expect(engines, hasLength(2));
      expect(engines.last.reports, hasLength(1));
      expect(state.opened.last.videoTrack!.id, urlA); // bounded retry

      // Same reset through the pills-style quality options.
      final pill = state.tvQualityOptions().firstWhere(
        (o) => o.label == '720p',
      );
      pill.onTap();
      await _flush(tester);
      expect(state.opened.last.videoTrack!.id, urlB);
      state.reportPlaybackError('tcp: Connection timed out');
      await _flush(tester);
      expect(engines, hasLength(3));
      expect(engines.last.reports, hasLength(1));
    });

    testWidgets('duplicate server URLs are deduped before the engine sees '
        'them', (tester) async {
      final engine = _BudgetFakeEngine([urlA, urlA, urlB]);
      final state = await _pumpHarness(
        tester,
        videos: [
          video(urlA, '1080p'),
          video(urlA, '720p'), // same server, second quality
          video(urlB, '480p'),
        ],
        engine: engine,
      );
      state.reportPlaybackError('tcp: Connection timed out');
      await _flush(tester);
      expect(engine.servers.map((s) => s.id).toList(), [urlA, urlB]);
      // Two tries on A then straight to B — the duplicate never wastes a
      // cycle or re-picks the failed URL.
      state.reportPlaybackError('tcp: Connection timed out');
      await _flush(tester);
      expect(state.opened.last.videoTrack!.id, urlB);
    });
  });

  group('E-11 — concurrent error mid-fallback is queued, not dropped', () {
    testWidgets('the latest error arriving mid-switch is reprocessed after '
        'the switch completes', (tester) async {
      final engine = _BudgetFakeEngine([urlA, urlB]);
      final state = await _pumpHarness(
        tester,
        videos: [video(urlA, '1080p'), video(urlB, '720p')],
        engine: engine,
      );

      // Hold the first fallback pass open so a second error lands mid-flight.
      engine.gate = Completer<void>();
      state.reportPlaybackError('tcp: Connection timed out');
      await tester.pump();
      expect(engine.reports, hasLength(1));
      expect(state.serverFallbackInProgressForTest, isTrue);

      state.reportPlaybackError('tcp: Connection timed out');
      await tester.pump();
      // Queued, not processed yet — and crucially not discarded.
      expect(engine.reports, hasLength(1));

      engine.gate!.complete();
      await _flush(tester);
      // First pass retried A; the queued error was then reprocessed and
      // spent the budget -> advanced to B.
      expect(engine.reports, hasLength(2));
      expect(state.opened.last.videoTrack!.id, urlB);
      expect(state.serverFallbackInProgressForTest, isFalse);
    });
  });
}

VideoPrefs prefsFor(vid.Video v) => VideoPrefs(
  videoTrack: VideoTrack(v.url, v.quality, v.quality),
  headers: v.headers,
  isLocal: false,
);

/// Pumps a harness widget, opens the first server, and returns its state.
Future<_HarnessState> _pumpHarness(
  WidgetTester tester, {
  required List<vid.Video> videos,
  _BudgetFakeEngine? engine,
  Future<AnimeEngine> Function(List<String> servers)? engineFactory,
}) async {
  final factory =
      engineFactory ?? (servers) async => engine ?? _BudgetFakeEngine(servers);
  await tester.pumpWidget(
    riv.ProviderScope(
      child: _Harness(videos: videos, engineFactory: factory),
    ),
  );
  final state = tester.state<_HarnessState>(find.byType(_Harness));
  addTearDown(() {
    state.player.controls.close();
  });
  await state.openMediaFromTrackSelection(prefsFor(videos.first));
  await tester.pump();
  return state;
}

/// Flushes pending microtasks without advancing fake time (pumpAndSettle
/// would advance 100ms per pump and could fire the start watchdog).
Future<void> _flush(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump();
  }
}

class _FakePlayerStreams implements PlayerStream {
  final playingController = StreamController<bool>.broadcast();
  final playlistController = StreamController<Playlist>.broadcast();

  void close() {
    playingController.close();
    playlistController.close();
  }

  @override
  Stream<bool> get playing => playingController.stream;

  @override
  Stream<Playlist> get playlist => playlistController.stream;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePlayer implements Player {
  final controls = _FakePlayerStreams();
  bool playingValue = false;
  int stopCalls = 0;

  @override
  PlayerState get state => PlayerState(playing: playingValue);

  @override
  PlayerStream get stream => controls;

  @override
  Future<void> stop() async {
    stopCalls++;
    playingValue = false;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeServer {
  _FakeServer(this.id);
  final String id;
  String state = 'pending'; // pending | ready | playing | failed
  int attempts = 0;
}

/// Mirrors the fixed Rust engine; see the file-level doc comment.
class _BudgetFakeEngine implements AnimeEngine {
  _BudgetFakeEngine(List<String> servers) {
    for (final id in servers) {
      if (!this.servers.any((s) => s.id == id)) {
        this.servers.add(_FakeServer(id));
      }
    }
  }

  final List<_FakeServer> servers = [];
  final List<({String server, String error})> reports = [];

  /// When set, reportError awaits this before answering (E-11 test).
  Completer<void>? gate;

  static const int maxAttempts = 2;

  @override
  Future<EngineAction> reportError({
    required String server,
    required String error,
  }) async {
    reports.add((server: server, error: error));
    final g = gate;
    if (g != null) await g.future;
    final low = error.toLowerCase();
    // Same transient classes as the fixed classify_playback_error path.
    final transient =
        low.contains('timed out') ||
        low.contains('timeout') ||
        low.contains('500') ||
        low.contains('503');
    return _reportClass(server, transient);
  }

  EngineAction _reportClass(String id, bool transient) {
    final i = servers.indexWhere((s) => s.id == id);
    if (i < 0) return const EngineAction.idle();
    final s = servers[i];
    // E-01: report_class calls start() before on_error — the attempt that
    // just failed is counted even though the host never called start().
    s.attempts += 1;
    s.state = 'playing';
    if (transient && s.attempts < maxAttempts) {
      s.state = 'ready';
      return EngineAction.retry(server: id);
    }
    s.state = 'failed';
    // E-05: advance in order, never re-picking the id that just failed.
    for (final next in servers) {
      if (next.id != id &&
          (next.state == 'ready' || next.state == 'pending')) {
        next.state = 'playing';
        return EngineAction.play(server: next.id);
      }
    }
    return const EngineAction.fail(reason: 'all servers exhausted');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Harness extends riv.ConsumerStatefulWidget {
  const _Harness({required this.videos, required this.engineFactory});

  final List<vid.Video> videos;
  final Future<AnimeEngine> Function(List<String> servers) engineFactory;

  @override
  riv.ConsumerState<_Harness> createState() => _HarnessState();
}

class _HarnessState extends riv.ConsumerState<_Harness>
    with AnimeTrackSelectionMixin<_Harness> {
  final player = _FakePlayer();
  final prefs = ValueNotifier<VideoPrefs?>(null);
  final List<VideoPrefs> opened = [];

  @override
  Player get trackPlayer => player;

  @override
  List<vid.Video> get trackVideos => widget.videos;

  @override
  vid.Video get firstVideoForTracks => widget.videos.first;

  @override
  bool get isLocalForTracks => false;

  @override
  String get defaultSubtitleLanguage => '';

  @override
  bool get subtitlesOnByDefault => false;

  @override
  String get preferredAudioLanguagesCsv => '';

  @override
  ValueNotifier<VideoPrefs?> get selectedVideoPrefs => prefs;

  @override
  Future<void> openMediaFromTrackSelection(VideoPrefs p) async {
    opened.add(p);
    prefs.value = p;
    player.controls.playlistController.add(Playlist([Media(p.videoTrack!.id)]));
  }

  @override
  Future<AnimeEngine> createAnimeEngine(List<String> servers) =>
      widget.engineFactory(servers);

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
