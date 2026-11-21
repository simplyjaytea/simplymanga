import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mangayomi/services/download_manager/m3u8/models/ts_info.dart';
import 'package:mangayomi/services/download_manager/m3u8/resume_manifest.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('hls_manifest');
  });
  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  List<TsInfo> segs(List<String> urls) => [
    for (var i = 0; i < urls.length; i++) TsInfo('seg$i', urls[i]),
  ];
  String manifestPath() => p.join(tempDir.path, hlsResumeManifestFileName);

  group('hlsResumeFingerprint', () {
    final base = segs(['a.ts', 'b.ts']);

    test('stable for identical inputs', () {
      expect(
        hlsResumeFingerprint(segments: base),
        hlsResumeFingerprint(segments: segs(['a.ts', 'b.ts'])),
      );
    });
    test('changes when a segment url changes', () {
      expect(
        hlsResumeFingerprint(segments: base),
        isNot(hlsResumeFingerprint(segments: segs(['a.ts', 'c.ts']))),
      );
    });
    test('changes when segment order changes', () {
      expect(
        hlsResumeFingerprint(segments: base),
        isNot(hlsResumeFingerprint(segments: segs(['b.ts', 'a.ts']))),
      );
    });
    test('changes when segment count changes', () {
      expect(
        hlsResumeFingerprint(segments: base),
        isNot(hlsResumeFingerprint(segments: segs(['a.ts']))),
      );
    });
    test('changes when the key changes', () {
      expect(
        hlsResumeFingerprint(segments: base),
        isNot(
          hlsResumeFingerprint(
            segments: base,
            key: Uint8List.fromList([1, 2, 3]),
          ),
        ),
      );
    });
    test('changes when the iv changes', () {
      expect(
        hlsResumeFingerprint(segments: base),
        isNot(
          hlsResumeFingerprint(segments: base, iv: Uint8List.fromList([9])),
        ),
      );
    });
    test('changes when the media sequence changes', () {
      expect(
        hlsResumeFingerprint(segments: base),
        isNot(hlsResumeFingerprint(segments: base, mediaSequence: 5)),
      );
    });
  });

  group('manifest match/write', () {
    test('no manifest is not a match', () async {
      expect(await hlsResumeMatches(tempDir.path, 'fp'), isFalse);
    });
    test('written manifest matches its fingerprint', () async {
      await writeHlsResumeManifest(tempDir.path, 'fp');
      expect(await hlsResumeMatches(tempDir.path, 'fp'), isTrue);
    });
    test('different fingerprint does not match', () async {
      await writeHlsResumeManifest(tempDir.path, 'fp');
      expect(await hlsResumeMatches(tempDir.path, 'other'), isFalse);
    });
    test('corrupt manifest is not a match', () async {
      await File(manifestPath()).writeAsString('not json');
      expect(await hlsResumeMatches(tempDir.path, 'fp'), isFalse);
    });
    test('wrong version is not a match', () async {
      await File(
        manifestPath(),
      ).writeAsString(jsonEncode({'version': 2, 'fingerprint': 'fp'}));
      expect(await hlsResumeMatches(tempDir.path, 'fp'), isFalse);
    });
  });

  group('discardStaleHlsSegments', () {
    test('removes TS files and parts, keeps manifest and unrelated files', () async {
      await File(p.join(tempDir.path, 'TS_1.ts')).writeAsBytes([1]);
      await File(p.join(tempDir.path, 'TS_2.ts.part')).writeAsBytes([2]);
      await File(manifestPath()).writeAsString('{}');
      await File(p.join(tempDir.path, 'notes.txt')).writeAsString('keep');
      final sub = Directory(p.join(tempDir.path, 'sub'));
      await sub.create();
      await File(p.join(sub.path, 'TS_9.ts')).writeAsBytes([9]);

      expect(await discardStaleHlsSegments(tempDir.path), 2);
      expect(await File(p.join(tempDir.path, 'TS_1.ts')).exists(), isFalse);
      expect(await File(p.join(tempDir.path, 'TS_2.ts.part')).exists(), isFalse);
      expect(await File(manifestPath()).exists(), isTrue);
      expect(await File(p.join(tempDir.path, 'notes.txt')).exists(), isTrue);
      expect(await File(p.join(sub.path, 'TS_9.ts')).exists(), isTrue);
    });
    test('missing dir returns 0', () async {
      expect(
        await discardStaleHlsSegments(p.join(tempDir.path, 'nope')),
        0,
      );
    });
  });

  group('prepareHlsResume', () {
    test('fresh dir records manifest without discarding', () async {
      expect(await prepareHlsResume(tempDir.path, 'fp'), isFalse);
      expect(await hlsResumeMatches(tempDir.path, 'fp'), isTrue);
    });
    test('matching provenance keeps segments', () async {
      await writeHlsResumeManifest(tempDir.path, 'fp');
      final seg = File(p.join(tempDir.path, 'TS_1.ts'));
      await seg.writeAsBytes([1]);
      expect(await prepareHlsResume(tempDir.path, 'fp'), isFalse);
      expect(await seg.exists(), isTrue);
    });
    test('changed provenance discards segments and rewrites manifest', () async {
      await writeHlsResumeManifest(tempDir.path, 'fp');
      final seg = File(p.join(tempDir.path, 'TS_1.ts'));
      await seg.writeAsBytes([1]);
      expect(await prepareHlsResume(tempDir.path, 'other'), isTrue);
      expect(await seg.exists(), isFalse);
      expect(await hlsResumeMatches(tempDir.path, 'other'), isTrue);
    });
    test('legacy segments without manifest are discarded', () async {
      final seg = File(p.join(tempDir.path, 'TS_1.ts'));
      await seg.writeAsBytes([1]);
      expect(await prepareHlsResume(tempDir.path, 'fp'), isTrue);
      expect(await seg.exists(), isFalse);
      expect(await hlsResumeMatches(tempDir.path, 'fp'), isTrue);
    });
  });
}
