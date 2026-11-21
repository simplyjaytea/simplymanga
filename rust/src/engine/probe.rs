//! Parallel server pre-flight probing — orchestration only.
//!
//! HTTP is performed by an injected async callback (the FRB layer wires it to
//! Dart's MClient so DoH / Cloudflare / cookie handling keep applying). This
//! module owns concurrency, per-probe timeout and cancellation; it never issues
//! a raw request, so a CF-challenged host is classified, not marked dead.

use std::future::Future;
use std::time::{Duration, Instant};

use futures_util::future::join_all;
use tokio_util::sync::CancellationToken;

use super::classify::{classify, FailureClass, ProbeOutcome};

#[derive(Debug, Clone)]
pub struct ProbeResult {
    pub server: String,
    pub outcome: ProbeOutcome,
    pub class: FailureClass,
    pub latency_ms: f64,
}

/// Probe every server concurrently, bounding each by `timeout` and honouring
/// `cancel`. Results preserve input order.
pub async fn probe_all<F, Fut>(
    servers: Vec<String>,
    timeout: Duration,
    cancel: CancellationToken,
    probe: F,
) -> Vec<ProbeResult>
where
    F: Fn(String) -> Fut + Clone,
    Fut: Future<Output = ProbeOutcome>,
{
    let futs = servers.into_iter().map(|server| {
        let probe = probe.clone();
        let cancel = cancel.clone();
        async move {
            let start = Instant::now();
            let outcome = tokio::select! {
                _ = cancel.cancelled() => ProbeOutcome {
                    error: Some("cancelled".into()),
                    ..Default::default()
                },
                r = tokio::time::timeout(timeout, probe(server.clone())) => match r {
                    Ok(o) => o,
                    Err(_) => ProbeOutcome {
                        error: Some("operation timed out".into()),
                        ..Default::default()
                    },
                },
            };
            let latency_ms = start.elapsed().as_secs_f64() * 1000.0;
            let class = classify(&outcome);
            ProbeResult {
                server,
                outcome,
                class,
                latency_ms,
            }
        }
    });
    join_all(futs).await
}

#[cfg(test)]
mod tests {
    use super::*;

    fn ok_outcome() -> ProbeOutcome {
        ProbeOutcome {
            status: Some(200),
            ..Default::default()
        }
    }

    #[tokio::test]
    async fn collects_a_result_for_every_server() {
        let servers = vec!["a".to_string(), "b".to_string(), "c".to_string()];
        let res = probe_all(
            servers,
            Duration::from_secs(1),
            CancellationToken::new(),
            |_s| async { ok_outcome() },
        )
        .await;
        assert_eq!(res.len(), 3);
        assert!(res.iter().all(|r| r.class == FailureClass::Ok));
    }

    #[tokio::test]
    async fn classifies_each_outcome() {
        let servers = vec!["live".to_string(), "dead".to_string()];
        let res = probe_all(
            servers,
            Duration::from_secs(1),
            CancellationToken::new(),
            |s| async move {
                if s == "dead" {
                    ProbeOutcome {
                        status: Some(403),
                        ..Default::default()
                    }
                } else {
                    ok_outcome()
                }
            },
        )
        .await;
        let live = res.iter().find(|r| r.server == "live").unwrap();
        let dead = res.iter().find(|r| r.server == "dead").unwrap();
        assert_eq!(live.class, FailureClass::Ok);
        assert_eq!(dead.class, FailureClass::Forbidden);
    }

    #[tokio::test]
    async fn slow_probe_times_out() {
        let res = probe_all(
            vec!["slow".to_string()],
            Duration::from_millis(50),
            CancellationToken::new(),
            |_s| async {
                tokio::time::sleep(Duration::from_millis(300)).await;
                ok_outcome()
            },
        )
        .await;
        assert_eq!(res.len(), 1);
        assert_eq!(res[0].class, FailureClass::Timeout);
    }

    #[tokio::test]
    async fn probes_run_concurrently_not_serially() {
        let start = Instant::now();
        let servers = vec!["a".to_string(), "b".to_string(), "c".to_string()];
        let _res = probe_all(
            servers,
            Duration::from_secs(2),
            CancellationToken::new(),
            |_s| async {
                tokio::time::sleep(Duration::from_millis(150)).await;
                ok_outcome()
            },
        )
        .await;
        // Serial would be ~450ms; concurrent must be well under that.
        assert!(start.elapsed() < Duration::from_millis(350));
    }

    #[tokio::test]
    async fn cancellation_short_circuits_probes() {
        let cancel = CancellationToken::new();
        cancel.cancel();
        let start = Instant::now();
        let res = probe_all(
            vec!["a".to_string()],
            Duration::from_secs(5),
            cancel,
            |_s| async {
                tokio::time::sleep(Duration::from_secs(3)).await;
                ok_outcome()
            },
        )
        .await;
        assert_eq!(res.len(), 1);
        assert!(start.elapsed() < Duration::from_millis(500));
        assert_ne!(res[0].class, FailureClass::Ok);
    }

    #[tokio::test]
    async fn empty_input_yields_empty_output() {
        let res = probe_all(
            Vec::new(),
            Duration::from_secs(1),
            CancellationToken::new(),
            |_s| async { ok_outcome() },
        )
        .await;
        assert!(res.is_empty());
    }
}
