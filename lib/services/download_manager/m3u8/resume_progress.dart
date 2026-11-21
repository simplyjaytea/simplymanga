import 'dart:io';

/// Segments already on disk for an HLS download being resumed in the
/// foreground, counted the same way the downloader filters them: a
/// `TS_<n>.ts` (1-indexed, as the parser names them) inside the playlist
/// range that exists and is not empty.
///
/// Call after [prepareHlsResume] (resume_manifest.dart) so segments from a
/// changed manifest have already been discarded — a stale resume then reports
/// zero, never the old offset. This is the starting progress the queue shows
/// while the remaining segments download.
int countResumedSegments(String tempDir, int totalSegments) {
  var completed = 0;
  for (var n = 1; n <= totalSegments; n++) {
    final segment = File('$tempDir${Platform.pathSeparator}TS_$n.ts');
    if (segment.existsSync() && segment.lengthSync() > 0) completed++;
  }
  return completed;
}
