//! AI Agents
//!
//! This module contains agent abstractions and implementations.

pub mod markers;
mod sparring_partner;
mod traits;

pub use sparring_partner::SparringPartner;
pub use traits::Agent;
