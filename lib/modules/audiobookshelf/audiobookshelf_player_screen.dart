import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shiori/shiori.dart';

import 'package:mangayomi/modules/audiobookshelf/abs_playback_math.dart';
import 'package:mangayomi/modules/audiobookshelf/audiobookshelf_shared.dart';
import 'package:mangayomi/services/audiobookshelf/audiobookshelf_client.dart';
import 'package:mangayomi/services/audiobookshelf/audiobookshelf_models.dart';
import 'package:mangayomi/services/audiobookshelf/audiobookshelf_settings.dart';
import 'package:mangayomi/utils/platform_utils.dart';

/// An audiobook's player: one file open at a time, one position for the whole
/// book.
///
/// ABS sends a book-level resume position and a list of files; this screen
/// maps between them, plays the files in order, and reports progress back on
/// pause, at the end and on the way out. A failed progress save is never
/// shown: playback is the task, syncing is a courtesy.
class AudiobookshelfPlayerScreen extends ConsumerStatefulWidget {
  const AudiobookshelfPlayerScreen({super.key, required this.item});

  final AbsLibraryItem item;

  @override
  ConsumerState<AudiobookshelfPlayerScreen> createState() =>
      _AudiobookshelfPlayerScreenState();
}

class _AudiobookshelfPlayerScreenState
    extends ConsumerState<AudiobookshelfPlayerScreen> {
  late final Player _player = Player();

  final List<_PlaybackTrack> _tracks = [];
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  AudiobookshelfClient? _client;

  int _index = 0;
  Duration _position = Duration.zero;
  Duration _trackDuration = Duration.zero;
  bool _playing = false;
  bool _wasPlaying = false;
  bool _loading = true;
  bool _opening = false;
  bool _finished = false;
  String? _error;
  double? _dragValue;

  @override
  void initState() {
    super.initState();
    _player.setVolume(100.0);
    _subscriptions.add(
      _player.stream.position.listen((position) {
        if (!mounted) return;
        setState(() => _position = position);
      }),
    );
    _subscriptions.add(
      _player.stream.duration.listen((duration) {
        if (!mounted || duration <= Duration.zero) return;
        setState(() => _trackDuration = duration);
      }),
    );
    _subscriptions.add(
      _player.stream.playing.listen((playing) {
        if (!mounted) return;
        setState(() => _playing = playing);
        // A pause is the natural moment to tell the server where the reader
        // is; the resume after a pause must not save the old position again.
        if (_wasPlaying && !playing) {
          unawaited(_saveProgress());
        }
        _wasPlaying = playing;
      }),
    );
    _subscriptions.add(
      _player.stream.completed.listen((completed) {
        if (!mounted || !completed) return;
        if (_index + 1 < _tracks.length) {
          unawaited(_openTrack(_index + 1));
        } else {
          setState(() => _finished = true);
          unawaited(_saveProgress(isFinished: true));
        }
      }),
    );
    _subscriptions.add(
      _player.stream.error.listen((message) {
        if (!mounted) return;
        setState(() => _error = 'Playback failed: $message');
      }),
    );
    _load();
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    // Fire and forget: the provider still holds the client while this runs,
    // and the client swallows a failed save itself.
    unawaited(_saveProgress());
    unawaited(_player.dispose());
    super.dispose();
  }

  Future<void> _load() async {
    final client = ref.read(absClientProvider);
    setState(() {
      _loading = true;
      _error = null;
      _finished = false;
    });
    if (client == null) {
      setState(() {
        _loading = false;
        _error = 'No Audiobookshelf server is saved.';
      });
      return;
    }
    _client = client;
    try {
      final item = await client.item(widget.item.id);
      final session = await client.startPlayback(widget.item.id);
      if (!mounted) return;
      _tracks
        ..clear()
        ..addAll(_playlist(item, session));
      if (_tracks.isEmpty) {
        setState(() {
          _loading = false;
          _error = 'This book has no audio files.';
        });
        return;
      }
      final resume = locatePosition([
        for (final track in _tracks) track.duration,
      ], Duration(milliseconds: (session.currentTime * 1000).round()));
      setState(() {
        _loading = false;
        _trackDuration = _tracks[resume.index].duration;
      });
      await _openTrack(resume.index, start: resume.offset);
    } on AbsException catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.message;
      });
    }
  }

  List<_PlaybackTrack> _playlist(AbsItem item, AbsPlaybackSession session) {
    final fromSession = [
      for (var index = 0; index < session.audioTracks.length; index++)
        if (session.audioTracks[index].contentUrl.trim().isNotEmpty)
          _PlaybackTrack(
            title: _titleFor(session.audioTracks[index].title, item, index),
            uri: _client!.streamUri(session.audioTracks[index].contentUrl),
            duration: Duration(
              milliseconds: (session.audioTracks[index].duration * 1000)
                  .round(),
            ),
          ),
    ];
    if (fromSession.isNotEmpty) return fromSession;
    return [
      for (var index = 0; index < item.tracks.length; index++)
        if (item.tracks[index].contentUrl.trim().isNotEmpty)
          _PlaybackTrack(
            title: _titleFor(item.tracks[index].title, item, index),
            uri: _client!.streamUri(item.tracks[index].contentUrl),
            duration: Duration(
              milliseconds: (item.tracks[index].duration * 1000).round(),
            ),
          ),
    ];
  }

  /// Session tracks sometimes carry the generic `Track N` name while the
  /// item's own tracks have the chapter title; prefer the latter.
  String _titleFor(String sessionTitle, AbsItem item, int index) {
    if (index < item.tracks.length &&
        (sessionTitle.startsWith('Track ') || sessionTitle.isEmpty)) {
      return item.tracks[index].title;
    }
    return sessionTitle;
  }

  Future<void> _openTrack(int index, {Duration start = Duration.zero}) async {
    if (index < 0 || index >= _tracks.length || _opening) return;
    _opening = true;
    setState(() {
      _index = index;
      _position = start;
      _trackDuration = _tracks[index].duration;
      _error = null;
      _finished = false;
    });
    try {
      await _player.open(
        Media(_tracks[index].uri.toString(), start: start),
        play: true,
      );
    } on Object catch (error) {
      if (mounted) setState(() => _error = 'Playback failed: $error');
    } finally {
      _opening = false;
    }
  }

  Future<void> _togglePlay() async {
    if (_tracks.isEmpty) return;
    if (_playing) {
      await _player.pause();
    } else {
      if (_position >= _trackDuration && _index == _tracks.length - 1) {
        await _openTrack(_index, start: Duration.zero);
      } else {
        await _player.play();
      }
    }
  }

  Duration get _bookDuration => Duration(
    milliseconds: _tracks.fold<int>(
      0,
      (sum, track) => sum + track.duration.inMilliseconds,
    ),
  );

  Duration get _bookPosition => absolutePosition(
    [for (final track in _tracks) track.duration],
    _index,
    _position,
  );

  Future<void> _saveProgress({bool isFinished = false}) async {
    final client = _client;
    if (client == null || _tracks.isEmpty) return;
    await client.saveProgress(
      widget.item.id,
      currentTime: _bookPosition.inMilliseconds / 1000,
      duration: _bookDuration.inMilliseconds / 1000,
      isFinished: isFinished,
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.shiori;
    final track = _tracks.isEmpty ? null : _tracks[_index];
    final duration = _trackDuration > Duration.zero
        ? _trackDuration
        : (track?.duration ?? Duration.zero);
    final max = duration.inMilliseconds.toDouble();
    final value =
        _dragValue ?? _position.inMilliseconds.toDouble().clamp(0, max);
    return Scaffold(
      appBar: AppBar(title: Text(widget.item.title)),
      body: _loading
          ? const ShioriLoading(label: 'Opening the book…')
          : _error != null && _tracks.isEmpty
          ? ShioriErrorState(
              title: 'Could not open this book',
              detail: _error,
              retryLabel: 'Retry',
              onRetry: _load,
              secondaryLabel: 'Back',
              secondaryIcon: Symbols.arrow_back_rounded,
              onSecondary: () => Navigator.of(context).maybePop(),
            )
          : _tracks.isEmpty
          ? const ShioriEmptyState(
              icon: Symbols.headphones_rounded,
              title: 'Nothing to play',
              message: 'This book has no audio files the server can stream.',
            )
          : ListView(
              padding: pageInsets(context),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    ShioriSpace.s24,
                    ShioriSpace.s16,
                    ShioriSpace.s24,
                    ShioriSpace.s16,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: ShioriSpace.s16,
                    children: [
                      SizedBox(
                        width: 96,
                        child: AbsCover(
                          uri: _client?.coverUri(widget.item.id),
                          title: widget.item.title,
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          spacing: ShioriSpace.s4,
                          children: [
                            Text(
                              widget.item.title,
                              style: tokens.text.seriesTitle.copyWith(
                                color: tokens.color.fg,
                              ),
                            ),
                            if (widget.item.author.isNotEmpty)
                              Text(
                                widget.item.author,
                                style: tokens.text.row.copyWith(
                                  color: tokens.color.fgMuted,
                                ),
                              ),
                            Text(
                              '${_index + 1} of ${_tracks.length} · '
                              '${track?.title ?? ''}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: tokens.text.meta.copyWith(
                                color: tokens.color.fgMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (_error != null)
                  AbsNotice(
                    icon: Symbols.error_rounded,
                    color: tokens.color.error.foreground,
                    message: _error!,
                  ),
                Slider(
                  value: value.clamp(0, max).toDouble(),
                  max: max <= 0 ? 1 : max,
                  onChanged: max <= 0
                      ? null
                      : (next) => setState(() => _dragValue = next),
                  onChangeEnd: max <= 0
                      ? null
                      : (next) async {
                          setState(() => _dragValue = null);
                          await _player.seek(
                            Duration(milliseconds: next.round()),
                          );
                        },
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: ShioriSpace.s24,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        formatBookPosition(
                          Duration(milliseconds: value.round()),
                        ),
                        style: tokens.text.meta.copyWith(
                          color: tokens.color.fgMuted,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      Text(
                        formatBookPosition(duration),
                        style: tokens.text.meta.copyWith(
                          color: tokens.color.fgMuted,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: ShioriSpace.s16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  spacing: ShioriSpace.s24,
                  children: [
                    IconButton(
                      tooltip: 'Previous file',
                      iconSize: 40,
                      icon: const Icon(Symbols.skip_previous_rounded),
                      onPressed: _index == 0
                          ? null
                          : () => _openTrack(_index - 1),
                    ),
                    IconButton.filled(
                      tooltip: _playing ? 'Pause' : 'Play',
                      iconSize: 48,
                      padding: const EdgeInsets.all(ShioriSpace.s16),
                      icon: Icon(
                        _playing
                            ? Symbols.pause_rounded
                            : Symbols.play_arrow_rounded,
                      ),
                      onPressed: _togglePlay,
                    ),
                    IconButton(
                      tooltip: 'Next file',
                      iconSize: 40,
                      icon: const Icon(Symbols.skip_next_rounded),
                      onPressed: _index + 1 >= _tracks.length
                          ? null
                          : () => _openTrack(_index + 1),
                    ),
                  ],
                ),
                const SizedBox(height: ShioriSpace.s24),
                Center(
                  child: Text(
                    _finished
                        ? 'Finished · ${formatBookDuration(_bookDuration.inSeconds.toDouble())}'
                        : 'Book position ${formatBookPosition(_bookPosition)} '
                              'of ${formatBookDuration(_bookDuration.inSeconds.toDouble())}',
                    textAlign: TextAlign.center,
                    style: tokens.text.meta.copyWith(
                      color: tokens.color.fgMuted,
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _PlaybackTrack {
  const _PlaybackTrack({
    required this.title,
    required this.uri,
    required this.duration,
  });

  final String title;
  final Uri uri;
  final Duration duration;
}
