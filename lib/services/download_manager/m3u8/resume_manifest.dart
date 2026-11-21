/// Resume provenance for an HLS download's temporary segment directory.
///
/// Segments are stored under index names (`TS_1.ts`, `TS_2.ts`, …) in a temp
/// directory keyed only by `chapterId:m3u8Url`. That key does not change when
/// the source rotates the playlist under the same URL — a new variant, fresh
/// segment tokens, or a shifted live window. Without a record of which playlist
/// the cached segments came from, a later attempt would keep the old `TS_1.ts`
/// and splice it together with newly fetched segments, producing a corrupt
/// merge. The manifest fingerprint pins the cached segments to the exact
/// resolved playlist they were fetched from so a changed playlist discards them
/// instead.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:mangayomi/services/download_manager/m3u8/models/ts_info.dart';
import 'package:path/path.dart' as path;

/// File name of the resume manifest inside the HLS temp directory.
const String hlsResumeManifestFileName = 'resume.json';

/// Stable identity of a resolved media playlist for resume purposes.
///
/// Covers the ordered segment URLs (which encode the chosen variant and any
/// per-segment tokens), the AES-128 key bytes and IV, and the media sequence
/// (which drives the derived IV when the playlist omits an explicit one). Two
/// attempts fingerprint equally only when their cached segments are
/// interchangeable; any difference forces a clean re-download.
String hlsResumeFingerprint({
  required List<TsInfo> segments,
  Uint8List? key,
  Uint8List? iv,
  int? mediaSequence,
}) {
  final buffer = StringBuffer()
    ..writeln('hls-resume-v1')
    ..writeln(segments.length);
  for (final segment in segments) {
    buffer.writeln(segment.url);
  }
  buffer.writeln(key == null ? '' : base64Encode(key));
  buffer.writeln(iv == null ? '' : base64Encode(iv));
  buffer.writeln(mediaSequence?.toString() ?? '');
  return sha256.convert(utf8.encode(buffer.toString())).toString();
}

/// Whether the temp directory's manifest matches [fingerprint]. A missing,
/// unreadable, malformed, or different-version manifest is never a match, so
/// legacy directories from before the manifest existed are treated as unknown
/// provenance and re-downloaded rather than trusted.
Future<bool> hlsResumeMatches(String tempDir, String fingerprint) async {
  try {
    final file = File(path.join(tempDir, hlsResumeManifestFileName));
    if (!await file.exists()) return false;
    final decoded = jsonDecode(await file.readAsString());
    return decoded is Map<String, dynamic> &&
        decoded['version'] == 1 &&
        decoded['fingerprint'] == fingerprint;
  } catch (_) {
    return false;
  }
}

/// Writes (or overwrites) the manifest for [fingerprint].
Future<void> writeHlsResumeManifest(String tempDir, String fingerprint) async {
  final file = File(path.join(tempDir, hlsResumeManifestFileName));
  await file.writeAsString(
    jsonEncode({'version': 1, 'fingerprint': fingerprint}),
  );
}

final RegExp _segmentFilePattern = RegExp(r'^TS_\d+\.ts(\.part)?$');

/// Deletes cached segment files (`TS_N.ts` and interrupted `TS_N.ts.part`)
/// from [tempDir], leaving the manifest and any unrelated files alone. Returns
/// the number of files removed.
Future<int> discardStaleHlsSegments(String tempDir) async {
  final dir = Directory(tempDir);
  if (!await dir.exists()) return 0;
  var removed = 0;
  await for (final entity in dir.list()) {
    if (entity is File &&
        _segmentFilePattern.hasMatch(path.basename(entity.path))) {
      try {
        await entity.delete();
        removed++;
      } catch (_) {
        // A segment we cannot delete is left for the next attempt; the
        // fingerprint mismatch still forces it to be re-fetched and renamed.
      }
    }
  }
  return removed;
}

/// Prepares [tempDir] for a download of the playlist identified by
/// [fingerprint]: discards stale segments when the provenance does not match
/// (changed playlist, or unknown legacy provenance), then records the manifest.
/// Returns true when stale segments were discarded.
Future<bool> prepareHlsResume(String tempDir, String fingerprint) async {
  final matches = await hlsResumeMatches(tempDir, fingerprint);
  var discarded = false;
  if (!matches) {
    discarded = await discardStaleHlsSegments(tempDir) > 0;
  }
  await writeHlsResumeManifest(tempDir, fingerprint);
  return discarded;
}
