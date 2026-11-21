/// Pure mapping between the Rust engine's [HostHealthView] and the persisted
/// [HostHealth] row, plus a Dart-side ranking over stored health. No Isar and
/// no native bridge here, so it is unit-testable headless.
library;

import 'package:mangayomi/models/host_health.dart';
import 'package:mangayomi/src/rust/api/anime_engine.dart';

/// Copy an engine snapshot entry onto a persisted row, stamping [updatedAt].
HostHealth hostHealthFromView(HostHealthView view, {required int updatedAt}) {
  return HostHealth()
    ..host = view.host
    ..successEwma = view.successEwma
    ..latencyEwmaMs = view.latencyEwmaMs
    ..samples = view.samples
    ..challenges = view.challenges
    ..updatedAt = updatedAt;
}

/// Read a persisted row back as the engine's view type.
HostHealthView hostHealthToView(HostHealth row) => HostHealthView(
  host: row.host,
  successEwma: row.successEwma,
  latencyEwmaMs: row.latencyEwmaMs,
  samples: row.samples,
  challenges: row.challenges,
);

/// Map a whole snapshot, stamping one shared timestamp.
List<HostHealth> hostHealthsFromViews(
  List<HostHealthView> views, {
  required int updatedAt,
}) => [for (final view in views) hostHealthFromView(view, updatedAt: updatedAt)];

/// The same score the Rust engine ranks by: success rewarded, latency and
/// challenges penalised. Kept in sync with `engine/health.rs`.
double hostHealthScore(HostHealth row) =>
    row.successEwma * 1000 - row.latencyEwmaMs * 0.05 - row.challenges * 2;

/// Hosts best-first by stored health, for pre-ranking servers before a probe.
List<String> rankHostsByHealth(List<HostHealth> rows) {
  final sorted = [...rows]
    ..sort((a, b) => hostHealthScore(b).compareTo(hostHealthScore(a)));
  return sorted.map((row) => row.host).toList(growable: false);
}