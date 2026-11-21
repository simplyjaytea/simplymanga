import 'package:mangayomi/models/download.dart';

/// The download queue's aggregate state, for the progress header above the
/// queue list: how many downloads are active, how many wait, and how far the
/// whole queue has come.
///
/// Overall progress is weighted by each entry's own total, so a 300-page
/// chapter counts for more than a 10-page one — the bar answers "how much of
/// everything I asked for is on disk", not "how many rows are green".
class DownloadQueueProgress {
  const DownloadQueueProgress({
    required this.activeCount,
    required this.waitingCount,
    required this.overallFraction,
    required this.paused,
  });

  /// Aggregates the pending [entries]. An entry is active when its id is in
  /// [scheduledIds] — scheduled this session, running or waiting in the gate.
  /// Ids in [scheduledIds] that are no longer pending (completed between
  /// snapshots) do not count.
  factory DownloadQueueProgress.from(
    List<Download> entries, {
    required Set<int> scheduledIds,
    required bool paused,
  }) {
    var active = 0;
    var succeeded = 0;
    var total = 0;
    for (final entry in entries) {
      final id = entry.id;
      if (id != null && scheduledIds.contains(id)) active++;
      final entryTotal = entry.total ?? 0;
      if (entryTotal > 0) {
        total += entryTotal;
        succeeded += (entry.succeeded ?? 0).clamp(0, entryTotal);
      }
    }
    return DownloadQueueProgress(
      activeCount: active,
      waitingCount: entries.length - active,
      overallFraction: total == 0 ? 0 : succeeded / total,
      paused: paused,
    );
  }

  /// Downloads scheduled this session: running, or waiting for a gate slot.
  final int activeCount;

  /// Pending downloads not scheduled this session — including failed entries
  /// waiting for a retry.
  final int waitingCount;

  /// Share of the whole queue's work already on disk, from 0 to 1.
  final double overallFraction;

  /// Whether the queue is paused: nothing starts until it is resumed.
  final bool paused;

  bool get isEmpty => activeCount + waitingCount == 0;

  /// [overallFraction] as a whole percent, for the header's readout.
  int get percent => (overallFraction * 100).round();
}
