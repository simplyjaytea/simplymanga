//! Host health memory — EWMA success + latency, computed in Rust.
//!
//! Persistence is owned by Dart/Isar (the FRB layer serialises these values);
//! this module is pure computation. A challenged host is treated as neutral,
//! never as a dead host, so anti-bot interstitials don't poison the ranking.

use super::classify::FailureClass;

const ALPHA: f64 = 0.3;

#[derive(Debug, Clone)]
pub struct HostHealth {
    pub host: String,
    pub success_ewma: f64,
    pub latency_ewma_ms: f64,
    pub samples: u32,
    pub challenges: u32,
    pub last_failure: Option<FailureClass>,
}

impl HostHealth {
    pub fn new(host: impl Into<String>) -> Self {
        Self {
            host: host.into(),
            success_ewma: 0.5,
            latency_ewma_ms: 0.0,
            samples: 0,
            challenges: 0,
            last_failure: None,
        }
    }

    /// Record one observation. `Ok` raises success; hard failures lower it;
    /// `Challenge` is neutral (the host is alive, just gated).
    pub fn record(&mut self, class: FailureClass, latency_ms: f64) {
        self.samples += 1;
        let obs = match class {
            FailureClass::Ok => 1.0,
            FailureClass::Challenge => {
                self.challenges += 1;
                0.5
            }
            _ => {
                self.last_failure = Some(class);
                0.0
            }
        };
        self.success_ewma = ALPHA * obs + (1.0 - ALPHA) * self.success_ewma;
        if class == FailureClass::Ok {
            self.latency_ewma_ms = if self.latency_ewma_ms == 0.0 {
                latency_ms
            } else {
                ALPHA * latency_ms + (1.0 - ALPHA) * self.latency_ewma_ms
            };
        }
    }

    /// Higher is better. Success dominates; latency and challenges are mild
    /// penalties that never zero a live, challenged host.
    pub fn score(&self) -> f64 {
        self.success_ewma * 1000.0 - self.latency_ewma_ms * 0.05 - (self.challenges as f64) * 2.0
    }
}

/// Sort hosts best-first by score (in place).
pub fn rank(hosts: &mut [HostHealth]) {
    hosts.sort_by(|a, b| {
        b.score()
            .partial_cmp(&a.score())
            .unwrap_or(std::cmp::Ordering::Equal)
    });
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn new_host_has_neutral_prior() {
        let h = HostHealth::new("a");
        assert_eq!(h.success_ewma, 0.5);
        assert_eq!(h.samples, 0);
    }

    #[test]
    fn success_ewma_converges_toward_one_on_repeated_ok() {
        let mut h = HostHealth::new("a");
        for _ in 0..10 {
            h.record(FailureClass::Ok, 100.0);
        }
        assert!(h.success_ewma > 0.9, "got {}", h.success_ewma);
        assert_eq!(h.samples, 10);
    }

    #[test]
    fn repeated_dead_host_drives_success_toward_zero() {
        let mut h = HostHealth::new("a");
        for _ in 0..10 {
            h.record(FailureClass::DeadHost, 0.0);
        }
        assert!(h.success_ewma < 0.1, "got {}", h.success_ewma);
        assert_eq!(h.last_failure, Some(FailureClass::DeadHost));
    }

    #[test]
    fn challenge_is_never_treated_as_dead() {
        let mut h = HostHealth::new("a");
        for _ in 0..10 {
            h.record(FailureClass::Challenge, 0.0);
        }
        // Neutral observation keeps success near the prior, not zero.
        assert!(h.success_ewma > 0.4, "got {}", h.success_ewma);
        assert_eq!(h.challenges, 10);
        assert_eq!(h.last_failure, None);
    }

    #[test]
    fn latency_ewma_tracks_ok_observations() {
        let mut h = HostHealth::new("a");
        h.record(FailureClass::Ok, 200.0);
        assert_eq!(h.latency_ewma_ms, 200.0);
        h.record(FailureClass::Ok, 100.0);
        assert!(h.latency_ewma_ms < 200.0 && h.latency_ewma_ms > 100.0);
    }

    #[test]
    fn healthy_host_scores_above_dead_host() {
        let mut healthy = HostHealth::new("healthy");
        let mut dead = HostHealth::new("dead");
        for _ in 0..10 {
            healthy.record(FailureClass::Ok, 100.0);
            dead.record(FailureClass::DeadHost, 0.0);
        }
        assert!(healthy.score() > dead.score());
    }

    #[test]
    fn challenged_host_scores_above_dead_host() {
        let mut challenged = HostHealth::new("cf");
        let mut dead = HostHealth::new("dead");
        for _ in 0..10 {
            challenged.record(FailureClass::Challenge, 0.0);
            dead.record(FailureClass::DeadHost, 0.0);
        }
        assert!(challenged.score() > dead.score());
    }

    #[test]
    fn rank_orders_best_first() {
        let mut healthy = HostHealth::new("healthy");
        let mut dead = HostHealth::new("dead");
        for _ in 0..10 {
            healthy.record(FailureClass::Ok, 100.0);
            dead.record(FailureClass::DeadHost, 0.0);
        }
        let mut hosts = vec![dead, healthy];
        rank(&mut hosts);
        assert_eq!(hosts[0].host, "healthy");
        assert_eq!(hosts[1].host, "dead");
    }
}
