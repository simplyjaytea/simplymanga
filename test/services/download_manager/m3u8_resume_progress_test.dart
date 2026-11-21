// D3: foreground HLS resume reports the segments already on disk as progress,
// using the same filter the downloader applies (existing, non-empty TS_<n>.ts,
// 1-indexed as the parser names them). After prepareHlsResume discards stale
// segments from a changed manifest, the resumed count is zero — never the old
// offset.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mangayomi/services/download_manager/m3u8/models/ts_info.dart';
import 'package:mangayomi/services/download_manager/m3u8/resume_manifest.dart';
import 'package:mangayomi/services/download_manager/m3u8/resume_progress.dart';

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('simplymanga_resume_progress_');
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  void writeSegment(int n, List<int> bytes) {
    File('${dir.path}/TS_$n.ts').writeAsBytesSync(bytes);
  }

  String fingerprint(List<String> urls) => hlsResumeFingerprint(
    segments: [for (final url in urls) TsInfo('TS_1', url)],
  );

  test('no segments on disk means zero resumed', () {
    expect(countResumedSegments(dir.path, 3), 0);
    expect(countResumedSegments('${dir.path}/gone', 3), 0);
  });

  test('counts existing non-empty segments within the playlist range', () {
    writeSegment(1, [1, 2, 3]);
    writeSegment(2, [4, 5, 6]);
    // TS_3 not downloaded yet; an out-of-range stray file is ignored.
    writeSegment(9, [9]);
    expect(countResumedSegments(dir.path, 3), 2);
  });

  test('zero-byte segments do not count as resumed', () {
    writeSegment(1, []);
    writeSegment(2, [1]);
    writeSegment(3, []);
    expect(countResumedSegments(dir.path, 3), 1);
  });

  test('a changed manifest discards stale segments, so resume starts at zero',
      () async {
    // Establish provenance for the original playlist on the empty directory,
    // then cache the segments fetched from it.
    final oldFingerprint = fingerprint(['https://x/old1.ts', 'https://x/old2.ts']);
    await prepareHlsResume(dir.path, oldFingerprint);
    writeSegment(1, [1, 2, 3]);
    writeSegment(2, [4, 5, 6]);

    // Same playlist: provenance matches, nothing is discarded, so resume keeps
    // the two cached segments.
    expect(await prepareHlsResume(dir.path, oldFingerprint), isFalse);
    expect(countResumedSegments(dir.path, 2), 2);

    // The source rotated the playlist under the same URL: provenance no longer
    // matches, so the cached segments are discarded before re-download.
    final newFingerprint = fingerprint(['https://x/new1.ts', 'https://x/new2.ts']);
    final discarded = await prepareHlsResume(dir.path, newFingerprint);
    expect(discarded, isTrue);
    expect(countResumedSegments(dir.path, 2), 0);
  });
}
