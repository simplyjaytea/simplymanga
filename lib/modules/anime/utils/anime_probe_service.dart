import 'dart:async';

import 'package:mangayomi/services/http/m_client.dart';
import 'package:mangayomi/src/rust/api/anime_engine.dart';

import 'anime_probe.dart';

/// Drive the Rust engine's concurrent probe through the app's MClient seam so
/// DoH, Cloudflare retry and clearance cookies all apply — a raw HTTP prober
/// would mislabel CF-challenged but live hosts as dead. Returns the engine's
/// health-ranked servers; the caller filters with [liveServerUrls].
///
/// HTTP stays in Dart on purpose: Rust owns concurrency, per-host timeout,
/// classification and ranking, but never opens a socket itself.
Future<List<RankedServer>> probeAnimeServers(
  AnimeEngine engine, {
  Duration timeout = const Duration(seconds: 8),
}) {
  Future<ProbeResponse> handler(ProbeRequest req) async {
    final client = MClient.init(showCloudFlareError: false);
    try {
      final uri = Uri.parse(req.url);
      final headers = {for (final (k, v) in req.headers) k: v};
      final resp = req.method.toUpperCase() == 'HEAD'
          ? await client.head(uri, headers: headers)
          : await client.get(uri, headers: headers);
      return mapHttpResponse(
        status: resp.statusCode,
        headers: resp.headers,
        bodySnippet: bodySnippetOf(resp.body),
      );
    } catch (e) {
      return mapProbeError(e);
    } finally {
      client.close();
    }
  }

  return engine.probeServers(
    requestHandler: handler,
    timeoutMs: BigInt.from(timeout.inMilliseconds),
  );
}
