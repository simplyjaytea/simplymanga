import 'package:flutter_test/flutter_test.dart';
import 'package:mangayomi/models/download.dart';
import 'package:mangayomi/services/download_manager/download_queue_progress.dart';

/// D3: the aggregate the queue's progress header shows — how many downloads
/// are active, how many wait, and how far the whole queue has come, weighted
/// by each entry's own total so a 300-page chapter counts for more than a
/// 10-page one.
void main() {
  Download entry(int id, {int succeeded = 0, int total = 100}) => Download(
    id: id,
    succeeded: succeeded,
    failed: 0,
    total: total,
    isDownload: false,
    isStartDownload: true,
  );

  test('an empty queue reports nothing and zero progress', () {
    final progress = DownloadQueueProgress.from(
      const [],
      scheduledIds: const {},
      paused: false,
    );

    expect(progress.isEmpty, isTrue);
    expect(progress.activeCount, 0);
    expect(progress.waitingCount, 0);
    expect(progress.overallFraction, 0);
    expect(progress.percent, 0);
  });

  test('scheduled entries are active, the rest wait', () {
    final progress = DownloadQueueProgress.from(
      [entry(1), entry(2), entry(3)],
      scheduledIds: const {1, 3},
      paused: false,
    );

    expect(progress.activeCount, 2);
    expect(progress.waitingCount, 1);
    expect(progress.isEmpty, isFalse);
  });

  test('a scheduled id no longer pending does not count as active', () {
    // The entry completed between snapshots: its id is still in the session
    // set, but it is not in the pending list any more.
    final progress = DownloadQueueProgress.from(
      [entry(2)],
      scheduledIds: const {1, 2},
      paused: false,
    );

    expect(progress.activeCount, 1);
    expect(progress.waitingCount, 0);
  });

  test('overall progress is weighted by each entry total', () {
    final progress = DownloadQueueProgress.from(
      [entry(1, succeeded: 25), entry(2, succeeded: 75, total: 300)],
      scheduledIds: const {1},
      paused: false,
    );

    // (25 + 75) / (100 + 300) = 0.25
    expect(progress.overallFraction, 0.25);
    expect(progress.percent, 25);
  });

  test('entries with a zero total contribute nothing and never divide by zero',
      () {
    final progress = DownloadQueueProgress.from(
      [entry(1, succeeded: 0, total: 0), entry(2, succeeded: 50)],
      scheduledIds: const {},
      paused: false,
    );

    expect(progress.overallFraction, 0.5);
    expect(progress.percent, 50);
  });

  test('an queue of only zero-total entries reports zero, not NaN', () {
    final progress = DownloadQueueProgress.from(
      [entry(1, total: 0)],
      scheduledIds: const {},
      paused: false,
    );

    expect(progress.overallFraction, 0);
    expect(progress.percent, 0);
  });

  test('succeeded counts above the total are clamped', () {
    final progress = DownloadQueueProgress.from(
      [entry(1, succeeded: 150)],
      scheduledIds: const {},
      paused: false,
    );

    expect(progress.overallFraction, 1);
    expect(progress.percent, 100);
  });

  test('the paused flag passes through', () {
    final paused = DownloadQueueProgress.from(
      [entry(1)],
      scheduledIds: const {1},
      paused: true,
    );
    final running = DownloadQueueProgress.from(
      [entry(1)],
      scheduledIds: const {1},
      paused: false,
    );

    expect(paused.paused, isTrue);
    expect(running.paused, isFalse);
  });

  test('percent rounds to the nearest whole number', () {
    final progress = DownloadQueueProgress.from(
      [entry(1, succeeded: 1, total: 3)],
      scheduledIds: const {},
      paused: false,
    );

    expect(progress.percent, 33);
  });
}
