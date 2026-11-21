import 'package:mangayomi/modules/anime/utils/audio_track_fallback.dart';
import 'package:mangayomi/modules/anime/utils/video_prefs.dart';
import 'package:mangayomi/src/rust/api/anime_engine.dart';

/// Whether a playback error must reach server-level fallback. Audio-decoder
/// initialization errors are handled by the audio-track fallback path instead;
/// every other non-empty failure (403, dead stream, timeout, buffering) used to
/// be silently dropped — it must now be routed to the reliability engine.
bool shouldRouteToServerFallback(String message) {
  final m = message.trim();
  return m.isNotEmpty && !isAudioDecoderInitializationError(m);
}

/// The server URL identifying an external-stream prefs option, or null for a
/// local track (which is not a switchable server).
String? serverUrlOf(VideoPrefs prefs) {
  return prefs.isLocal ? null : prefs.videoTrack?.id;
}

/// Ordered external-server candidates excluding the current and tried servers.
List<VideoPrefs> serverFallbackCandidates({
  required List<VideoPrefs> options,
  required String? currentUrl,
  Set<String> triedUrls = const {},
}) {
  return options.where((p) {
    final url = serverUrlOf(p);
    return url != null && url != currentUrl && !triedUrls.contains(url);
  }).toList();
}

/// The player's next step after the engine classifies a failure.
sealed class ServerFallbackPlan {}

class SwitchServer extends ServerFallbackPlan {
  final VideoPrefs prefs;
  SwitchServer(this.prefs);
}

class AwaitChallenge extends ServerFallbackPlan {
  final String server;
  AwaitChallenge(this.server);
}

class FallbackExhausted extends ServerFallbackPlan {
  final String reason;
  FallbackExhausted(this.reason);
}

class NoFallback extends ServerFallbackPlan {}

/// Map a Rust engine action onto a concrete player plan using the available
/// server options. Pure: no FFI, no playback mutation.
ServerFallbackPlan planFromEngineAction(
  EngineAction action,
  List<VideoPrefs> options,
) {
  return switch (action) {
    EngineAction_Play(:final server) => _switchTo(server, options),
    EngineAction_Retry(:final server) => _switchTo(server, options),
    EngineAction_AwaitChallenge(:final server) => AwaitChallenge(server),
    EngineAction_Fail(:final reason) => FallbackExhausted(reason),
    EngineAction_Idle() => NoFallback(),
  };
}

ServerFallbackPlan _switchTo(String server, List<VideoPrefs> options) {
  final matches = options.where((p) => serverUrlOf(p) == server).toList();
  if (matches.isEmpty) {
    return FallbackExhausted('no playable option for server $server');
  }
  return SwitchServer(matches.first);
}
