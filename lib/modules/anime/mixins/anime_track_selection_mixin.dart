import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' as riv;
import 'package:mangayomi/models/video.dart' as vid;
import 'package:mangayomi/modules/anime/utils/audio_track_fallback.dart';
import 'package:mangayomi/modules/anime/utils/audio_track_label.dart';
import 'package:mangayomi/modules/anime/utils/server_fallback.dart';
import 'package:mangayomi/src/rust/api/anime_engine.dart';
import 'package:mangayomi/modules/anime/utils/player_labels.dart';
import 'package:mangayomi/modules/anime/utils/track_list_builder.dart';
import 'package:mangayomi/modules/anime/utils/video_prefs.dart';
import 'package:mangayomi/modules/anime/widgets/tv_player_pills.dart';
import 'package:mangayomi/utils/log/logger.dart';
import 'package:media_kit/media_kit.dart';

/// Manages audio and subtitle track resolution, language preference matching,
/// libmpv active track synchronization, audio decoder fallback recovery,
/// and TV track option builders.
mixin AnimeTrackSelectionMixin<T extends riv.ConsumerStatefulWidget>
    on riv.ConsumerState<T> {
  Player get trackPlayer;
  List<vid.Video> get trackVideos;
  vid.Video get firstVideoForTracks;
  bool get isLocalForTracks;
  String get defaultSubtitleLanguage;

  /// Off, an episode starts without subtitles until one is picked.
  bool get subtitlesOnByDefault;
  String get preferredAudioLanguagesCsv;
  ValueNotifier<VideoPrefs?> get selectedVideoPrefs;
  Future<void> openMediaFromTrackSelection(VideoPrefs prefs);

  bool initSubtitleAndAudio = true;
  SubtitleTrack? activeSubtitleTrack;
  AudioTrack? activeAudioTrack;
  final Set<String> _failedAudioTrackKeys = {};
  final Set<String> _failedAudioCodecs = {};
  String? _requestedAudioLanguage;
  bool _audioFallbackInProgress = false;
  bool _audioFallbackErrorQueued = false;

  // Server-level reliability (Lane A2). The Rust engine classifies failures and
  // drives fallback; these track tried servers and any pending anti-bot gate.
  AnimeEngine? _animeEngine;
  final Set<String> _triedServerUrls = {};
  bool _serverFallbackInProgress = false;
  String? _pendingChallengeServer;
  // E-11: latest error arriving while a server switch is in flight. Kept and
  // reprocessed after the pass completes (mirrors _audioFallbackErrorQueued).
  String? _serverFallbackErrorQueued;

  // E-02: start watchdog. mpv's network-timeout is 5s, so a stalled stream
  // would otherwise take >=5s to surface an error and miss the <2s switch
  // contract. If an open has not reached playing within this window, report
  // a Timeout to the engine so the bounded retry/fallback machinery advances.
  static const Duration serverStartWatchdogTimeout = Duration(seconds: 2);
  Timer? _startWatchdog;
  StreamSubscription<bool>? _playingWatchSub;
  StreamSubscription<Playlist>? _playlistWatchSub;

  /// A server awaiting an anti-bot challenge the user must clear (never skipped).
  String? get pendingChallengeServer => _pendingChallengeServer;

  /// Test seam: whether a server-fallback pass is currently in flight.
  @visibleForTesting
  bool get serverFallbackInProgressForTest => _serverFallbackInProgress;

  @override
  void initState() {
    super.initState();
    _playingWatchSub = trackPlayer.stream.playing.listen(_onPlayingForWatchdog);
    _playlistWatchSub = trackPlayer.stream.playlist.listen(
      _onPlaylistForWatchdog,
    );
  }

  @override
  void dispose() {
    _cancelStartWatchdog();
    unawaited(_playingWatchSub?.cancel());
    unawaited(_playlistWatchSub?.cancel());
    _playingWatchSub = null;
    _playlistWatchSub = null;
    super.dispose();
  }

  void _onPlayingForWatchdog(bool playing) {
    if (!playing) return;
    _cancelStartWatchdog();
    // E-05: confirmed playback is recovery — give any later failure a fresh
    // budget, unless a fallback switch is mid-flight (its engine must keep
    // counting the attempts it is making).
    if (!_serverFallbackInProgress) _resetServerFallbackState();
  }

  void _onPlaylistForWatchdog(Playlist playlist) => _armStartWatchdog();

  void _armStartWatchdog() {
    _cancelStartWatchdog();
    if (!mounted || isLocalForTracks) return;
    if (trackPlayer.state.playing) return;
    _startWatchdog = Timer(serverStartWatchdogTimeout, _onStartWatchdogTimeout);
  }

  void _cancelStartWatchdog() {
    _startWatchdog?.cancel();
    _startWatchdog = null;
  }

  void _onStartWatchdogTimeout() {
    _startWatchdog = null;
    if (!mounted || trackPlayer.state.playing) return;
    reportPlaybackError(
      'playback start timed out: no playing state within '
      '${serverStartWatchdogTimeout.inSeconds}s',
    );
  }

  /// E-05: drop the exhausted/stale machine so the next failure or a manual
  /// reselect starts a fresh sweep instead of failing forever.
  void _resetServerFallbackState() {
    _animeEngine = null;
    _triedServerUrls.clear();
    _pendingChallengeServer = null;
  }

  void initializeDefaultSubtitleAndAudioTracks() {
    if (!initSubtitleAndAudio) return;
    initSubtitleAndAudio = false;
    if (activeSubtitleTrack != null) {
      try {
        unawaited(setSubtitleTrack(activeSubtitleTrack!));
      } catch (_) {}
    } else if (!subtitlesOnByDefault) {
      unawaited(setSubtitleTrack(SubtitleTrack.no()));
    } else if (firstVideoForTracks.subtitles?.isNotEmpty ?? false) {
      try {
        final preferredSource = findPreferredSourceSubtitleTrack(
          firstVideoForTracks.subtitles!,
        );
        final defaultTrack =
            preferredSource ??
            firstVideoForTracks.subtitles!.firstWhere(
              (sub) => sub.label == defaultSubtitleLanguage,
              orElse: () => firstVideoForTracks.subtitles!.first,
            );
        final file = defaultTrack.file ?? "";
        final label = defaultTrack.label;
        final track = (file.startsWith("http") || file.startsWith("file"))
            ? SubtitleTrack.uri(file, title: label, language: label)
            : SubtitleTrack.data(file, title: label, language: label);
        unawaited(setSubtitleTrack(track));
      } catch (_) {}
    } else {
      unawaited(syncActiveSubtitleTrackFromMpv());
    }

    if (activeAudioTrack != null) {
      try {
        unawaited(setAudioTrack(activeAudioTrack!));
      } catch (_) {}
    } else if (firstVideoForTracks.audios?.isNotEmpty ?? false) {
      try {
        final preferredSource = findPreferredSourceAudioTrack(
          firstVideoForTracks.audios!,
        );
        final at = preferredSource ?? firstVideoForTracks.audios!.first;
        final track = AudioTrack.uri(
          at.file ?? "",
          title: at.label,
          language: at.label,
        );
        activeAudioTrack = track;
        unawaited(setAudioTrack(track));
      } catch (_) {}
    } else {
      unawaited(syncActiveAudioTrackFromMpv());
    }
  }

  SubtitleTrack? get effectiveSubtitleTrack {
    if (activeSubtitleTrack != null && activeSubtitleTrack!.id == 'no') {
      return activeSubtitleTrack;
    }
    final playerSubtitle = trackPlayer.state.track.subtitle;
    if (playerSubtitle.id == 'no') {
      return playerSubtitle;
    }
    if (activeSubtitleTrack != null && activeSubtitleTrack!.id != 'auto') {
      return activeSubtitleTrack;
    }
    if (playerSubtitle.id != 'auto') {
      return playerSubtitle;
    }
    final tracks = trackPlayer.state.tracks.subtitle
        .where((t) => t.id != 'auto' && t.id != 'no')
        .toList();
    if (tracks.isNotEmpty) {
      final preferred = _findPreferredSubtitleTrack(tracks);
      if (preferred != null) return preferred;
    }
    final extSubs = firstVideoForTracks.subtitles;
    if (extSubs != null && extSubs.isNotEmpty) {
      final preferredExt = findPreferredSourceSubtitleTrack(extSubs);
      final st = preferredExt ?? extSubs.first;
      final file = st.file ?? '';
      return (file.startsWith('http') || file.startsWith('file'))
          ? SubtitleTrack.uri(file, title: st.label, language: st.label)
          : SubtitleTrack.data(file, title: st.label, language: st.label);
    }
    return activeSubtitleTrack ?? playerSubtitle;
  }

  SubtitleTrack? _findPreferredSubtitleTrack(List<SubtitleTrack> tracks) {
    if (tracks.isEmpty) return null;
    final pref = defaultSubtitleLanguage.trim().toLowerCase();
    if (pref.isNotEmpty && pref != 'auto') {
      for (final track in tracks) {
        if (track.id == 'no' || track.id == 'auto') continue;
        if (audioTrackLanguagesMatch(track.language, pref) ||
            audioTrackLanguagesMatch(track.title, pref)) {
          return track;
        }
      }
    }
    return tracks.firstWhere(
      (t) => t.id != 'no' && t.id != 'auto',
      orElse: () => tracks.first,
    );
  }

  vid.Track? findPreferredSourceSubtitleTrack(List<vid.Track> tracks) {
    if (tracks.isEmpty) return null;
    final pref = defaultSubtitleLanguage.trim().toLowerCase();
    if (pref.isNotEmpty && pref != 'auto') {
      for (final track in tracks) {
        if (audioTrackLanguagesMatch(track.label, pref)) {
          return track;
        }
      }
    }
    return null;
  }

  bool isSubtitleTrackSelected(
    SubtitleTrack? candidate,
    SubtitleTrack? effective,
  ) {
    if (candidate == null || effective == null) return false;
    if (candidate.id == 'auto' || candidate.id == 'no') return false;
    if (effective.id == 'auto' || effective.id == 'no') return false;
    if (candidate.id == effective.id) return true;
    if (candidate.title != null &&
        candidate.title!.isNotEmpty &&
        candidate.title == effective.title) {
      return true;
    }
    return false;
  }

  Future<void> syncActiveSubtitleTrackFromMpv() async {
    if (!mounted) return;
    try {
      final active = await _activeSubtitleTrackFn();
      if (!mounted) return;
      if (active.id != 'auto') {
        if (activeSubtitleTrack?.id != active.id ||
            activeSubtitleTrack?.title != active.title ||
            activeSubtitleTrack?.language != active.language) {
          if (mounted) {
            setState(() {
              activeSubtitleTrack = active;
            });
          }
        }
      }
    } catch (_) {}
  }

  Future<void> setSubtitleTrack(SubtitleTrack track) async {
    activeSubtitleTrack = track;
    await trackPlayer.setSubtitleTrack(track);
  }

  Future<SubtitleTrack> _activeSubtitleTrackFn() async {
    final selectedSub = trackPlayer.state.track.subtitle;
    if (selectedSub.id != 'auto' && selectedSub.id != 'no') {
      return selectedSub;
    }

    final platform = trackPlayer.platform;
    if (platform is! NativePlayer) return selectedSub;
    final sid = await _nativeAudioProperty(platform, 'sid');
    final explicitlySelected = _subtitleTrackForNativeId(sid);
    if (explicitlySelected != null) return explicitlySelected;
    final activeId = await _nativeAudioProperty(
      platform,
      'current-tracks/sub/id',
    );
    return _subtitleTrackForNativeId(activeId) ?? selectedSub;
  }

  SubtitleTrack? _subtitleTrackForNativeId(String? id) {
    if (id == null || id == 'auto' || id == '-1') return null;
    if (id == 'no') return SubtitleTrack.no();
    for (final track in trackPlayer.state.tracks.subtitle) {
      if (track.id == id) return track;
    }
    return SubtitleTrack(id, null, null);
  }

  AudioTrack? get effectiveAudioTrack {
    if (activeAudioTrack != null && activeAudioTrack!.id == 'no') {
      return activeAudioTrack;
    }
    final playerAudio = trackPlayer.state.track.audio;
    if (playerAudio.id == 'no') {
      return playerAudio;
    }
    if (activeAudioTrack != null && activeAudioTrack!.id != 'auto') {
      return activeAudioTrack;
    }
    if (playerAudio.id != 'auto') {
      return playerAudio;
    }
    final tracks = trackPlayer.state.tracks.audio
        .where((t) => t.id != 'auto' && t.id != 'no')
        .toList();
    if (tracks.isNotEmpty) {
      final preferred = _findPreferredAudioTrack(tracks);
      if (preferred != null) return preferred;
    }
    final extAudios = firstVideoForTracks.audios;
    if (extAudios != null && extAudios.isNotEmpty) {
      final preferredExt = findPreferredSourceAudioTrack(extAudios);
      final at = preferredExt ?? extAudios.first;
      return AudioTrack.uri(at.file ?? '', title: at.label, language: at.label);
    }
    return activeAudioTrack ?? playerAudio;
  }

  AudioTrack? _findPreferredAudioTrack(List<AudioTrack> tracks) {
    if (tracks.isEmpty) return null;
    final preferredList = preferredAudioLanguagesCsv
        .split(',')
        .map((l) => l.trim().toLowerCase())
        .where((l) => l.isNotEmpty && l != 'auto')
        .toList();
    for (final pref in preferredList) {
      for (final track in tracks) {
        if (track.id == 'no' || track.id == 'auto') continue;
        if (audioTrackLanguagesMatch(track.language, pref) ||
            audioTrackLanguagesMatch(track.title, pref)) {
          return track;
        }
      }
    }
    return tracks.firstWhere(
      (t) => t.id != 'no' && t.id != 'auto',
      orElse: () => tracks.first,
    );
  }

  vid.Track? findPreferredSourceAudioTrack(List<vid.Track> tracks) {
    if (tracks.isEmpty) return null;
    final preferredList = preferredAudioLanguagesCsv
        .split(',')
        .map((l) => l.trim().toLowerCase())
        .where((l) => l.isNotEmpty && l != 'auto')
        .toList();
    for (final pref in preferredList) {
      for (final track in tracks) {
        if (audioTrackLanguagesMatch(track.label, pref)) {
          return track;
        }
      }
    }
    return null;
  }

  bool isAudioTrackSelected(AudioTrack? candidate, AudioTrack? effective) {
    if (candidate == null || effective == null) return false;
    if (candidate.id == 'auto' || candidate.id == 'no') return false;
    if (effective.id == 'auto' || effective.id == 'no') return false;
    if (candidate.id == effective.id) return true;
    if (candidate.title != null &&
        candidate.title!.isNotEmpty &&
        candidate.title == effective.title) {
      return true;
    }
    return false;
  }

  Future<void> syncActiveAudioTrackFromMpv() async {
    if (!mounted) return;
    try {
      final active = await _activeAudioTrackFn();
      if (!mounted) return;
      if (active.id != 'auto') {
        if (activeAudioTrack?.id != active.id ||
            activeAudioTrack?.title != active.title ||
            activeAudioTrack?.language != active.language) {
          if (mounted) {
            setState(() {
              activeAudioTrack = active;
            });
          }
        }
      }
    } catch (_) {}
  }

  Future<void> setAudioTrack(AudioTrack track) async {
    resetAudioFallbackState();
    _requestedAudioLanguage = track.language ?? _preferredAudioLanguage();
    activeAudioTrack = track;
    await trackPlayer.setAudioTrack(track);
  }

  String? _preferredAudioLanguage() {
    for (final language in preferredAudioLanguagesCsv.split(',')) {
      final value = language.trim();
      if (value.isNotEmpty) return value;
    }
    return null;
  }

  List<AudioTrack> _audioTracksForFallback() {
    final tracks = trackPlayer.state.tracks.audio.toList();
    for (final sourceTrack
        in firstVideoForTracks.audios ?? const <vid.Track>[]) {
      final file = sourceTrack.file;
      if (file == null || file.isEmpty) continue;
      tracks.add(
        AudioTrack.uri(
          file,
          title: sourceTrack.label,
          language: sourceTrack.label,
        ),
      );
    }
    return tracks;
  }

  void resetAudioFallbackState({bool resetRequestedLanguage = false}) {
    _failedAudioTrackKeys.clear();
    _failedAudioCodecs.clear();
    _audioFallbackErrorQueued = false;
    if (resetRequestedLanguage) _requestedAudioLanguage = null;
  }

  Future<AudioTrack> _activeAudioTrackFn() async {
    final selectedAudio = trackPlayer.state.track.audio;
    if (selectedAudio.id != 'auto' && selectedAudio.id != 'no') {
      return selectedAudio;
    }

    final platform = trackPlayer.platform;
    if (platform is! NativePlayer) return selectedAudio;
    final aid = await _nativeAudioProperty(platform, 'aid');
    final explicitlySelected = _audioTrackForNativeId(aid);
    if (explicitlySelected != null) return explicitlySelected;
    final activeId = await _nativeAudioProperty(
      platform,
      'current-tracks/audio/id',
    );
    return _audioTrackForNativeId(activeId) ?? selectedAudio;
  }

  Future<String?> _nativeAudioProperty(
    NativePlayer platform,
    String property,
  ) async {
    try {
      final value = (await platform.getProperty(property)).trim();
      return value.isEmpty ? null : value;
    } catch (_) {
      return null;
    }
  }

  Future<String?> _nativePreferredAudioLanguage() async {
    final platform = trackPlayer.platform;
    if (platform is! NativePlayer) return null;
    final alang = await _nativeAudioProperty(platform, 'alang');
    for (final language in alang?.split(',') ?? const <String>[]) {
      final value = language.trim();
      if (value.isNotEmpty && value != 'auto') return value;
    }
    return null;
  }

  AudioTrack? _audioTrackForNativeId(String? id) {
    if (id == null || id == 'auto' || id == 'no' || id == '-1') return null;
    for (final track in trackPlayer.state.tracks.audio) {
      if (track.id == id) return track;
    }
    return AudioTrack(id, null, null);
  }

  bool _isVideoDecoderError(String? codec, AudioTrack activeAudio) {
    final normalized = codec?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) return false;
    if (activeAudio.codec?.trim().toLowerCase() == normalized) return false;
    final hasAudioCodec = trackPlayer.state.tracks.audio.any(
      (track) => track.codec?.trim().toLowerCase() == normalized,
    );
    final hasVideoCodec = trackPlayer.state.tracks.video.any(
      (track) => track.codec?.trim().toLowerCase() == normalized,
    );
    return hasVideoCodec && !hasAudioCodec;
  }

  void reportPlaybackError(String error) {
    final message = error.trim();
    if (message.isEmpty) return;
    if (isAudioDecoderInitializationError(message)) {
      if (_audioFallbackInProgress) {
        _audioFallbackErrorQueued = true;
        return;
      }
      unawaited(_recoverFromAudioDecoderError(message));
      return;
    }
    // Every other failure (403, dead stream, timeout, buffering) used to be
    // silently dropped. Route it to the reliability engine for server fallback.
    unawaited(_recoverFromServerError(message));
  }

  /// Test seam: build the native engine. Headless tests override this because
  /// the FRB bridge is unavailable there.
  Future<AnimeEngine> createAnimeEngine(List<String> servers) =>
      AnimeEngine.newInstance(servers: servers);

  Future<AnimeEngine?> _ensureAnimeEngine(List<VideoPrefs> options) async {
    if (_animeEngine != null) return _animeEngine;
    try {
      final servers = options.map(serverUrlOf).whereType<String>().toList();
      if (servers.isEmpty) return null;
      _animeEngine = await createAnimeEngine(servers);
      return _animeEngine;
    } catch (_) {
      // Native bridge unavailable (e.g. headless test): fall back to pure Dart.
      return null;
    }
  }

  Future<void> _recoverFromServerError(String message) async {
    if (_serverFallbackInProgress) {
      // E-11: keep the latest concurrent error and reprocess it after the
      // in-flight pass, instead of silently dropping it (the audio path
      // already does this via _audioFallbackErrorQueued).
      _serverFallbackErrorQueued = message;
      return;
    }
    _serverFallbackInProgress = true;
    try {
      final options = buildVideoQualityOptions(
        player: trackPlayer,
        videos: trackVideos,
        isLocal: isLocalForTracks,
      );
      final currentPrefs = selectedVideoPrefs.value;
      final currentUrl = currentPrefs == null ? null : serverUrlOf(currentPrefs);
      if (currentUrl != null) _triedServerUrls.add(currentUrl);

      final engine = await _ensureAnimeEngine(options);
      EngineAction action;
      if (engine != null && currentUrl != null) {
        action = await engine.reportError(server: currentUrl, error: message);
      } else {
        final candidates = serverFallbackCandidates(
          options: options,
          currentUrl: currentUrl,
          triedUrls: _triedServerUrls,
        );
        action = candidates.isEmpty
            ? const EngineAction.fail(reason: 'all servers failed')
            : EngineAction.play(server: serverUrlOf(candidates.first)!);
      }

      final plan = planFromEngineAction(action, options);
      // The current open is dead or being replaced; its watchdog must not
      // fire into the next server's startup (E-02).
      _cancelStartWatchdog();
      switch (plan) {
        case SwitchServer(:final prefs):
          AppLogger.log(
            'Playback failed ($message); switching server to '
            '${serverUrlOf(prefs)}.',
            logLevel: LogLevel.warning,
          );
          await openMediaFromTrackSelection(prefs);
          _armStartWatchdog();
        case AwaitChallenge(:final server):
          _pendingChallengeServer = server;
          AppLogger.log(
            'Playback gated by an anti-bot challenge on $server; awaiting user.',
            logLevel: LogLevel.warning,
          );
        case FallbackExhausted(:final reason):
          AppLogger.log(
            'Playback fallback exhausted: $reason ($message)',
            logLevel: LogLevel.error,
          );
          // E-05: an exhausted machine must not poison later attempts —
          // reset so a reselect or a new error starts a fresh sweep.
          _resetServerFallbackState();
        case NoFallback():
          break;
      }
    } catch (error, stackTrace) {
      AppLogger.log(
        'Server fallback failed: $error\n$stackTrace',
        logLevel: LogLevel.error,
      );
    } finally {
      _serverFallbackInProgress = false;
      // E-11: reprocess the latest error that arrived mid-switch.
      final queued = _serverFallbackErrorQueued;
      _serverFallbackErrorQueued = null;
      if (queued != null) unawaited(_recoverFromServerError(queued));
    }
  }

  Future<void> _recoverFromAudioDecoderError(String message) async {
    _audioFallbackInProgress = true;
    try {
      final failedTrack = await _activeAudioTrackFn();
      final failedCodec = audioDecoderCodecFromError(message);
      if (_isVideoDecoderError(failedCodec, failedTrack)) return;

      _failedAudioTrackKeys.add(audioTrackFallbackKey(failedTrack));
      if (failedCodec != null) {
        _failedAudioCodecs.add(failedCodec.toLowerCase());
      }
      final requestedLanguage =
          failedTrack.language ??
          _requestedAudioLanguage ??
          _preferredAudioLanguage() ??
          await _nativePreferredAudioLanguage();
      final candidates = audioTrackFallbackCandidates(
        failedTrack: failedTrack,
        availableTracks: _audioTracksForFallback(),
        requestedLanguage: requestedLanguage,
        failedTrackKeys: _failedAudioTrackKeys,
        failedCodecs: _failedAudioCodecs,
      );
      if (candidates.isEmpty) return;

      final fallback = candidates.first;
      _requestedAudioLanguage = requestedLanguage;
      AppLogger.log(
        'Audio decoder failed for ${audioTrackLabel(failedTrack)}; '
        'trying ${audioTrackLabel(fallback)}.',
        logLevel: LogLevel.warning,
      );
      await trackPlayer.setAudioTrack(fallback);
    } catch (error, stackTrace) {
      AppLogger.log(
        'Audio track fallback failed: $error\n$stackTrace',
        logLevel: LogLevel.error,
      );
    } finally {
      _audioFallbackInProgress = false;
      if (_audioFallbackErrorQueued) {
        _audioFallbackErrorQueued = false;
        unawaited(_recoverFromAudioDecoderError(message));
      }
    }
  }

  List<({String label, bool selected, VoidCallback onTap})> tvQualityOptions() {
    final videoQuality = buildVideoQualityOptions(
      player: trackPlayer,
      videos: trackVideos,
      isLocal: isLocalForTracks,
    );
    return videoQuality.map((quality) {
      final selected =
          selectedVideoPrefs.value!.videoTrack!.title ==
              quality.videoTrack!.title ||
          isLocalForTracks;
      return (
        label: isLocalForTracks
            ? firstVideoForTracks.quality
            : quality.videoTrack!.title!,
        selected: selected,
        onTap: () {
          if (selectedVideoPrefs.value?.videoTrack?.id ==
              quality.videoTrack?.id) {
            return;
          }
          // E-05: a deliberate reselect starts a fresh reliability sweep.
          _resetServerFallbackState();
          selectedVideoPrefs.value = quality;
          trackPlayer.stop();
          if (quality.isLocal) {
            if (isLocalForTracks) {
              trackPlayer.setVideoTrack(quality.videoTrack!);
            } else {
              openMediaFromTrackSelection(quality);
            }
          } else {
            openMediaFromTrackSelection(quality);
          }
          initSubtitleAndAudio = true;
        },
      );
    }).toList();
  }

  List<({String label, bool selected, VoidCallback onTap})>
  tvSubtitleOptions() {
    final uniqueSubtitle = buildUniqueSubtitleOptions(
      player: trackPlayer,
      videos: trackVideos,
      isLocal: isLocalForTracks,
    );
    final effective = effectiveSubtitleTrack;
    return uniqueSubtitle.map((sub) {
      final isNone = sub.subtitle?.id == 'no';
      final title = isNone
          ? 'Off'
          : (sub.title ?? subtitleTrackLabel(sub.subtitle));
      final selected = isNone
          ? (effective == null || effective.id == 'no')
          : isSubtitleTrackSelected(sub.subtitle, effective);
      return (
        label: title,
        selected: selected,
        onTap: () {
          try {
            unawaited(setSubtitleTrack(sub.subtitle!));
          } catch (_) {}
        },
      );
    }).toList();
  }

  List<({String label, bool selected, VoidCallback onTap})> tvAudioOptions() {
    final uniqueAudio = buildUniqueAudioOptions(
      player: trackPlayer,
      videos: trackVideos,
      isLocal: isLocalForTracks,
    );
    final effective = effectiveAudioTrack;
    return uniqueAudio.map((aud) {
      final isNone = aud.audio?.id == "no";
      final title = isNone ? "Off" : (aud.title ?? audioTrackLabel(aud.audio));
      final selected = isNone
          ? (effective == null || effective.id == "no")
          : isAudioTrackSelected(aud.audio, effective);
      return (
        label: title,
        selected: selected,
        onTap: () {
          try {
            activeAudioTrack = aud.audio!;
            unawaited(setAudioTrack(aud.audio!));
          } catch (_) {}
        },
      );
    }).toList();
  }

  List<TvTrackOption> buildTvQualityOptions() {
    if (isLocalForTracks || trackVideos.isEmpty) return const <TvTrackOption>[];
    final currentTitle = selectedVideoPrefs.value?.videoTrack?.title;
    return [
      for (final video in trackVideos)
        TvTrackOption(
          label: shortQualityLabel(video.quality),
          selected: currentTitle == video.quality,
          onSelect: () {
            if (selectedVideoPrefs.value?.videoTrack?.title == video.quality) {
              return;
            }
            // E-05: a deliberate reselect starts a fresh reliability sweep.
            _resetServerFallbackState();
            final prefs = VideoPrefs(
              videoTrack: VideoTrack(video.url, video.quality, video.quality),
              headers: video.headers,
              isLocal: false,
            );
            selectedVideoPrefs.value = prefs;
            trackPlayer.stop();
            openMediaFromTrackSelection(prefs);
            initSubtitleAndAudio = true;
          },
        ),
    ];
  }
}
