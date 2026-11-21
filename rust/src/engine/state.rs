//! Server fallback state machine — pure transitions, fully unit-testable.
//!
//! Drives ordered server selection on playback failure. A challenge pauses for
//! a WebView (never advances past a live host); transient errors retry within a
//! budget; hard failures advance to the next candidate; exhaustion fails
//! honestly rather than looping forever.

use super::classify::FailureClass;

pub const MAX_ATTEMPTS: u32 = 2;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ServerState {
    Pending,
    Ready,
    Playing,
    Failed(FailureClass),
    Challenged,
}

#[derive(Debug, Clone)]
pub struct Server {
    pub id: String,
    pub state: ServerState,
    pub attempts: u32,
}

impl Server {
    pub fn new(id: impl Into<String>) -> Self {
        Self {
            id: id.into(),
            state: ServerState::Pending,
            attempts: 0,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum NextAction {
    Play(String),
    AwaitChallenge(String),
    Retry(String),
    Fail(String),
    Idle,
}

pub struct FallbackMachine {
    pub servers: Vec<Server>,
    pub max_attempts: u32,
}

impl FallbackMachine {
    pub fn new(ids: Vec<String>) -> Self {
        Self {
            servers: ids.into_iter().map(Server::new).collect(),
            max_attempts: MAX_ATTEMPTS,
        }
    }

    fn idx(&self, id: &str) -> Option<usize> {
        self.servers.iter().position(|s| s.id == id)
    }

    pub fn mark_ready(&mut self, id: &str) {
        if let Some(i) = self.idx(id) {
            if self.servers[i].state == ServerState::Pending {
                self.servers[i].state = ServerState::Ready;
            }
        }
    }

    pub fn start(&mut self, id: &str) {
        if let Some(i) = self.idx(id) {
            self.servers[i].state = ServerState::Playing;
            self.servers[i].attempts += 1;
        }
    }

    pub fn on_error(&mut self, id: &str, class: FailureClass) -> NextAction {
        let i = match self.idx(id) {
            Some(i) => i,
            None => return NextAction::Idle,
        };
        // A challenge gates a LIVE host: pause for a WebView, never advance.
        if class == FailureClass::Challenge {
            self.servers[i].state = ServerState::Challenged;
            return NextAction::AwaitChallenge(id.to_string());
        }
        self.servers[i].state = ServerState::Failed(class);
        // Transient errors retry the same server within budget.
        if matches!(class, FailureClass::Timeout | FailureClass::ServerError)
            && self.servers[i].attempts < self.max_attempts
        {
            self.servers[i].state = ServerState::Ready;
            return NextAction::Retry(id.to_string());
        }
        // Otherwise advance to the next candidate in order.
        if let Some(next) = self
            .servers
            .iter_mut()
            .find(|s| matches!(s.state, ServerState::Ready | ServerState::Pending))
        {
            next.state = ServerState::Playing;
            return NextAction::Play(next.id.clone());
        }
        NextAction::Fail(format!("all servers exhausted; last failure: {class:?}"))
    }

    pub fn on_challenge_resolved(&mut self, id: &str) -> NextAction {
        if let Some(i) = self.idx(id) {
            self.servers[i].state = ServerState::Playing;
            return NextAction::Play(id.to_string());
        }
        NextAction::Idle
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn ready_machine(ids: &[&str]) -> FallbackMachine {
        let mut m = FallbackMachine::new(ids.iter().map(|s| s.to_string()).collect());
        for id in ids {
            m.mark_ready(id);
        }
        m
    }

    #[test]
    fn dead_first_server_advances_to_next() {
        let mut m = ready_machine(&["a", "b"]);
        m.start("a");
        assert_eq!(m.on_error("a", FailureClass::DeadHost), NextAction::Play("b".into()));
        assert_eq!(m.servers[0].state, ServerState::Failed(FailureClass::DeadHost));
        assert_eq!(m.servers[1].state, ServerState::Playing);
    }

    #[test]
    fn challenge_pauses_without_advancing() {
        let mut m = ready_machine(&["a", "b"]);
        m.start("a");
        assert_eq!(
            m.on_error("a", FailureClass::Challenge),
            NextAction::AwaitChallenge("a".into())
        );
        assert_eq!(m.servers[0].state, ServerState::Challenged);
        // b must NOT be started while a challenge is pending.
        assert_eq!(m.servers[1].state, ServerState::Ready);
    }

    #[test]
    fn challenge_resolved_resumes_same_server() {
        let mut m = ready_machine(&["a", "b"]);
        m.start("a");
        m.on_error("a", FailureClass::Challenge);
        assert_eq!(m.on_challenge_resolved("a"), NextAction::Play("a".into()));
        assert_eq!(m.servers[0].state, ServerState::Playing);
    }

    #[test]
    fn all_servers_failed_fails_honestly() {
        let mut m = ready_machine(&["a"]);
        m.start("a");
        assert!(matches!(m.on_error("a", FailureClass::DeadHost), NextAction::Fail(_)));
    }

    #[test]
    fn transient_timeout_retries_within_budget_then_fails() {
        let mut m = ready_machine(&["a"]);
        m.start("a"); // attempts = 1
        assert_eq!(m.on_error("a", FailureClass::Timeout), NextAction::Retry("a".into()));
        m.start("a"); // attempts = 2
        assert!(matches!(m.on_error("a", FailureClass::Timeout), NextAction::Fail(_)));
    }

    #[test]
    fn forbidden_is_not_retried_it_advances() {
        let mut m = ready_machine(&["a", "b"]);
        m.start("a");
        assert_eq!(m.on_error("a", FailureClass::Forbidden), NextAction::Play("b".into()));
    }

    #[test]
    fn exhausted_servers_are_not_reused() {
        let mut m = ready_machine(&["a", "b"]);
        m.start("a");
        m.on_error("a", FailureClass::DeadHost); // -> Play b
        m.start("b");
        assert!(matches!(m.on_error("b", FailureClass::DeadHost), NextAction::Fail(_)));
    }
}
