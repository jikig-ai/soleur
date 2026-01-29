//! Command Line Interface
//!
//! This module contains CLI parsing and the interactive REPL.

mod args;
pub mod repl;

pub use args::{Cli, Command};
pub use repl::Repl;
