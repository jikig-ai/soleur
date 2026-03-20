# Runtime Agent Discovery and Project-Aware Filtering

**Date:** 2026-02-12
**Status:** Active
**Issue:** #46

## What We're Building

A two-part system for smarter agent selection in the Soleur plugin:

1. **Project-type detection with local agent filtering** -- Commands like `/soleur:review` detect the project stack (Rails, TypeScript, Go, etc.) via file-based heuristics and only spawn agents relevant to that stack. Rails-specific agents (`kieran-rails-reviewer`, `dhh-rails-reviewer`) won't run on a TypeScript project.

2. **External agent discovery via MCP servers** -- Integrate tessl.io and skills.sh as MCP servers (same pattern as context7 for docs). Any command can query these registries to discover relevant agents for the detected project type, present them to the user with a tiered security assessment, and install approved agents as first-class plugin files in `plugins/soleur/agents/`.

## Why This Approach

**Approach A: Agent Metadata + MCP Discovery Layer** was chosen over alternatives because:

- **Builds on what exists** -- Agent markdown files already have YAML frontmatter. Adding `frameworks` and `languages` tags is minimal change.
- **Follows proven patterns** -- context7 MCP server is already used for docs lookup. Same integration model for skill discovery.
- **Ships incrementally** -- Local filtering works immediately with no external dependencies. MCP discovery layers on top.
- **No magic** -- Agents remain plain markdown files. Commands explicitly reference the filtering logic. No hidden middleware.

**Rejected alternatives:**
- **Central Registry Config (Approach B):** Adds an indirection layer (agent-registry.yaml) when frontmatter metadata already exists. Single file becomes a bottleneck.
- **Smart Command Middleware (Approach C):** Hidden middleware violates the plugin's "commands are readable markdown" philosophy. Hard to debug.

## Key Decisions

1. **Scope: Plugin-wide, not just review** -- Any command can discover and suggest external agents, not just `/soleur:review`.

2. **Detection: File-based heuristics** -- Check for `Gemfile` (Ruby/Rails), `package.json` (JS/TS), `go.mod` (Go), `Cargo.toml` (Rust), `pyproject.toml`/`requirements.txt` (Python), etc. No CLAUDE.md metadata required.

3. **Trust: Tiered vetting** -- Quick summary by default (source, popularity, last updated). Opt-in deep scan on request (permission scope, tool access, vulnerability analysis).

4. **User consent: Always required** -- No agent installs without explicit user approval. Show rationale for why the agent is suggested and security risk score.

5. **Persistence: First-class plugin agents** -- Approved external agents are installed into `plugins/soleur/agents/` as standard markdown files. They persist across sessions and work offline.

6. **Agent metadata: Frontmatter tags** -- Add `frameworks`, `languages`, and `applies-to` fields to agent YAML frontmatter for filtering.

7. **MCP integration: Same as context7** -- tessl.io and skills.sh become MCP tool sources. Commands query them like any other MCP tool.

## Open Questions

- **tessl.io and skills.sh API availability** -- Do these registries expose APIs suitable for MCP server integration? Need to verify.
- **Agent versioning** -- How to handle updates to externally-installed agents? Auto-check on sync? Manual?
- **Conflict resolution** -- What happens when an external agent overlaps with a local one?
- **Quality bar** -- Minimum criteria for an external agent to be suggested (e.g., must have description, must specify applicable frameworks)?
