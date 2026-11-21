import 'package:isar_community/isar.dart';
import 'package:mangayomi/models/host_health.dart';
import 'package:mangayomi/models/tracker_library_cache.dart' show fastHash;
import 'package:mangayomi/utils/host_health_mapping.dart';
import 'package:mangayomi/repositories/db.dart';
import 'package:mangayomi/repositories/db_write_queue.dart';
import 'package:mangayomi/src/rust/api/anime_engine.dart';

/// Persists the Rust engine's host-health snapshot so server reliability
/// memory survives a restart. Writes go through the shared [dbWriteQueue]
/// like every other repository; reads are sync for callers outside a txn.
class HostHealthRepository {
  /// Upsert a snapshot. Each row's id is derived from its host, so a repeated
  /// host replaces its previous row. An empty snapshot is a no-op.
  Future<void> saveSnapshot(List<HostHealthView> views) {
    if (views.isEmpty) return Future.value();
    final now = DateTime.now().millisecondsSinceEpoch;
    final rows = hostHealthsFromViews(views, updatedAt: now);
    return dbWriteQueue.run(() async {
      await isar.writeTxn(() => isar.hostHealths.putAll(rows));
    });
  }

  List<HostHealth> getAll() => isar.hostHealths.where().findAllSync();

  HostHealth? getByHost(String host) => isar.hostHealths.getSync(fastHash(host));

  Future<void> clear() => dbWriteQueue.run(() async {
    await isar.writeTxn(() => isar.hostHealths.clear());
  });
}

final hostHealthRepository = HostHealthRepository();