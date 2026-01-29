//! Soleur - Company-as-a-Service Platform
//!
//! An AI orchestration engine that enables solo founders to leverage
//! AI agent swarms for building and scaling businesses.

pub mod agents;
pub mod cli;
pub mod config;
pub mod conversation;
pub mod error;
pub mod providers;

pub use config::Config;
pub use error::{Result, SoleurError};
