//! Public flutter_rust_bridge API surface for the anime reliability engine.
//!
//! Wraps the pure `crate::engine` logic (classification, health, fallback,
//! probing) behind an opaque Dart object. HTTP probes are performed by an
//! injected `request_handler` callback wired to Dart's MClient on the Dart
//! side, so DoH / Cloudflare / cookie interceptors keep applying — the engine
//! never issues a raw request and never marks a challenged host dead.

use std::collections::HashMap;
use std::sync::Arc;
use std::time::Duration;

use flutter_rust_bridge::DartFnFuture;
use parking_lot::Mutex;
use tokio_util::sync::CancellationToken;

pub use crate::engine::classify::FailureClass;
use crate::engine::classify::{classify_playback_error, ProbeOutcome};
use crate::engine::health::HostHealth;
use crate::engine::probe::probe_all;
use crate::engine::state::{FallbackMachine, NextAction};

/// A probe request handed to the Dart callback.
#[derive(Debug, Clone)]
pub struct ProbeRequest {
    pub url: String,
    pub method: String,
    pub headers: Vec<(String, String)>,
}

/// The Dart callback's response, mapped into a [`ProbeOutcome`].
#[derive(Debug, Clone, Default)]
pub struct ProbeResponse {
    pub status: Option<u16>,
    pub headers: Vec<(String, String)>,
    pub error: Option<String>,
    pub body_snippet: Option<String>,
}

/// One ranked server after probing.
#[derive(Debug, Clone)]
pub struct RankedServer {
    pub server: String,
    pub class: FailureClass,
    pub score: f64,
    pub latency_ms: f64,
}

/// A serialisable view of host health for Dart/Isar persistence.
#[derive(Debug, Clone)]
pub struct HostHealthView {
    pub host: String,
    pub success_ewma: f64,
    pub latency_ewma_ms: f64,
    pub samples: u32,
    pub challenges: u32,
}

/// The engine's instruction to the player after an error / event.
#[derive(Debug, Clone)]
pub enum EngineAction {
    Play { server: String },
    AwaitChallenge { server: String },
    Retry { server: String },
    Fail { reason: String },
    Idle,
}

struct EngineInner {
    machine: FallbackMachine,
    health: HashMap<String, HostHealth>,
}

/// Opaque engine handle exposed to Dart. Cheap to clone (shared inner state).
pub struct AnimeEngine {
    inner: Arc<Mutex<EngineInner>>,
}

fn to_action(a: NextAction) -> EngineAction {
    match a {
        NextAction::Play(server) => EngineAction::Play { server },
        NextAction::AwaitChallenge(server) => EngineAction::AwaitChallenge { server },
        NextAction::Retry(server) => EngineAction::Retry { server },
        NextAction::Fail(reason) => EngineAction::Fail { reason },
        NextAction::Idle => EngineAction::Idle,
    }
}

impl AnimeEngine {
    /// Create an engine for an ordered list of server identifiers (URLs).
    pub fn new(servers: Vec<String>) -> AnimeEngine {
        AnimeEngine {
            inner: Arc::new(Mutex::new(EngineInner {
                machine: FallbackMachine::new(servers),
                health: HashMap::new(),
            })),
        }
    }

    /// Probe all servers concurrently through the Dart callback, update health
    /// memory, mark live servers ready, and return them ranked best-first.
    pub async fn probe_servers(
        &self,
        request_handler: impl Fn(ProbeRequest) -> DartFnFuture<ProbeResponse> + Send + Sync + 'static,
        timeout_ms: u64,
    ) -> Vec<RankedServer> {
        let servers: Vec<String> = self
            .inner
            .lock()
            .machine
            .servers
            .iter()
            .map(|s| s.id.clone())
            .collect();
        let handler = Arc::new(request_handler);
        let results = probe_all(
            servers,
            Duration::from_millis(timeout_ms),
            CancellationToken::new(),
            move |url| {
                let handler = handler.clone();
                async move {
                    let resp = handler(ProbeRequest {
                        url,
                        method: "GET".to_string(),
                        headers: Vec::new(),
                    })
                    .await;
                    ProbeOutcome {
                        status: resp.status,
                        headers: resp.headers,
                        error: resp.error,
                        body_snippet: resp.body_snippet,
                    }
                }
            },
        )
        .await;

        let mut inner = self.inner.lock();
        let mut ranked: Vec<RankedServer> = Vec::with_capacity(results.len());
        for r in results {
            let score = {
                let h = inner
                    .health
                    .entry(r.server.clone())
                    .or_insert_with(|| HostHealth::new(r.server.clone()));
                h.record(r.class, r.latency_ms);
                h.score()
            };
            if r.class == FailureClass::Ok {
                inner.machine.mark_ready(&r.server);
            }
            ranked.push(RankedServer {
                server: r.server.clone(),
                class: r.class,
                score,
                latency_ms: r.latency_ms,
            });
        }
        // Same deterministic tie-break as health::rank (E-09).
        ranked.sort_by(|a, b| {
            b.score
                .partial_cmp(&a.score)
                .unwrap_or(std::cmp::Ordering::Equal)
                .then_with(|| a.server.cmp(&b.server))
        });
        ranked
    }

    /// Report an mpv / playback error string; returns the next action.
    pub fn report_error(&self, server: String, error: String) -> EngineAction {
        let class = classify_playback_error(&error);
        self.report_class(server, class)
    }

    /// Report an explicit failure class (e.g. from a probe or extractor);
    /// drives the fallback state machine and updates health.
    pub fn report_class(&self, server: String, class: FailureClass) -> EngineAction {
        let mut inner = self.inner.lock();
        // E-01: the wired playback path never calls start() — the host opens
        // media directly and only reports failures. Count the attempt that
        // just failed here so the MAX_ATTEMPTS budget is actually enforced
        // (otherwise attempts stayed 0 and Timeout/ServerError retried the
        // same URL forever). Pure-machine callers that DO call start() keep
        // their semantics: start() marks the attempt, this marks its failure.
        inner.machine.start(&server);
        let action = inner.machine.on_error(&server, class);
        if let Some(h) = inner.health.get_mut(&server) {
            h.record(class, 0.0);
        }
        to_action(action)
    }

    /// Resume a server after the user cleared an anti-bot challenge.
    pub fn challenge_resolved(&self, server: String) -> EngineAction {
        let mut inner = self.inner.lock();
        to_action(inner.machine.on_challenge_resolved(&server))
    }

    /// Record a successful playback / probe result for health memory.
    pub fn record_result(&self, server: String, ok: bool, latency_ms: f64) {
        let mut inner = self.inner.lock();
        let h = inner
            .health
            .entry(server.clone())
            .or_insert_with(|| HostHealth::new(server));
        h.record(if ok { FailureClass::Ok } else { FailureClass::Unknown }, latency_ms);
    }

    /// Snapshot health for Dart/Isar persistence.
    pub fn health_snapshot(&self) -> Vec<HostHealthView> {
        let inner = self.inner.lock();
        inner
            .health
            .values()
            .map(|h| HostHealthView {
                host: h.host.clone(),
                success_ewma: h.success_ewma,
                latency_ewma_ms: h.latency_ewma_ms,
                samples: h.samples,
                challenges: h.challenges,
            })
            .collect()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn engine(servers: &[&str]) -> AnimeEngine {
        AnimeEngine::new(servers.iter().map(|s| s.to_string()).collect())
    }

    #[test]
    fn api_path_timeout_retry_budget_is_bounded_without_start() {
        // E-01 regression: the wired path (report_error -> report_class ->
        // on_error) never calls start(). Two timeouts on one server must
        // advance to the next candidate, not Retry the same URL forever.
        let e = engine(&["a", "b"]);
        assert!(matches!(
            e.report_class("a".into(), FailureClass::Timeout),
            EngineAction::Retry { server } if server == "a"
        ));
        assert!(matches!(
            e.report_class("a".into(), FailureClass::Timeout),
            EngineAction::Play { server } if server == "b"
        ));
    }

    #[test]
    fn api_path_report_error_string_drives_the_same_budget() {
        // The exact call the Dart mixin makes: reportError(server, error).
        let e = engine(&["a", "b"]);
        let first = e.report_error("a".into(), "tcp: Connection timed out".into());
        assert!(matches!(first, EngineAction::Retry { ref server } if server == "a"));
        let second = e.report_error("a".into(), "tcp: Connection timed out".into());
        assert!(matches!(second, EngineAction::Play { ref server } if server == "b"));
    }

    #[test]
    fn api_path_single_server_exhausts_after_max_attempts() {
        let e = engine(&["a"]);
        assert!(matches!(
            e.report_class("a".into(), FailureClass::Timeout),
            EngineAction::Retry { .. }
        ));
        assert!(matches!(
            e.report_class("a".into(), FailureClass::Timeout),
            EngineAction::Fail { .. }
        ));
    }

    #[test]
    fn api_path_server_error_budget_is_bounded() {
        let e = engine(&["a", "b"]);
        assert!(matches!(
            e.report_class("a".into(), FailureClass::ServerError),
            EngineAction::Retry { .. }
        ));
        assert!(matches!(
            e.report_class("a".into(), FailureClass::ServerError),
            EngineAction::Play { .. }
        ));
    }

    #[test]
    fn api_path_challenge_still_pauses_and_resumes() {
        let e = engine(&["a", "b"]);
        assert!(matches!(
            e.report_class("a".into(), FailureClass::Challenge),
            EngineAction::AwaitChallenge { ref server } if server == "a"
        ));
        assert!(matches!(
            e.challenge_resolved("a".into()),
            EngineAction::Play { ref server } if server == "a"
        ));
    }

    #[test]
    fn api_path_exhausted_server_is_not_resurrected() {
        let e = engine(&["a", "b"]);
        e.report_class("a".into(), FailureClass::Timeout);
        e.report_class("a".into(), FailureClass::Timeout); // -> Play b
        // b fails hard; a is exhausted and must not be picked again.
        assert!(matches!(
            e.report_class("b".into(), FailureClass::DeadHost),
            EngineAction::Fail { .. }
        ));
    }
}
