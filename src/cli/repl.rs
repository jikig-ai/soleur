//! Interactive REPL for Agent Conversations

use rustyline::error::ReadlineError;
use rustyline::{DefaultEditor, Result as RlResult};
use std::io::{self, Write};
use tokio_stream::StreamExt;

use crate::agents::Agent;
use crate::config::Config;
use crate::conversation::{DecisionLedger, Session, SessionStore};
use crate::error::{Result, SoleurError};
use crate::providers::{CompletionConfig, ModelProvider};

/// Interactive REPL for agent conversations
pub struct Repl<'a, A: Agent, P: ModelProvider> {
    agent: &'a A,
    provider: &'a P,
    session: Session,
    session_store: SessionStore,
    decision_ledger: DecisionLedger,
    config: CompletionConfig,
}

impl<'a, A: Agent, P: ModelProvider> Repl<'a, A, P> {
    /// Create a new REPL
    pub fn new(agent: &'a A, provider: &'a P, session: Session, app_config: &Config) -> Self {
        let config = CompletionConfig {
            model: app_config.default_model.clone(),
            ..Default::default()
        };

        Self {
            agent,
            provider,
            session,
            session_store: SessionStore::new(app_config.sessions_dir()),
            decision_ledger: DecisionLedger::new(app_config.decisions_dir()),
            config,
        }
    }

    /// Run the REPL
    pub async fn run(&mut self) -> Result<()> {
        let mut rl = DefaultEditor::new().map_err(|e| SoleurError::Io(io::Error::other(e)))?;

        // Display header
        self.print_header();

        // If we have context but no messages, kick off the sparring session automatically
        if self.session.project_context.is_some() && self.session.messages.is_empty() {
            println!("Analyzing your project context...\n");
            let kickoff = "I've just shared my project's README with you. Please analyze it thoroughly and start our sparring session by identifying the most critical assumptions or claims that need to be stress-tested. Ask me your first probing question.";
            if let Err(e) = self.process_input(kickoff).await {
                eprintln!("\nError starting session: {e}");
            }
        }

        loop {
            let readline = rl.readline("> ");

            match readline {
                Ok(line) => {
                    let line = line.trim();

                    if line.is_empty() {
                        continue;
                    }

                    // Add to history
                    let _ = rl.add_history_entry(line);

                    // Check for commands
                    if line.starts_with('/') {
                        match self.handle_command(line).await {
                            Ok(should_exit) => {
                                if should_exit {
                                    break;
                                }
                            }
                            Err(e) => {
                                eprintln!("Error: {e}");
                            }
                        }
                        continue;
                    }

                    // Process user input with agent
                    if let Err(e) = self.process_input(line).await {
                        eprintln!("\nError: {e}");
                    }
                }
                Err(ReadlineError::Interrupted) => {
                    println!("\nUse /quit to exit");
                    continue;
                }
                Err(ReadlineError::Eof) => {
                    println!("\nGoodbye!");
                    self.save_session()?;
                    break;
                }
                Err(err) => {
                    eprintln!("Error: {err}");
                    break;
                }
            }
        }

        Ok(())
    }

    /// Print the REPL header
    fn print_header(&self) {
        println!();
        println!("=== {} ===", self.agent.name());
        println!(
            "Session: {} | Project: {}",
            &self.session.id.to_string()[..8],
            self.session.project_name
        );
        println!("Type /help for commands, /quit to exit");
        println!();
    }

    /// Process user input and get agent response
    async fn process_input(&mut self, input: &str) -> Result<()> {
        // Add user message to session
        self.session.add_user_message(input);

        // Show thinking indicator
        print!("\nThinking...");
        io::stdout().flush()?;

        // Get streaming response from agent
        let stream = self
            .agent
            .respond(&self.session, input, self.provider, &self.config)
            .await?;

        // Clear thinking indicator
        print!("\r           \r");
        io::stdout().flush()?;

        // Collect response while streaming
        let mut response = String::new();
        tokio::pin!(stream);

        while let Some(chunk_result) = stream.next().await {
            let chunk = chunk_result?;
            print!("{}", chunk.text);
            io::stdout().flush()?;
            response.push_str(&chunk.text);

            if chunk.done {
                break;
            }
        }

        println!("\n");

        // Add assistant response to session
        self.session.add_assistant_message(&response);

        // Auto-save session
        self.save_session()?;

        Ok(())
    }

    /// Handle a slash command
    async fn handle_command(&mut self, input: &str) -> Result<bool> {
        let parts: Vec<&str> = input.splitn(2, ' ').collect();
        let command = parts[0].to_lowercase();
        let args = parts.get(1).map(|s| s.trim());

        match command.as_str() {
            "/quit" | "/q" => {
                println!("Saving session and exiting...");
                self.save_session()?;
                println!("Goodbye!");
                Ok(true)
            }
            "/save" => {
                self.save_session()?;
                println!("Session saved.");
                Ok(false)
            }
            "/load" => {
                if let Some(id) = args {
                    match self.session_store.load_by_str(id) {
                        Ok(session) => {
                            self.session = session;
                            println!("Loaded session {}", id);
                            self.print_header();
                        }
                        Err(e) => {
                            eprintln!("Failed to load session: {e}");
                        }
                    }
                } else {
                    eprintln!("Usage: /load <session-id>");
                }
                Ok(false)
            }
            "/decisions" => {
                match self.decision_ledger.read_full(&self.session.project_name)? {
                    Some(content) => println!("\n{content}"),
                    None => println!("No decisions recorded for this project yet."),
                }
                Ok(false)
            }
            "/decide" => {
                if let Some(text) = args {
                    let project_name = self.session.project_name.clone();
                    let decision = self.session.add_decision(text);
                    self.decision_ledger.append(&project_name, decision)?;
                    println!("Decision recorded: {text}");
                } else {
                    eprintln!("Usage: /decide <decision text>");
                }
                Ok(false)
            }
            "/context" => {
                if let Some(path) = args {
                    match std::fs::read_to_string(path) {
                        Ok(content) => {
                            self.session.set_context(&content);
                            println!("Loaded context from {} ({} chars)", path, content.len());
                        }
                        Err(e) => {
                            eprintln!("Failed to read file: {e}");
                        }
                    }
                } else {
                    eprintln!("Usage: /context <filepath>");
                }
                Ok(false)
            }
            "/help" => {
                self.print_help();
                Ok(false)
            }
            _ => {
                eprintln!("Unknown command: {command}");
                eprintln!("Type /help for available commands.");
                Ok(false)
            }
        }
    }

    /// Print help text
    fn print_help(&self) {
        println!();
        println!("Available commands:");
        println!("  /quit, /q          Save session and exit");
        println!("  /save              Save current session");
        println!("  /load <id>         Load a specific session");
        println!("  /decisions         Show recorded decisions");
        println!("  /decide <text>     Record a decision");
        println!("  /context <path>    Load file as project context");
        println!("  /help              Show this help");
        println!();
    }

    /// Save the current session
    fn save_session(&self) -> Result<()> {
        self.session_store.save(&self.session)
    }
}

/// Prompt the user for yes/no confirmation
pub fn confirm(prompt: &str, default: bool) -> RlResult<bool> {
    let suffix = if default { "[Y/n]" } else { "[y/N]" };
    print!("{prompt} {suffix} ");
    io::stdout().flush().ok();

    let mut input = String::new();
    io::stdin().read_line(&mut input)?;
    let input = input.trim().to_lowercase();

    Ok(match input.as_str() {
        "y" | "yes" => true,
        "n" | "no" => false,
        "" => default,
        _ => default,
    })
}

/// Check if README.md exists in current directory
pub fn readme_exists() -> bool {
    std::path::Path::new("README.md").exists()
}

/// Load README.md content
pub fn load_readme() -> Result<String> {
    Ok(std::fs::read_to_string("README.md")?)
}
