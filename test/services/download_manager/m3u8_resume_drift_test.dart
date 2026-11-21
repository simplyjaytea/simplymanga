import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' show Client;
import 'package:mangayomi/models/chapter.dart';
import 'package:mangayomi/models/manga.dart';
import 'package:mangayomi/services/download_manager/download_isolate_pool.dart';
import 'package:mangayomi/services/download_manager/m3u8/m3u8_downloader.dart';
import 'package:path/path.dart' as p;

/// End-to-end resume behaviour of [M3u8Downloader.download] across two
/// attempts that share a temp directory (same chapter id + m3u8 URL). The
/// playlist and segments are served by a real loopback HTTP server and the
/// segments are fetched by the pool's Dart-HTTP worker isolate
/// ([DownloadIsolatePool.configureForTesting]), so no Rust library is needed
/// and the real isolate path is exercised.
///
/// Proves that a playlist which changes under the same URL must not splice
/// stale segments into the new merge, while an unchanged playlist still
/// resumes without re-fetching complete segments.
void main() {
  late Directory root;
  late HttpServer server;
  late String m3u8Url;
  late String playlistBody;
  final hits = <String, int>{};
  final failPaths = <String>{};
  final segmentBytes = <String, List<int>>{};

  Manga animeManga() => Manga(
    source: 'Test',
    author: '',
    artist: '',
    genre: const [],
    imageUrl: '',
    lang: 'en',
    link: '',
    name: 'Series',
    status: Status.values.first,
    description: '',
    sourceId: 1,
    itemType: ItemType.anime,
  );

  Chapter chapter(int id) =>
      Chapter(id: id, mangaId: 1, name: 'Episode $id')
        ..manga.value = animeManga();

  String mediaPlaylist(List<String> segments) =>
      '#EXTM3U\n#EXT-X-TARGETDURATION:4\n#EXT-X-MEDIA-SEQUENCE:0\n'
      '${segments.map((u) => '#EXTINF:4.0,\n$u').join('\n')}\n'
      '#EXT-X-ENDLIST\n';

  M3u8Downloader downloader(Chapter c, String fileName) => M3u8Downloader(
    m3u8Url: m3u8Url,
    downloadDir: root.path,
    fileName: fileName,
    chapter: c,
    subtitles: null,
  );

  setUp(() async {
    root = await Directory.systemTemp.createTemp('hls_drift');
    hits.clear();
    failPaths.clear();
    segmentBytes.clear();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    m3u8Url = 'http://127.0.0.1:${server.port}/hls/master.m3u8';
    server.listen((request) async {
      final path = request.uri.path;
      hits[path] = (hits[path] ?? 0) + 1;
      if (path.endsWith('master.m3u8')) {
        request.response.statusCode = 200;
        request.response.write(playlistBody);
      } else if (failPaths.contains(path)) {
        request.response.statusCode = 503;
      } else {
        final bytes = segmentBytes[path] ?? [0];
        request.response.statusCode = 200;
        request.response.contentLength = bytes.length;
        request.response.add(bytes);
      }
      await request.response.close();
    });
    M3u8Downloader.httpClient = Client();
    DownloadIsolatePool.configureForTesting();
  });

  tearDown(() async {
    DownloadIsolatePool.instance.dispose();
    await server.close(force: true);
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('playlist drift discards stale segments instead of splicing', () async {
    final c = chapter(701);
    final fileName = p.join(root.path, 'episode.mp4');
    final tempDir = p.join(
      root.path,
      m3u8TempDirectoryName('${c.id}:$m3u8Url'),
    );

    // Attempt 1: first segment lands, second fails -> temp dir survives with
    // a complete TS_1.ts from playlist A.
    playlistBody = mediaPlaylist(['seg-a1.ts', 'seg-a2.ts']);
    segmentBytes['/hls/seg-a1.ts'] = [1, 1, 1];
    segmentBytes['/hls/seg-a2.ts'] = [9, 9, 9];
    failPaths.add('/hls/seg-a2.ts');
    await expectLater(
      downloader(c, fileName).download((_) {}),
      throwsA(isA<M3u8DownloaderException>()),
    );
    expect(await File(p.join(tempDir, 'TS_1.ts')).readAsBytes(), [1, 1, 1]);

    // The source rotates the playlist under the same URL: new segment URLs,
    // new content. Index-named TS_1.ts from playlist A is now stale.
    playlistBody = mediaPlaylist(['seg-b1.ts', 'seg-b2.ts']);
    segmentBytes['/hls/seg-b1.ts'] = [2, 2, 2];
    segmentBytes['/hls/seg-b2.ts'] = [3, 3, 3];
    failPaths.clear();

    await downloader(c, fileName).download((_) {});

    // The merge must be pure playlist-B content, not A's TS_1 spliced in.
    expect(await File(fileName).readAsBytes(), [2, 2, 2, 3, 3, 3]);
    expect(hits['/hls/seg-b1.ts'], greaterThanOrEqualTo(1));
  });

  test('unchanged playlist resumes without re-fetching complete segments', () async {
    final c = chapter(702);
    final fileName = p.join(root.path, 'episode.mp4');

    playlistBody = mediaPlaylist(['seg-c1.ts', 'seg-c2.ts']);
    segmentBytes['/hls/seg-c1.ts'] = [5, 5];
    segmentBytes['/hls/seg-c2.ts'] = [6, 6];
    failPaths.add('/hls/seg-c2.ts');
    await expectLater(
      downloader(c, fileName).download((_) {}),
      throwsA(isA<M3u8DownloaderException>()),
    );

    // Same playlist, second segment now succeeds: TS_1 must be reused.
    failPaths.clear();
    await downloader(c, fileName).download((_) {});

    expect(await File(fileName).readAsBytes(), [5, 5, 6, 6]);
    expect(hits['/hls/seg-c1.ts'], 1);
    expect(hits['/hls/seg-c2.ts'], greaterThanOrEqualTo(2));
  });
}
