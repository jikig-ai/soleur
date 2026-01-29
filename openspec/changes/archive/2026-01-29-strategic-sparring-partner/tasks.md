# Tasks

## 1. Project Setup

- [x] 1.1 Update Cargo.toml with all required dependencies (tokio, reqwest, serde, clap, async-trait, anyhow, thiserror, dirs, uuid, chrono, rustyline, toml)
- [x] 1.2 Create module structure: lib.rs, error.rs, config.rs, and subdirectories for providers/, conversation/, agents/, cli/
- [x] 1.3 Create mod.rs files for each submodule

## 2. Error Handling

- [x] 2.1 Define SoleurError enum in error.rs with variants for Config, Api, Io, Session errors
- [x] 2.2 Implement std::error::Error and Display for SoleurError
- [x] 2.3 Create Result type alias for convenience

## 3. Configuration

- [x] 3.1 Define Config struct with api_key, default_model, and data_dir fields
- [x] 3.2 Implement config loading from ~/.soleur/config.toml with serde
- [x] 3.3 Implement environment variable override for ANTHROPIC_API_KEY
- [x] 3.4 Create default config with sensible defaults (claude-sonnet-4-20250514)
- [x] 3.5 Add helper to ensure ~/.soleur/ directory exists

## 4. Model Provider Abstraction

- [x] 4.1 Define Message struct with role (User/Assistant/System), content, timestamp
- [x] 4.2 Define CompletionConfig struct with model, temperature, max_tokens
- [x] 4.3 Define ModelProvider trait with complete(), name(), model_id() methods
- [x] 4.4 Implement async streaming support in the trait design

## 5. Claude Provider Implementation

- [x] 5.1 Create ClaudeProvider struct with api_key and default model
- [x] 5.2 Implement Anthropic Messages API request construction
- [x] 5.3 Implement streaming response parsing (SSE format)
- [x] 5.4 Implement ModelProvider trait for ClaudeProvider
- [x] 5.5 Add error handling for API errors (rate limits, auth failures, etc.)
- [x] 5.6 Write unit tests with mock responses

## 6. Session Management

- [x] 6.1 Define Session struct with id, messages, decisions, timestamps, project_context
- [x] 6.2 Define Decision struct with content, timestamp, session_id, tags
- [x] 6.3 Implement Session::new() and Session::add_message()
- [x] 6.4 Implement Session::add_decision() for tracking decisions
- [x] 6.5 Implement JSON serialization/deserialization for Session

## 7. Session Persistence

- [x] 7.1 Create SessionStore struct managing ~/.soleur/sessions/
- [x] 7.2 Implement save() to write session as pretty-printed JSON
- [x] 7.3 Implement load() to restore session from UUID
- [x] 7.4 Implement list() to enumerate all saved sessions with metadata
- [x] 7.5 Implement get_latest() to find most recent session
- [x] 7.6 Write integration tests for persistence roundtrip

## 8. Decision Ledger

- [x] 8.1 Create DecisionLedger struct managing ~/.soleur/decisions/
- [x] 8.2 Implement append() to add decision to markdown file
- [x] 8.3 Implement load() to read all decisions for a project
- [x] 8.4 Implement project name derivation from current directory
- [x] 8.5 Create markdown header on first decision for new project

## 9. Agent Abstraction

- [x] 9.1 Define Agent trait with name(), system_prompt(), respond() methods
- [x] 9.2 Create AgentContext struct to pass session and provider to agents

## 10. Sparring Partner Agent

- [x] 10.1 Create SparringPartner struct implementing Agent trait
- [x] 10.2 Write comprehensive system prompt (Socratic, challenging, business-savvy)
- [x] 10.3 Implement context injection (prepend README content to system prompt)
- [x] 10.4 Implement respond() that builds messages and calls provider
- [x] 10.5 Add decision identification logic (detect when user makes strategic choices)

## 11. CLI Argument Parsing

- [x] 11.1 Define CLI struct with clap derive macros
- [x] 11.2 Add `spar` subcommand for interactive sparring
- [x] 11.3 Add `sessions` subcommand to list saved sessions
- [x] 11.4 Add `decisions` subcommand to show decision ledger
- [x] 11.5 Add global flags: --config, --verbose

## 12. REPL Implementation

- [x] 12.1 Create Repl struct with rustyline Editor, session, provider, agent
- [x] 12.2 Implement main loop: read input, process, display response
- [x] 12.3 Implement streaming output (print tokens as they arrive)
- [x] 12.4 Add "Thinking..." spinner while waiting for first token
- [x] 12.5 Implement Ctrl+C handling to cancel current response
- [x] 12.6 Implement Ctrl+D handling to exit gracefully

## 13. Slash Commands

- [x] 13.1 Implement command parser to detect /commands
- [x] 13.2 Implement /quit and /q to save and exit
- [x] 13.3 Implement /save to force-save current session
- [x] 13.4 Implement /load <id> to switch sessions
- [x] 13.5 Implement /decisions to display project decisions
- [x] 13.6 Implement /decide <text> to record a decision
- [x] 13.7 Implement /context <path> to attach file contents
- [x] 13.8 Implement /help to show available commands
- [x] 13.9 Handle unknown commands with helpful error message

## 14. Session Resume Flow

- [x] 14.1 On REPL start, check for existing sessions
- [x] 14.2 If recent session exists, prompt "Resume last session? [Y/n]"
- [x] 14.3 If README.md exists, prompt "Load README as context? [Y/n]"
- [x] 14.4 Display session ID and project name on startup

## 15. Main Entry Point

- [x] 15.1 Wire up CLI parsing in main.rs
- [x] 15.2 Initialize config, provider, and agent based on subcommand
- [x] 15.3 Implement `spar` subcommand to launch REPL
- [x] 15.4 Implement `sessions` subcommand to list and display sessions
- [x] 15.5 Implement `decisions` subcommand to show ledger

## 16. Testing and Polish

- [x] 16.1 Add integration test: full conversation flow with mock provider
- [x] 16.2 Add test: session save/load roundtrip
- [x] 16.3 Add test: decision ledger append and read
- [ ] 16.4 Manual testing: run full conversation with real API
- [x] 16.5 Run clippy and fix all warnings
- [x] 16.6 Run cargo fmt to ensure consistent formatting
