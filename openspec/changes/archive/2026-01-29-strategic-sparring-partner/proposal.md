## Why

Soleur needs its first functional agent to validate the core thesis: that AI can provide meaningful leverage to solo founders. The "Strategic Sparring Partner" is the ideal starting point because it solves an immediate, real problem (founders need critical feedback on ideas) and enables recursive dogfooding—Soleur will use this agent to refine Soleur itself.

## What Changes

- Add a model provider abstraction (strategy pattern) enabling pluggable AI backends, starting with Claude Opus 4.5
- Implement an interactive CLI-based conversation system with session persistence
- Create the "Strategic Sparring Partner" agent with Socratic prompting for business idea critique
- Add a Decision Ledger to track key strategic decisions made during conversations
- Establish the foundational architecture for all future Soleur agents

## Capabilities

### New Capabilities

- `model-providers`: Abstraction layer for AI model providers (strategy pattern). Enables BYOI (Bring Your Own Intelligence) with pluggable backends. Initial implementation: Claude/Anthropic.
- `conversation-management`: Session-based conversation system with message history, persistence (JSON files), and resume capability across CLI invocations.
- `sparring-partner-agent`: The Strategic Sparring Partner agent—a Socratic business advisor that reads project context (README, etc.), asks probing questions, challenges assumptions, and helps founders stress-test ideas.
- `decision-ledger`: Tracking system for key decisions made during sparring sessions. Persisted as markdown files for git-trackability and human review.
- `cli-repl`: Interactive command-line interface with REPL, input history, and slash commands (/save, /load, /decisions, /quit).

### Modified Capabilities

<!-- None - this is greenfield development -->

## Impact

- **Code**: Complete rewrite of `src/main.rs`; new module structure under `src/`
- **Dependencies**: Adds tokio, reqwest, serde, clap, async-trait, anyhow, chrono, uuid, rustyline, toml
- **APIs**: Requires `ANTHROPIC_API_KEY` environment variable (or config file)
- **Filesystem**: Creates `~/.soleur/` directory for config, sessions, and decision ledgers
- **User workflow**: Introduces `soleur spar` command as primary entry point
