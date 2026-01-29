## Context

Soleur is a greenfield Rust project (Edition 2024) with no existing code beyond a placeholder main.rs. This is the foundational architecture that all future agents will build upon. The design must balance immediate utility (get a working sparring partner) with extensibility (support future model providers and agent types).

**Constraints:**
- Rust 2024 edition (latest async/await patterns available)
- CLI-first approach (no web UI in this change)
- User brings their own API keys (BYOI model)
- Must work offline for session management (only API calls require network)

**Stakeholders:**
- Solo founders using Soleur to refine business ideas
- Soleur developers extending the platform with new agents

## Goals / Non-Goals

**Goals:**
- Establish a clean, extensible architecture for AI-powered agents
- Deliver a functional Strategic Sparring Partner that provides real value
- Enable session persistence so conversations can span multiple CLI invocations
- Track key decisions in a human-readable, git-friendly format
- Make it trivial to add new model providers (OpenAI, Gemini, local models)

**Non-Goals:**
- Web UI or API server (CLI only)
- Multi-agent coordination or swarm orchestration
- Real-time collaboration or multi-user sessions
- Fine-tuning or training models
- Token usage optimization or cost tracking

## Decisions

### 1. Strategy Pattern for Model Providers

**Decision:** Use an async trait (`ModelProvider`) with runtime dispatch via `Box<dyn ModelProvider>`.

**Rationale:**
- Allows swapping providers without recompilation
- Supports configuration-driven provider selection
- Future: enables model routing (use Claude for reasoning, GPT for summaries)

**Alternatives considered:**
- Compile-time generics: Faster but requires knowing provider at build time
- Enum dispatch: Limited extensibility, can't add providers without code changes

### 2. File-based Session Persistence

**Decision:** Store sessions as JSON files in `~/.soleur/sessions/{uuid}.json`.

**Rationale:**
- Zero infrastructure (no database setup)
- Human-inspectable (debug by reading files)
- Git-friendly (users can version control their sessions if desired)
- Cross-platform via `dirs` crate

**Alternatives considered:**
- SQLite: More powerful queries but overkill for v1; adds dependency complexity
- In-memory only: Loses state between invocations, poor UX

### 3. Decision Ledger as Markdown

**Decision:** Append decisions to `~/.soleur/decisions/{project}.md` as markdown list items with timestamps.

**Rationale:**
- Human-readable without tooling
- Git-trackable (shows decision evolution over time)
- Can be copied into project repos
- Markdown renders nicely on GitHub

**Alternatives considered:**
- JSON log: Machine-readable but harder for humans to scan
- Database: Overkill for append-only decision log

### 4. Rustyline for REPL

**Decision:** Use `rustyline` for interactive input with history.

**Rationale:**
- Battle-tested readline implementation
- Built-in history (arrow keys work)
- Supports custom completers (future: command completion)
- Cross-platform

**Alternatives considered:**
- `dialoguer`: Better for prompts/menus, weaker for free-form REPL
- `ratatui`: Full TUI is overkill for v1; can add later
- Raw stdin: Poor UX (no history, no line editing)

### 5. Streaming Response Output

**Decision:** Print tokens as they arrive from the API (streaming mode).

**Rationale:**
- Better perceived latency (user sees progress immediately)
- Matches user expectations from ChatGPT/Claude web UIs
- Anthropic API supports SSE streaming natively

**Alternatives considered:**
- Wait for complete response: Simpler but feels sluggish for long responses

### 6. Environment Variables with Config Fallback

**Decision:** API keys load from environment variables first, then `~/.soleur/config.toml`.

**Rationale:**
- Environment variables are standard for secrets (12-factor app)
- Config file allows persistent settings without shell profile edits
- Order (env > file) lets users override config easily

**Alternatives considered:**
- Config file only: Less flexible for CI/automation
- Keychain integration: Complex, platform-specific

## Risks / Trade-offs

**[Risk] Anthropic API changes** → Pin to known API version; abstract behind trait so changes are localized to one file.

**[Risk] Large conversation histories exceed context window** → Implement conversation truncation in v2; for now, warn user when approaching limits.

**[Risk] Rustyline doesn't work in all terminals** → Fallback to basic stdin if rustyline fails to initialize.

**[Trade-off] JSON sessions are verbose** → Acceptable for v1; can add compression or binary format later if needed.

**[Trade-off] No encryption for stored sessions** → Sessions may contain sensitive business ideas. Document this; users can encrypt `~/.soleur/` themselves. Consider adding encryption in v2.

## Open Questions

1. **Should the agent auto-read README.md or require explicit `/context` command?**
   - Leaning toward: Ask on first run, remember preference.

2. **How to handle API errors gracefully in streaming mode?**
   - Need to display partial response + error message cleanly.

3. **Should sessions auto-save after each exchange or only on `/save`/exit?**
   - Leaning toward: Auto-save after each agent response to prevent data loss.
