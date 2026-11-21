import 'package:flutter_test/flutter_test.dart';
import 'package:mangayomi/services/download_manager/background/background_download_contract.dart';

/// The Dart side of the proposed background-URLSession handoff (PLAN M2).
/// Dart registers the direct-file downloads it hands to the native background
/// session; when the app next foregrounds (or the session reports completion),
/// the reconciler places finished files and settles each task exactly once.
void main() {
  BackgroundDownloadRequest req(String id) => BackgroundDownloadRequest(
    taskId: id,
    url: 'https://cdn.example.test/$id.bin',
    destinationPath: '/downloads/$id.bin',
  );

  late BackgroundDownloadReconciler reconciler;
  late List<(String, String)> moves;
  late List<String> completed;
  late List<(String, String)> errors;
  late Set<String> failMovesTo;

  setUp(() {
    reconciler = BackgroundDownloadReconciler();
    moves = [];
    completed = [];
    errors = [];
    failMovesTo = {};
  });

  Future<void> moveFile(String from, String to) async {
    if (failMovesTo.contains(to)) throw StateError('disk full');
    moves.add((from, to));
  }

  Future<BackgroundReconcileSummary> run(
    List<BackgroundDownloadResult> results,
  ) => reconciler.reconcile(
    results,
    moveFile: moveFile,
    onComplete: completed.add,
    onError: (id, err) => errors.add((id, err)),
  );

  test('completed result places the file and settles the task once', () async {
    reconciler.register(req('a'));
    final summary = await run([
      const BackgroundDownloadResult(
        taskId: 'a',
        status: BackgroundDownloadStatus.completed,
        localPath: '/tmp/staged-a',
      ),
    ]);
    expect(moves, [('/tmp/staged-a', '/downloads/a.bin')]);
    expect(completed, ['a']);
    expect(errors, isEmpty);
    expect(summary.completed, 1);
    expect(reconciler.pendingCount, 0);
  });

  test('failed result reports the error and clears the task', () async {
    reconciler.register(req('b'));
    final summary = await run([
      const BackgroundDownloadResult(
        taskId: 'b',
        status: BackgroundDownloadStatus.failed,
        error: 'HTTP 503',
      ),
    ]);
    expect(moves, isEmpty);
    expect(completed, isEmpty);
    expect(errors, [('b', 'HTTP 503')]);
    expect(summary.failed, 1);
    expect(reconciler.pendingCount, 0);
  });

  test('cancelled result clears the task without completing', () async {
    reconciler.register(req('c'));
    final summary = await run([
      const BackgroundDownloadResult(
        taskId: 'c',
        status: BackgroundDownloadStatus.cancelled,
      ),
    ]);
    expect(completed, isEmpty);
    expect(errors, isEmpty);
    expect(summary.cancelled, 1);
    expect(reconciler.pendingCount, 0);
  });

  test('orphan result for an unknown task is ignored and counted', () async {
    final summary = await run([
      const BackgroundDownloadResult(
        taskId: 'ghost',
        status: BackgroundDownloadStatus.completed,
        localPath: '/tmp/ghost',
      ),
    ]);
    expect(moves, isEmpty);
    expect(summary.orphaned, 1);
    expect(summary.completed, 0);
  });

  test('a task reported twice is settled only once', () async {
    reconciler.register(req('d'));
    const result = BackgroundDownloadResult(
      taskId: 'd',
      status: BackgroundDownloadStatus.completed,
      localPath: '/tmp/staged-d',
    );
    final first = await run([result]);
    final second = await run([result]);
    expect(first.completed, 1);
    expect(second.orphaned, 1);
    expect(moves.length, 1);
    expect(completed, ['d']);
  });

  test('a failed file move is reported as a failure, not a completion', () async {
    reconciler.register(req('e'));
    failMovesTo.add('/downloads/e.bin');
    final summary = await run([
      const BackgroundDownloadResult(
        taskId: 'e',
        status: BackgroundDownloadStatus.completed,
        localPath: '/tmp/staged-e',
      ),
    ]);
    expect(completed, isEmpty);
    expect(summary.failed, 1);
    expect(summary.completed, 0);
    expect(errors.single.$1, 'e');
    expect(reconciler.pendingCount, 0);
  });

  test('completed without a local path is a failure', () async {
    reconciler.register(req('f'));
    final summary = await run([
      const BackgroundDownloadResult(
        taskId: 'f',
        status: BackgroundDownloadStatus.completed,
      ),
    ]);
    expect(summary.failed, 1);
    expect(completed, isEmpty);
    expect(errors.single.$1, 'f');
  });

  test('registerAll tracks pending tasks and empty reconcile is a no-op', () async {
    reconciler.registerAll([req('g'), req('h')]);
    expect(reconciler.pendingCount, 2);
    expect(reconciler.pendingTaskIds.toSet(), {'g', 'h'});
    final summary = await run([]);
    expect(summary.completed + summary.failed + summary.cancelled + summary.orphaned, 0);
    expect(reconciler.pendingCount, 2);
    reconciler.forget('g');
    expect(reconciler.pendingCount, 1);
  });
}
