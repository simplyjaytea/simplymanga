//! Anime reliability engine — pure Rust, no Flutter dependency.
//!
//! Orchestrates server pre-flight probing, failure classification, fallback
//! state and host health memory. HTTP itself is performed by an injected
//! callback (the FRB layer wires it to Dart's MClient so DoH / Cloudflare /
//! cookie handling keep applying); this module never issues raw requests.

pub mod classify;
pub mod health;
pub mod probe;
pub mod state;
