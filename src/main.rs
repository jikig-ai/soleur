//! Soleur - Company-as-a-Service Platform
//!
//! CLI entry point

use clap::Parser;

use soleur::agents::{Agent, SparringPartner};
use soleur::cli::{Cli, Command, Repl, repl};
use soleur::config::Config;
use soleur::conversation::{DecisionLedger, Session, SessionStore};
use soleur::error::Result;
use soleur::providers::ClaudeProvider;

#[tokio::main]
async fn main() -> Result<()> {
    let cli = Cli::parse();

    // Load configuration
    let config = Config::load()?;
    config.ensure_dirs()?;

    // Handle commands
    match cli.command {
        Some(Command::Spar { session, fresh }) => {
            run_spar(&config, session, fresh).await?;
        }
        Some(Command::Sessions) => {
            list_sessions(&config)?;
        }
        Some(Command::Decisions { project }) => {
            show_decisions(&config, project)?;
        }
        None => {
            // Default to spar command
            run_spar(&config, None, false).await?;
        }
    }

    Ok(())
}

/// Run the sparring session
async fn run_spar(config: &Config, session_id: Option<String>, fresh: bool) -> Result<()> {
    // Get API key
    let api_key = config.api_key()?;

    // Create provider and agent
    let provider = ClaudeProvider::new(api_key, &config.default_model);
    let agent = SparringPartner::new();

    // Get or create session
    let store = SessionStore::new(config.sessions_dir());
    let project_name = DecisionLedger::project_name_from_cwd();

    let session = if let Some(id) = session_id {
        // Load specific session
        store.load_by_str(&id)?
    } else if !fresh {
        // Try to resume latest session
        if let Some(latest) = store.get_latest()? {
            if repl::confirm(
                &format!(
                    "Resume session {} from {}?",
                    &latest.id.to_string()[..8],
                    latest.updated_at.format("%Y-%m-%d %H:%M")
                ),
                true,
            )
            .unwrap_or(true)
            {
                latest
            } else {
                create_new_session(&agent, &project_name)?
            }
        } else {
            create_new_session(&agent, &project_name)?
        }
    } else {
        create_new_session(&agent, &project_name)?
    };

    // Run REPL
    let mut repl = Repl::new(&agent, &provider, session, config);
    repl.run().await
}

/// Create a new session, optionally loading README
fn create_new_session(agent: &SparringPartner, project_name: &str) -> Result<Session> {
    let mut session = Session::new(agent.agent_type(), project_name);

    // Offer to load README
    if repl::readme_exists()
        && repl::confirm("Load README.md as project context?", true).unwrap_or(false)
    {
        let content = repl::load_readme()?;
        session.set_context(content);
        println!("Loaded README.md as context.");
    }

    Ok(session)
}

/// List all saved sessions
fn list_sessions(config: &Config) -> Result<()> {
    let store = SessionStore::new(config.sessions_dir());
    let sessions = store.list()?;

    if sessions.is_empty() {
        println!("No saved sessions found.");
        return Ok(());
    }

    println!("\nSaved sessions:\n");
    for meta in sessions {
        println!(
            "  {} | {} | {} messages | {}",
            &meta.id.to_string()[..8],
            meta.project_name,
            meta.message_count,
            meta.updated_at.format("%Y-%m-%d %H:%M")
        );
        if let Some(preview) = meta.last_preview {
            println!("    └─ {preview}");
        }
        println!();
    }

    Ok(())
}

/// Show decisions for a project
fn show_decisions(config: &Config, project: Option<String>) -> Result<()> {
    let ledger = DecisionLedger::new(config.decisions_dir());
    let project_name = project.unwrap_or_else(DecisionLedger::project_name_from_cwd);

    match ledger.read_full(&project_name)? {
        Some(content) => println!("{content}"),
        None => println!("No decisions recorded for project '{project_name}'."),
    }

    Ok(())
}
