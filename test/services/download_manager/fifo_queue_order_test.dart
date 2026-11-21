// D3: downloads start in the order they were enqueued (FIFO), the concurrency
// cap holds, and a manual queue order still wins over arrival order.
//
// The gate grants a free slot to the first acquire() synchronously, so FIFO is
// what orders the *waiters*: each gate test below holds the slot(s) with a
// blocker first, queues the real downloads behind it, then releases and asserts
// the order they are handed out in.
//
// Isar-backed like the other download_manager tests: a temp database per test,
// the arrival registry reset in setUp, no network and no real downloads.
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:isar_community/isar.dart';
import 'package:mangayomi/main.dart' as app;
import 'package:mangayomi/models/chapter.dart';
import 'package:mangayomi/models/download.dart';
import 'package:mangayomi/models/manga.dart';
import 'package:mangayomi/models/settings.dart';
import 'package:mangayomi/models/source.dart';
import 'package:mangayomi/repositories/db_write_queue.dart';
import 'package:mangayomi/repositories/download_repository.dart';
import 'package:mangayomi/services/download_manager/download_gate.dart';
import 'package:mangayomi/services/download_manager/download_queue_order.dart';

/// A pending, not-yet-finished download row for [id].
Download pending(int id) => Download(
  id: id,
  succeeded: 0,
  failed: 0,
  total: 100,
  isDownload: false,
  isStartDownload: true,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory databaseDirectory;
  late Isar database;

  setUpAll(() async {
    await Isar.initializeIsarCore(download: true);
  });

  setUp(() async {
    DownloadQueueOrder.resetArrivals();
    downloadsPaused.value = false;
    databaseDirectory = await Directory.systemTemp.createTemp(
      'mangayomi_fifo_queue_test_${math.Random().nextInt(1 << 32)}',
    );
    database = await Isar.open(
      [ChapterSchema, DownloadSchema, MangaSchema, SettingsSchema, SourceSchema],
      directory: databaseDirectory.path,
      inspector: false,
    );
    app.isar = database;
    await database.writeTxn(() async {
      await database.settings.put(Settings(id: 227));
    });
  });

  tearDown(() async {
    DownloadQueueOrder.resetArrivals();
    await database.close();
    await databaseDirectory.delete(recursive: true);
  });

  Future<void> putPending(List<int> ids) async {
    await database.writeTxn(
      () => database.downloads.putAll([for (final id in ids) pending(id)]),
    );
  }

  group('FIFO arrival order', () {
    test('unranked downloads sort by enqueue order, not id order', () async {
      await putPending([101, 102, 103]);
      DownloadQueueOrder.recordArrival(103);
      DownloadQueueOrder.recordArrival(101);
      DownloadQueueOrder.recordArrival(102);

      final rows = await downloadRepository.getPendingStarted();
      final sorted = DownloadQueueOrder.sorted(rows);
      expect(sorted.map((d) => d.id).toList(), [103, 101, 102]);
    });

    test('the gate hands out slots in FIFO order', () async {
      await putPending([300, 100, 200]);
      DownloadQueueOrder.recordArrival(300);
      DownloadQueueOrder.recordArrival(100);
      DownloadQueueOrder.recordArrival(200);

      final gate = DownloadGate.instance;
      final started = <int>[];
      // Hold the only slot so all three queue as waiters.
      await gate.acquire(
        id: 999,
        sourceKey: 'blocker',
        maxConcurrent: 1,
        delaySeconds: 0,
      );
      Future<void> run(int id) async {
        await gate.acquire(
          id: id,
          sourceKey: 'source-$id',
          maxConcurrent: 1,
          delaySeconds: 0,
        );
        started.add(id);
      }

      // Fire low-id-first to prove the gate reorders by arrival, not by the
      // order acquire() happened to be called in.
      final futures = [run(200), run(100), run(300)];
      await pumpEventQueue();
      expect(started, isEmpty);

      gate.release('blocker');
      await pumpEventQueue();
      expect(started, [300]);

      gate.release('source-300');
      await pumpEventQueue();
      expect(started, [300, 100]);

      gate.release('source-100');
      await pumpEventQueue();
      expect(started, [300, 100, 200]);

      gate.release('source-200');
      await Future.wait(futures);
    });

    test('manual queue order wins over FIFO arrival', () async {
      await putPending([100, 200]);
      await DownloadQueueOrder.setOrder([200]);
      await dbWriteQueue.run(() {});
      DownloadQueueOrder.recordArrival(100);
      DownloadQueueOrder.recordArrival(200);

      final gate = DownloadGate.instance;
      final started = <int>[];
      await gate.acquire(
        id: 999,
        sourceKey: 'blocker',
        maxConcurrent: 1,
        delaySeconds: 0,
      );
      Future<void> run(int id, String source) async {
        await gate.acquire(
          id: id,
          sourceKey: source,
          maxConcurrent: 1,
          delaySeconds: 0,
        );
        started.add(id);
      }

      final futures = [run(100, 'source-a'), run(200, 'source-b')];
      await pumpEventQueue();
      expect(started, isEmpty);

      gate.release('blocker');
      await pumpEventQueue();
      expect(started, [200]);

      gate.release('source-b');
      await pumpEventQueue();
      expect(started, [200, 100]);

      gate.release('source-a');
      await Future.wait(futures);
    });
  });

  group('concurrency cap with FIFO', () {
    test('no more than maxConcurrent run at once, in arrival order', () async {
      await putPending([400, 100, 300, 200]);
      for (final id in [400, 100, 300, 200]) {
        DownloadQueueOrder.recordArrival(id);
      }

      final gate = DownloadGate.instance;
      final started = <int>[];
      // Fill both slots so all four queue as waiters.
      await gate.acquire(
        id: 998,
        sourceKey: 'b1',
        maxConcurrent: 2,
        delaySeconds: 0,
      );
      await gate.acquire(
        id: 999,
        sourceKey: 'b2',
        maxConcurrent: 2,
        delaySeconds: 0,
      );
      Future<void> run(int id) async {
        await gate.acquire(
          id: id,
          sourceKey: 'source-$id',
          maxConcurrent: 2,
          delaySeconds: 0,
        );
        started.add(id);
      }

      final futures = [run(200), run(300), run(100), run(400)];
      await pumpEventQueue();
      expect(started, isEmpty);

      gate.release('b1');
      gate.release('b2');
      await pumpEventQueue();
      // Cap 2: the two earliest arrivals start, nobody else.
      expect(started, [400, 100]);

      gate.release('source-400');
      await pumpEventQueue();
      expect(started, [400, 100, 300]);

      gate.release('source-100');
      await pumpEventQueue();
      expect(started, [400, 100, 300, 200]);

      gate.release('source-300');
      gate.release('source-200');
      await Future.wait(futures);
    });

    test('one chapter per source at a time, even with free slots', () async {
      await database.writeTxn(() async {
        for (final id in [100, 200, 300]) {
          final manga = Manga(
            id: id,
            source: 'Test Source',
            author: '',
            artist: '',
            genre: const [],
            imageUrl: '',
            lang: 'en',
            link: '',
            name: 'Series $id',
            status: Status.values.first,
            description: '',
            sourceId: 1,
            itemType: ItemType.manga,
          );
          await database.mangas.put(manga);
          final chapter = Chapter(id: id, mangaId: id, name: 'Ch $id');
          chapter.manga.value = manga;
          await database.chapters.put(chapter);
          final record = pending(id);
          record.chapter.value = chapter;
          await database.downloads.put(record);
        }
      });
      for (final id in [100, 200, 300]) {
        DownloadQueueOrder.recordArrival(id);
      }

      final gate = DownloadGate.instance;
      final started = <int>[];
      final head = (await database.chapters.get(100))!;
      head.manga.value = await database.mangas.get(100);
      final sourceKey = chapterSourceKey(head);
      // Hold the shared source so all three queue behind it.
      await gate.acquire(
        id: 999,
        sourceKey: sourceKey,
        maxConcurrent: 3,
        delaySeconds: 0,
      );
      Future<void> run(int id) async {
        final chapter = (await database.chapters.get(id))!;
        chapter.manga.value = await database.mangas.get(id);
        await gate.acquire(
          id: id,
          sourceKey: chapterSourceKey(chapter),
          maxConcurrent: 3,
          delaySeconds: 0,
        );
        started.add(id);
      }

      final futures = [run(300), run(200), run(100)];
      await pumpEventQueue();
      expect(started, isEmpty);

      gate.release(sourceKey);
      await pumpEventQueue();
      // Cap is 3, but one source serialises: only the FIFO head runs.
      expect(started, [100]);

      gate.release(sourceKey);
      await pumpEventQueue();
      expect(started, [100, 200]);

      gate.release(sourceKey);
      await pumpEventQueue();
      expect(started, [100, 200, 300]);

      gate.release(sourceKey);
      await Future.wait(futures);
    });
  });

  group('arrival lifecycle', () {
    test('a failed download forgets its arrival so a retry queues last',
        () async {
      await putPending([100, 200, 300]);
      DownloadQueueOrder.recordArrival(100);
      DownloadQueueOrder.recordArrival(200);
      DownloadQueueOrder.recordArrival(300);

      final chapter = Chapter(id: 100, mangaId: 100, name: 'Ch 100');
      markDownloadFailed(chapter);

      // Retry: a fresh enqueue lands at the back of the line.
      DownloadQueueOrder.recordArrival(100);
      final rows = await downloadRepository.getPendingStarted();
      final sorted = DownloadQueueOrder.sorted(rows);
      expect(sorted.map((d) => d.id).toList(), [200, 300, 100]);
    });

    test('forgetArrival drops a cancelled id back to the legacy tail', () {
      DownloadQueueOrder.recordArrival(100);
      DownloadQueueOrder.recordArrival(200);
      DownloadQueueOrder.forgetArrival(100);
      expect(
        DownloadQueueOrder.positions()(200) <
            DownloadQueueOrder.positions()(100),
        isTrue,
      );
    });

    test('with no arrivals recorded, order falls back to id order', () {
      final positions = DownloadQueueOrder.positions();
      expect(positions(101), 101);
      expect(positions(5), 5);
      expect(positions(42), 42);
    });
  });
}
