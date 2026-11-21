/// Dart side of the proposed background-URLSession download handoff (PLAN M2).
///
/// Direct files (manga pages, single-file MP4 episodes) can be downloaded by a
/// native background `URLSession` that keeps running while the app is
/// suspended. The Dart m3u8/HLS pipeline cannot be backgrounded (it parses
/// playlists and orchestrates segments in Dart), so it stays foreground with
/// per-segment resume. This module models the boundary between the Dart
/// download queue and the native session for the direct-file half:
///
///  * Dart [register]s each request it hands to the session (task id, source
///    URL, final destination).
///  * The native session downloads into its own staging area and, on completion
///    or the next foreground, reports a [BackgroundDownloadResult] per task.
///  * [BackgroundDownloadReconciler.reconcile] places finished files at their
///    destinations and settles each task exactly once, tolerating orphaned and
///    duplicate reports (the session can outlive a Dart-side queue rebuild).
///
/// It is pure Dart and platform-agnostic so the contract is unit-testable on CI
/// without a device; the Swift proposal implements the native side against it.
library;

/// Outcome the native session reports for one background download task.
enum BackgroundDownloadStatus { completed, failed, cancelled }

/// A direct-file download Dart hands to the background session.
class BackgroundDownloadRequest {
  final String taskId;
  final String url;
  final String destinationPath;

  const BackgroundDownloadRequest({
    required this.taskId,
    required this.url,
    required this.destinationPath,
  });
}

/// The native session's report for one task. [localPath] is the staged file the
/// session wrote (present only for [BackgroundDownloadStatus.completed]);
/// [error] carries a human-readable reason for failures.
class BackgroundDownloadResult {
  final String taskId;
  final BackgroundDownloadStatus status;
  final String? localPath;
  final String? error;

  const BackgroundDownloadResult({
    required this.taskId,
    required this.status,
    this.localPath,
    this.error,
  });
}

/// Tally of one [BackgroundDownloadReconciler.reconcile] pass.
class BackgroundReconcileSummary {
  int completed = 0;
  int failed = 0;
  int cancelled = 0;
  int orphaned = 0;
}

/// Moves a staged file to its final destination. Injected so the contract can
/// be tested without touching the filesystem and so the native bridge can use
/// a cross-volume-safe move.
typedef MoveFile = Future<void> Function(String from, String to);

/// Tracks handed-off downloads and settles the native session's reports.
class BackgroundDownloadReconciler {
  final Map<String, BackgroundDownloadRequest> _pending = {};

  int get pendingCount => _pending.length;
  Iterable<String> get pendingTaskIds => _pending.keys;

  void register(BackgroundDownloadRequest request) {
    _pending[request.taskId] = request;
  }

  void registerAll(Iterable<BackgroundDownloadRequest> requests) {
    for (final request in requests) {
      register(request);
    }
  }

  /// Drops a task without settling it (e.g. the user cancelled from Dart and
  /// the native cancellation has already been requested).
  void forget(String taskId) {
    _pending.remove(taskId);
  }

  /// Settles each reported task exactly once. A result whose task is not
  /// pending (already settled, or never registered) is counted as orphaned and
  /// ignored, so duplicate or stale session reports cannot double-place files.
  /// A completed report is only a completion once its staged file has been
  /// moved to the destination; a move failure is reported as a failure.
  Future<BackgroundReconcileSummary> reconcile(
    Iterable<BackgroundDownloadResult> results, {
    required MoveFile moveFile,
    required void Function(String taskId) onComplete,
    required void Function(String taskId, String error) onError,
  }) async {
    final summary = BackgroundReconcileSummary();
    for (final result in results) {
      final request = _pending.remove(result.taskId);
      if (request == null) {
        summary.orphaned++;
        continue;
      }
      switch (result.status) {
        case BackgroundDownloadStatus.completed:
          final localPath = result.localPath;
          if (localPath == null) {
            summary.failed++;
            onError(result.taskId, 'completed without a local path');
            break;
          }
          try {
            await moveFile(localPath, request.destinationPath);
            summary.completed++;
            onComplete(result.taskId);
          } catch (error) {
            summary.failed++;
            onError(result.taskId, error.toString());
          }
          break;
        case BackgroundDownloadStatus.failed:
          summary.failed++;
          onError(result.taskId, result.error ?? 'download failed');
          break;
        case BackgroundDownloadStatus.cancelled:
          summary.cancelled++;
          break;
      }
    }
    return summary;
  }
}
