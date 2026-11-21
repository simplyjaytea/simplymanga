import 'package:mangayomi/models/download.dart';
import 'package:mangayomi/repositories/settings_repository.dart';

/// The user's manual ordering of the download queue as a list of Download ids
/// (which equal their chapter ids), highest priority first.
///
/// Stored on the Settings collection (`downloadQueueOrder`), alongside the rest
/// of the app's preferences. Ids missing from the saved order are treated as
/// lowest priority (in id order, after the known ones), so newly queued
/// downloads slot in at the end until the user moves them.
class DownloadQueueOrder {
  /// Session FIFO arrivals: download id → arrival sequence. Recorded when a
  /// download is enqueued and dropped when it reaches a terminal state
  /// (completed, failed or cancelled), so a later re-request queues at the
  /// back again. Session-scoped like the gate's scheduled set: records left
  /// over from an earlier session have no arrival and sort after this
  /// session's, in id order — exactly the legacy behaviour.
  static final Map<int, int> _arrivals = {};
  static int _arrivalSeq = 0;

  /// Records [id] as arriving now. A repeated request for a download already
  /// queued keeps its place — it does not jump the queue.
  static void recordArrival(int id) {
    _arrivals.putIfAbsent(id, () => _arrivalSeq++);
  }

  /// Drops [id]'s arrival: it reached a terminal state, so a later re-request
  /// is a fresh arrival at the back.
  static void forgetArrival(int id) {
    _arrivals.remove(id);
  }

  /// Test seam: clears the session's arrivals.
  static void resetArrivals() {
    _arrivals.clear();
    _arrivalSeq = 0;
  }

  /// The saved priority order (Download ids), or an empty list if none.
  static List<int> get order =>
      settingsRepository.current.downloadQueueOrder ?? const [];

  /// Persists [ids] as the new priority order.
  static Future<void> setOrder(List<int> ids) =>
      settingsRepository.update((s) => s.downloadQueueOrder = ids);

  /// The position of each download in the queue, smallest first: its place
  /// in the saved manual order, then, for the rest, its FIFO arrival order
  /// this session, then — for ids with no recorded arrival (left over from an
  /// earlier session) — its id. The manual order always wins; unranked
  /// downloads run in the order they were enqueued, not in chapter-id order.
  /// The screen, the queue processor and the gate all sort by this, so what
  /// is at the top of the list is what downloads next.
  static int Function(int id) positions() {
    final ord = order;
    final rank = <int, int>{for (var i = 0; i < ord.length; i++) ord[i]: i};
    final tail = ord.length + _arrivalSeq;
    return (id) {
      final manual = rank[id];
      if (manual != null) return manual;
      final arrival = _arrivals[id];
      if (arrival != null) return ord.length + arrival;
      return tail + id;
    };
  }

  /// [ids] with the ones [moved] picks taken to the top or the bottom,
  /// keeping their order among themselves, and the rest theirs.
  static List<int> move(
    List<int> ids,
    bool Function(int id) moved, {
    required bool toTop,
  }) {
    final group = ids.where(moved).toList();
    final rest = ids.where((id) => !moved(id)).toList();
    return toTop ? [...group, ...rest] : [...rest, ...group];
  }

  /// Returns [items] in queue order (see [positions]).
  static List<Download> sorted(List<Download> items) {
    final position = positions();
    return [...items]
      ..sort((a, b) => position(a.id ?? 0).compareTo(position(b.id ?? 0)));
  }
}
