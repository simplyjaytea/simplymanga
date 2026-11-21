//! Failure classification for probe outcomes and playback errors.
//!
//! The critical invariant (review 07 blocker): a Cloudflare / anti-bot
//! challenge is NEVER classified as a dead host. It must route to a WebView
//! challenge action, otherwise probing poisons health memory and marks live
//! CF-protected hosts dead.

/// The outcome of a single HTTP probe, supplied by the injected callback.
#[derive(Debug, Clone, Default)]
pub struct ProbeOutcome {
    pub status: Option<u16>,
    pub headers: Vec<(String, String)>,
    pub error: Option<String>,
    pub body_snippet: Option<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FailureClass {
    Ok,
    /// Anti-bot interstitial (Cloudflare etc.) — needs a WebView, not a retry.
    Challenge,
    Forbidden,
    ExpiredToken,
    GeoBlock,
    DeadHost,
    Timeout,
    ServerError,
    DecoderError,
    Unknown,
}

fn header<'a>(o: &'a ProbeOutcome, name: &str) -> Option<&'a str> {
    o.headers
        .iter()
        .find(|(k, _)| k.eq_ignore_ascii_case(name))
        .map(|(_, v)| v.as_str())
}

fn contains_any(hay: &str, needles: &[&str]) -> bool {
    let low = hay.to_ascii_lowercase();
    needles.iter().any(|n| low.contains(n))
}

/// Classify an HTTP probe outcome. Order matters: transport errors and
/// challenges take precedence over bare status codes.
pub fn classify(o: &ProbeOutcome) -> FailureClass {
    // 1. Transport errors take precedence over any status code.
    if let Some(err) = &o.error {
        if contains_any(err, &["timed out", "timeout", "deadline"]) {
            return FailureClass::Timeout;
        }
        if contains_any(
            err,
            &[
                "dns",
                "resolve",
                "lookup address",
                "connect",
                "refused",
                "unreachable",
                "no route",
                "network is down",
                "reset by peer",
            ],
        ) {
            return FailureClass::DeadHost;
        }
        return FailureClass::Unknown;
    }

    let body = o.body_snippet.as_deref().unwrap_or("");
    let server = header(o, "server").unwrap_or("");

    // 2. Anti-bot challenge — NEVER a dead host (review 07 blocker).
    if header(o, "cf-mitigated")
        .map(|v| v.eq_ignore_ascii_case("challenge"))
        .unwrap_or(false)
    {
        return FailureClass::Challenge;
    }
    let challenge_body = contains_any(
        body,
        &[
            "just a moment",
            "challenge-platform",
            "cf-chl",
            "cdn-cgi/challenge",
            "attention required",
            "cf-browser-verification",
        ],
    );
    let cloudflare = contains_any(server, &["cloudflare"]) || header(o, "cf-ray").is_some();
    if challenge_body && (cloudflare || matches!(o.status, Some(403) | Some(503))) {
        return FailureClass::Challenge;
    }

    // 3. Geo restriction.
    if o.status == Some(451) {
        return FailureClass::GeoBlock;
    }
    if contains_any(
        body,
        &[
            "not available in your",
            "available in your region",
            "geo-restrict",
            "geoblock",
        ],
    ) {
        return FailureClass::GeoBlock;
    }

    // 4. Auth / token failure.
    if o.status == Some(401) {
        return FailureClass::ExpiredToken;
    }
    if contains_any(
        body,
        &[
            "token expired",
            "expired token",
            "invalid token",
            "token has expired",
            "unauthorized",
            "invalid_grant",
        ],
    ) {
        return FailureClass::ExpiredToken;
    }

    // 5. Bare status code.
    match o.status {
        Some(s) if (200..300).contains(&s) => FailureClass::Ok,
        Some(403) => FailureClass::Forbidden,
        Some(s) if (500..600).contains(&s) => FailureClass::ServerError,
        _ => FailureClass::Unknown,
    }
}

/// Classify an mpv / media playback error string (not an HTTP outcome).
pub fn classify_playback_error(error: &str) -> FailureClass {
    if contains_any(
        error,
        &[
            "audio decoder",
            "video decoder",
            "decoder init",
            "failed to initialize",
            "decode",
            "codec",
        ],
    ) {
        FailureClass::DecoderError
    } else if contains_any(error, &["timed out", "timeout"]) {
        FailureClass::Timeout
    } else {
        FailureClass::Unknown
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn outcome(status: u16) -> ProbeOutcome {
        ProbeOutcome {
            status: Some(status),
            ..Default::default()
        }
    }

    #[test]
    fn ok_2xx() {
        assert_eq!(classify(&outcome(200)), FailureClass::Ok);
        assert_eq!(classify(&outcome(206)), FailureClass::Ok);
    }

    #[test]
    fn cf_mitigated_challenge_header_is_challenge_not_dead() {
        let mut o = outcome(403);
        o.headers.push(("cf-mitigated".into(), "challenge".into()));
        assert_eq!(classify(&o), FailureClass::Challenge);
    }

    #[test]
    fn cloudflare_503_interstitial_body_is_challenge() {
        let mut o = outcome(503);
        o.headers.push(("server".into(), "cloudflare".into()));
        o.body_snippet = Some("<title>Just a moment...</title>".into());
        assert_eq!(classify(&o), FailureClass::Challenge);
    }

    #[test]
    fn challenge_platform_script_is_challenge() {
        let mut o = outcome(403);
        o.body_snippet = Some("/cdn-cgi/challenge-platform/h/b/scripts".into());
        assert_eq!(classify(&o), FailureClass::Challenge);
    }

    #[test]
    fn plain_403_without_cloudflare_is_forbidden() {
        assert_eq!(classify(&outcome(403)), FailureClass::Forbidden);
    }

    #[test]
    fn status_401_is_expired_token() {
        assert_eq!(classify(&outcome(401)), FailureClass::ExpiredToken);
    }

    #[test]
    fn token_expired_body_is_expired_token() {
        let mut o = outcome(403);
        o.body_snippet = Some("{\"error\":\"token expired\"}".into());
        assert_eq!(classify(&o), FailureClass::ExpiredToken);
    }

    #[test]
    fn status_451_is_geo_block() {
        assert_eq!(classify(&outcome(451)), FailureClass::GeoBlock);
    }

    #[test]
    fn region_restriction_body_is_geo_block() {
        let mut o = outcome(200);
        o.body_snippet = Some("This content is not available in your region".into());
        assert_eq!(classify(&o), FailureClass::GeoBlock);
    }

    #[test]
    fn server_error_5xx() {
        assert_eq!(classify(&outcome(500)), FailureClass::ServerError);
        assert_eq!(classify(&outcome(502)), FailureClass::ServerError);
    }

    #[test]
    fn dns_resolution_error_is_dead_host() {
        let o = ProbeOutcome {
            error: Some("dns error: failed to lookup address information".into()),
            ..Default::default()
        };
        assert_eq!(classify(&o), FailureClass::DeadHost);
    }

    #[test]
    fn connection_refused_is_dead_host() {
        let o = ProbeOutcome {
            error: Some("tcp connect error: Connection refused (os error 111)".into()),
            ..Default::default()
        };
        assert_eq!(classify(&o), FailureClass::DeadHost);
    }

    #[test]
    fn transport_timeout_is_timeout() {
        let o = ProbeOutcome {
            error: Some("operation timed out".into()),
            ..Default::default()
        };
        assert_eq!(classify(&o), FailureClass::Timeout);
    }

    #[test]
    fn challenge_never_classifies_as_dead_host_regression() {
        // The exact poisoning bug from review 07: a CF-challenged live host
        // must never be recorded as dead.
        let mut o = outcome(403);
        o.headers.push(("cf-mitigated".into(), "challenge".into()));
        o.headers.push(("server".into(), "cloudflare".into()));
        assert_ne!(classify(&o), FailureClass::DeadHost);
        assert_eq!(classify(&o), FailureClass::Challenge);
    }

    #[test]
    fn audio_decoder_init_error_is_decoder_error() {
        assert_eq!(
            classify_playback_error("Failed to initialize audio decoder"),
            FailureClass::DecoderError
        );
    }

    #[test]
    fn unknown_playback_error_is_unknown() {
        assert_eq!(classify_playback_error("something odd"), FailureClass::Unknown);
    }
}
