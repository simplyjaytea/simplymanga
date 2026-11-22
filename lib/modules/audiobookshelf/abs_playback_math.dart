// Mapping between the book's clock and its files.
//
// ABS reports a single position for the whole book and a list of files. The
// player, however, has one file open at a time, so it needs both directions:
// where in which file a book position falls, and what the book position is
// while a file plays.

/// Which track [position] falls in, and how far into it. Past the end clamps
/// to the last track; an empty list (a book the server has no durations for)
/// starts at the first.
({int index, Duration offset}) locatePosition(
  List<Duration> tracks,
  Duration position,
) {
  if (tracks.isEmpty) return (index: 0, offset: Duration.zero);
  if (tracks.every((track) => track <= Duration.zero)) {
    return (index: 0, offset: Duration.zero);
  }
  final safe = position < Duration.zero ? Duration.zero : position;
  var elapsed = Duration.zero;
  for (var index = 0; index < tracks.length; index++) {
    final end = elapsed + tracks[index];
    if (safe < end) return (index: index, offset: safe - elapsed);
    elapsed = end;
  }
  return (index: tracks.length - 1, offset: tracks.last);
}

/// The book position for [position] inside track [index].
Duration absolutePosition(List<Duration> tracks, int index, Duration position) {
  if (tracks.isEmpty) {
    return position < Duration.zero ? Duration.zero : position;
  }
  final clamped = index.clamp(0, tracks.length - 1);
  var elapsed = Duration.zero;
  for (var i = 0; i < clamped; i++) {
    elapsed += tracks[i];
  }
  return elapsed + (position < Duration.zero ? Duration.zero : position);
}

/// A book position as `mm:ss`, or `h:mm:ss` past an hour.
String formatBookPosition(Duration position) {
  final safe = position < Duration.zero ? Duration.zero : position;
  final hours = safe.inHours;
  final minutes = safe.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = safe.inSeconds.remainder(60).toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
}
