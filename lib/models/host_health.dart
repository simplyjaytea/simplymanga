import 'package:isar_community/isar.dart';
import 'package:mangayomi/models/tracker_library_cache.dart' show fastHash;
part 'host_health.g.dart';

/// Durable memory of how an anime host has behaved, so a restart does not
/// forget which servers were fast, which were dead, and which kept throwing
/// anti-bot challenges. The Rust engine computes the EWMA live; this is the
/// Dart/Isar cache the engine's `healthSnapshot()` is meant to feed.
///
/// One row per host. The id is derived from the host, so saving a fresh
/// snapshot replaces the previous row instead of accumulating duplicates.
@collection
@Name("Host Health")
class HostHealth {
  Id get id => fastHash(host);

  /// The server identifier (URL) the engine ranks. Unique through [id].
  late String host;

  /// Exponentially weighted success rate, 0..1. Defaults to the Rust
  /// engine's neutral prior (health.rs HostHealth::new = 0.5) so an unseen
  /// host ranks identically on both sides once hydration is wired (E-09).
  double successEwma = 0.5;

  /// Exponentially weighted latency in milliseconds.
  double latencyEwmaMs = 0;

  /// Number of results folded into the EWMA.
  int samples = 0;

  /// Anti-bot challenges seen for this host.
  int challenges = 0;

  /// When this row was last written (ms since epoch).
  int updatedAt = 0;
}