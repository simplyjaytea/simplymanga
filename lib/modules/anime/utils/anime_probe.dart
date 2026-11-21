/// Pure adapters between the app's HTTP layer and the Rust anime engine's
/// probe contract. No FFI or network here so the mapping is unit-testable;
/// the MClient-backed driver lives in `anime_probe_service.dart`.
library;

import 'package:mangayomi/src/rust/api/anime_engine.dart';
import 'package:mangayomi/src/rust/engine/classify.dart';

/// Build the request the engine hands to the Dart probe callback. GET by
/// default because challenge detection needs a body snippet; MClient's cookie
/// manager supplies User-Agent and clearance cookies on the wire.
ProbeRequest buildProbeRequest(String url, {String method = 'GET'}) {
  return ProbeRequest(url: url, method: method, headers: const []);
}

/// Map an HTTP response into the engine's [ProbeResponse]. Header keys are
/// lowercased so the Rust classifier can match `cf-mitigated`, `server`, etc.
/// regardless of how the server capitalised them.
ProbeResponse mapHttpResponse({
  required int status,
  required Map<String, String> headers,
  String? bodySnippet,
}) {
  return ProbeResponse(
    status: status,
    headers: headers.entries
        .map((e) => (e.key.toLowerCase(), e.value))
        .toList(growable: false),
    bodySnippet: bodySnippet,
  );
}

/// Map a transport failure (DNS, connect, timeout) into a [ProbeResponse] the
/// classifier turns into the right [FailureClass]. No status means the request
/// never completed.
ProbeResponse mapProbeError(Object error) {
  return ProbeResponse(
    status: null,
    headers: const [],
    error: error.toString(),
  );
}

/// Trim a response body to the small snippet the classifier needs to spot an
/// anti-bot interstitial, avoiding pulling whole pages across the bridge.
String bodySnippetOf(String body, {int maxChars = 512}) {
  if (body.length <= maxChars) return body;
  return body.substring(0, maxChars);
}

/// Only an `ok` classification is immediately playable; a challenge is live
/// but gated behind a WebView the user must clear.
bool isPlayableClass(FailureClass class_) => class_ == FailureClass.ok;

/// The playable server URLs from a ranked probe result, best-first, preserving
/// the engine's health-weighted ordering and dropping challenged/dead hosts.
List<String> liveServerUrls(List<RankedServer> ranked) {
  return ranked
      .where((r) => isPlayableClass(r.class_))
      .map((r) => r.server)
      .toList(growable: false);
}
