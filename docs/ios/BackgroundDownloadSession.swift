// PROPOSAL — Lane D (D-bg). Reference implementation of the native half of the
// PLAN M2 background-download split. NOT compiled on the Linux CI/VPS host
// (no macOS/UIKit); the compile gate is the iOS CI build / P1 device session.
// The Dart-side contract it implements against is unit-tested in
// lib/services/download_manager/background/background_download_contract.dart.
//
// Split rationale (see docs/ios/BACKGROUND-DOWNLOADS.md):
//  * Direct files (manga pages, single-file MP4) -> background URLSession,
//    which keeps downloading while the app is suspended. THIS file.
//  * m3u8/HLS -> stays foreground (Dart parses playlists + orchestrates
//    segments); per-segment resume with playlist-provenance guard. Not here.
//  * BGProcessingTask -> best-effort drain/flush only, never the download
//    mechanism itself and never a guarantee of background execution.

import Foundation
import Flutter
import BackgroundTasks

final class BackgroundDownloadSession: NSObject, URLSessionDownloadDelegate {
  static let shared = BackgroundDownloadSession()
  static let processingTaskIdentifier = "com.kodjodevf.mangayomi.background-download"

  private let channelName = "com.kodjodevf.mangayomi.background_download"
  private weak var channel: FlutterMethodChannel?

  // Registry persisted across launches so a session that outlives the Dart
  // queue can still be reconciled. taskId -> record.
  private struct Record: Codable {
    var url: String
    var destination: String
    var stagedPath: String?
    var status: String   // pending | completed | failed | cancelled
    var error: String?
  }
  private var registry: [String: Record] = [:]
  private var tasks: [String: URLSessionDownloadTask] = [:]
  // Results not yet acknowledged by Dart (flushed on attach / reconcile).
  private var unreported: [String] = []

  private lazy var session: URLSession = {
    let config = URLSessionConfiguration.background(
      withIdentifier: "com.kodjodevf.mangayomi.background-download.session")
    config.isDiscretionary = false
    config.sessionSendsLaunchEvents = true
    config.allowsCellularAccess = true
    return URLSession(configuration: config, delegate: self, delegateQueue: nil)
  }()

  private var registryURL: URL {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    return base.appendingPathComponent("background-downloads.json")
  }
  private var stagingDir: URL {
    let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("bg-download-staging", isDirectory: true)
    try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    return base
  }

  private override init() {
    super.init()
    loadRegistry()
  }

  // MARK: - Channel wiring (called from didInitializeImplicitFlutterEngine)

  func attach(channel: FlutterMethodChannel) {
    self.channel = channel
    loadRegistry()
    // Re-attach live tasks the system kept alive across a relaunch.
    session.getAllTasks { tasks in
      for task in tasks {
        if let id = task.taskDescription, let download = task as? URLSessionDownloadTask {
          self.tasks[id] = download
        }
      }
    }
    flushUnreported()
  }

  func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "enqueue":
      guard let taskId = args["taskId"] as? String,
            let url = args["url"] as? String,
            let destination = args["destination"] as? String,
            let source = URL(string: url) else {
        result(FlutterError(code: "BAD_ARGS", message: "taskId/url/destination required", details: nil))
        return
      }
      var request = URLRequest(url: source)
      if let headers = args["headers"] as? [String: String] {
        for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
      }
      let task = session.downloadTask(with: request)
      task.taskDescription = taskId
      registry[taskId] = Record(url: url, destination: destination, stagedPath: nil, status: "pending", error: nil)
      tasks[taskId] = task
      saveRegistry()
      task.resume()
      scheduleProcessingTask()
      result(true)
    case "cancel":
      guard let taskId = args["taskId"] as? String else { result(false); return }
      tasks[taskId]?.cancel()
      tasks.removeValue(forKey: taskId)
      registry[taskId]?.status = "cancelled"
      saveRegistry()
      result(true)
    case "pending":
      result(registry.filter { $0.value.status == "pending" }.map { $0.key })
    case "reconcile":
      flushUnreported()
      result(true)
    case "acknowledge":
      if let taskId = args["taskId"] as? String { acknowledge(taskId: taskId) }
      result(true)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - URLSessionDownloadDelegate

  func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                  didFinishDownloadingTo location: URL) {
    guard let taskId = downloadTask.taskDescription, var record = registry[taskId] else { return }
    // Move out of the system's transient location into our staging dir before
    // the delegate returns (the system deletes `location` afterwards).
    let staged = stagingDir.appendingPathComponent(taskId)
    try? FileManager.default.removeItem(at: staged)
    do {
      try FileManager.default.moveItem(at: location, to: staged)
      record.stagedPath = staged.path
      record.status = "completed"
    } catch {
      record.status = "failed"
      record.error = error.localizedDescription
    }
    registry[taskId] = record
    tasks.removeValue(forKey: taskId)
    saveRegistry()
    report(taskId)
  }

  func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
    guard let taskId = task.taskDescription, var record = registry[taskId] else { return }
    if record.status == "completed" { return }   // already staged successfully
    if let nsError = error as NSError? {
      record.status = (nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled)
        ? "cancelled" : "failed"
      record.error = nsError.localizedDescription
    } else {
      record.status = "completed"
    }
    registry[taskId] = record
    tasks.removeValue(forKey: taskId)
    saveRegistry()
    report(taskId)
  }

  // MARK: - Reporting to Dart (matches BackgroundDownloadResult)

  private func report(_ taskId: String) {
    if !unreported.contains(taskId) { unreported.append(taskId) }
    flushUnreported()
  }

  private func flushUnreported() {
    guard let channel = channel else { return }   // engine not ready; keep queued
    for taskId in unreported {
      guard let record = registry[taskId] else { continue }
      var payload: [String: Any] = ["taskId": taskId, "status": record.status]
      if let staged = record.stagedPath { payload["localPath"] = staged }
      if let error = record.error { payload["error"] = error }
      channel.invokeMethod("onResult", arguments: payload)
    }
    unreported.removeAll()
  }

  /// Dart calls this once it has placed a staged file at its destination, so
  /// the staging copy can be removed. (Channel method "acknowledge".)
  func acknowledge(taskId: String) {
    if let record = registry[taskId], let staged = record.stagedPath {
      try? FileManager.default.removeItem(atPath: staged)
    }
    registry.removeValue(forKey: taskId)
    saveRegistry()
  }

  // MARK: - BGProcessingTask (best-effort drain, NOT the download mechanism)

  func handleProcessingTask(_ task: BGProcessingTask) {
    // The background URLSession runs independently of this task; the processing
    // task only buys extra foreground-equivalent time to flush results and let
    // pending transfers progress. Expiration must cancel cleanly.
    task.expirationHandler = { [weak self] in
      self?.saveRegistry()
      task.setTaskCompleted(success: false)
    }
    flushUnreported()
    scheduleProcessingTask()
    task.setTaskCompleted(success: true)
  }

  private func scheduleProcessingTask() {
    guard #available(iOS 13.0, *) else { return }
    let request = BGProcessingTaskRequest(identifier: Self.processingTaskIdentifier)
    request.requiresNetworkConnectivity = true
    request.requiresExternalPower = false
    request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
    try? BGTaskScheduler.shared.submit(request)
  }

  // MARK: - Persistence

  private func loadRegistry() {
    guard let data = try? Data(contentsOf: registryURL),
          let decoded = try? JSONDecoder().decode([String: Record].self, from: data) else { return }
    registry = decoded
    unreported = registry.filter { $0.value.status != "pending" }.map { $0.key }
  }

  private func saveRegistry() {
    guard let data = try? JSONEncoder().encode(registry) else { return }
    try? data.write(to: registryURL, options: .atomic)
  }
}
