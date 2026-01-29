//! CLI Argument Parsing

use clap::{Parser, Subcommand};
use std::path::PathBuf;

/// Soleur - Company-as-a-Service Platform
///
/// An AI orchestration engine that enables solo founders to leverage
/// AI agent swarms for building and scaling businesses.
#[derive(Parser, Debug, Default)]
#[command(name = "soleur")]
#[command(version, about, long_about = None)]
pub struct Cli {
    /// Path to configuration file
    #[arg(short, long, global = true)]
    pub config: Option<PathBuf>,

    /// Enable verbose output
    #[arg(short, long, global = true)]
    pub verbose: bool,

    #[command(subcommand)]
    pub command: Option<Command>,
}

/// Available commands
#[derive(Subcommand, Debug)]
pub enum Command {
    /// Start an interactive sparring session with the Strategic Sparring Partner
    Spar {
        /// Resume a specific session by ID
        #[arg(short, long)]
        session: Option<String>,

        /// Skip the resume prompt and start fresh
        #[arg(long)]
        fresh: bool,
    },

    /// List all saved sessions
    Sessions,

    /// Show the decision ledger for the current project
    Decisions {
        /// Project name (defaults to current directory name)
        #[arg(short, long)]
        project: Option<String>,
    },
}

#[cfg(test)]
mod tests {
    use super::*;
    use clap::CommandFactory;

    #[test]
    fn verify_cli() {
        Cli::command().debug_assert();
    }

    #[test]
    fn test_parse_spar() {
        let cli = Cli::parse_from(["soleur", "spar"]);
        assert!(matches!(cli.command, Some(Command::Spar { .. })));
    }

    #[test]
    fn test_parse_sessions() {
        let cli = Cli::parse_from(["soleur", "sessions"]);
        assert!(matches!(cli.command, Some(Command::Sessions)));
    }

    #[test]
    fn test_parse_decisions() {
        let cli = Cli::parse_from(["soleur", "decisions"]);
        assert!(matches!(cli.command, Some(Command::Decisions { .. })));
    }
}
