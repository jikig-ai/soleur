# Pencil Headless CLI Integration Brainstorm

**Date:** 2026-03-24
**Status:** Complete
**Branch:** feat-pencil-headless-cli

## What We're Building

Integrate the new Pencil headless CLI (npm package) as Tier 0 (highest priority) in the Pencil MCP detection stack. This adds a fully headless design capability that doesn't require Pencil Desktop or an IDE, enabling CI/CD design workflows and frictionless agent-driven design sessions.

### Components

1. **MCP adapter wrapper** (`pencil-mcp-adapter.js`) — a Node.js MCP server that spawns `pencil interactive --out <file.pen>` and translates MCP protocol to/from the interactive shell format
2. **Updated `check_deps.sh`** — adds Tier 0 detection for the Pencil npm CLI via `npm list -g` with auto-install capability
3. **Updated `pencil-setup` skill** — registers the adapter as the MCP server when headless CLI is available
4. **Node version management** — the CLI requires Node `>=22.9.0`; detection script must verify this

## Why This Approach

### MCP Adapter > Direct CLI Integration

The headless CLI's `pencil interactive` mode exposes the exact same tools as the Desktop/IDE MCP server (batch_design, batch_get, get_screenshot, etc.) but through a custom REPL format, not MCP protocol. Writing an adapter means:

- **ux-design-lead agent works unchanged** — same tool names, same parameters
- **Transparent fallback** — if headless fails, fall through to Desktop/IDE tiers seamlessly
- **Single integration point** — only the MCP registration changes, not the agent code

### Why Not Agent Delegation (`pencil --prompt`)

The `pencil --prompt` mode runs Pencil's own Claude agent internally. This:

- Doubles API costs (our Claude + Pencil's Claude)
- Loses fine-grained control over the design process
- Can't iterate based on screenshot feedback mid-design
- The ux-design-lead agent's workflow becomes a black box

### Why Not Wait for Native MCP

The founder may add `--mcp` flag to `pencil interactive` in the future (see Feedback section), but Phase 1 needs this now. The adapter is lightweight enough that replacing it with native MCP later is low cost.

## Key Decisions

1. **Tier 0 priority** — Headless CLI is checked first, before Desktop CLI, Desktop binary, and IDE extension
2. **MCP adapter pattern** — Node.js MCP server wrapping `pencil interactive` over stdin/stdout
3. **Auto-install** — `check_deps.sh` installs the Pencil npm CLI to `~/.local/node_modules` via npm if not found (no sudo needed)
4. **Auth requirement** — `pencil interactive` requires auth (PENCIL_CLI_KEY or `pencil login`). The setup flow guides users through this.
5. **Node version gate** — The CLI requires Node >=22.9.0. Detection script checks this and skips Tier 0 if unavailable.
6. **nvm/fnm awareness** — If system Node is too old but nvm/fnm has a compatible version, the adapter script should use it

## Open Questions

1. **PENCIL_CLI_KEY provisioning** — Can the founder provide a CI/CD key? Or must each user run `pencil login`?
2. **Interactive mode protocol stability** — Is the `tool_name({ args })` format a stable API? Could break across versions.
3. **Concurrent sessions** — Can multiple `pencil interactive` sessions run simultaneously? (Relevant for parallel agent work)
4. **Rate limits** — Does the Pencil API have rate limits that affect batch_design/get_screenshot calls?
5. **File locking** — Does `pencil interactive --out file.pen` lock the output file? Can we write to it from outside?

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Engineering (CTO)

**Summary:** The MCP adapter pattern is architecturally sound — it's a well-understood stdio proxy pattern. Key risks: the interactive shell protocol isn't formally specified (parsing could be fragile), Node version requirement (>=22.9.0) adds a dependency gate, and the adapter needs robust error handling for when the pencil process crashes mid-session. Recommend: version-pin the adapter to the CLI version and add integration tests.

### Product (CPO)

**Summary:** This unblocks Phase 1 screen design workflow entirely. The headless capability enables design-in-CI patterns and removes the Desktop/IDE friction that currently blocks automated design sessions. The tiered fallback ensures no existing users are disrupted. Key consideration: the auth setup step (pencil login) is a friction point for first-time users — the setup skill should guide them through it clearly.

### Marketing (CMO)

**Summary:** CONFIDENTIAL — the Pencil headless CLI npm package URL must not be shared publicly until the founder announces it. No public marketing content should reference the headless CLI. Internally, this is a differentiator: "design with AI agents, no desktop app needed." When the package goes public, coordinate a co-announcement with the pencil.dev founder.

## Capability Gaps

- **No native MCP mode** — The headless CLI speaks its own REPL format, not MCP protocol. Our adapter bridges this, but a native `--mcp` flag from the founder would eliminate it.
- **Node version requirement** — Node >=22.9.0 is newer than many system installs. The detection script must handle version managers (nvm, fnm) or skip gracefully.

## Feedback for Pencil Founder

### Feature Request: Native MCP Mode

**Request:** Add `pencil interactive --mcp` flag that makes the interactive shell speak MCP protocol (JSON-RPC over stdio) instead of the custom REPL format.

**Why:** Claude Code (and other MCP clients) natively connect to MCP servers. A native MCP mode would eliminate the need for adapter wrappers, reduce latency, and make integration trivial: `claude mcp add pencil -- pencil interactive --mcp --out design.pen`.

### Friction Log

1. **Node version**: CLI requires >=22.9.0 but many systems have older versions. The error message (`ERR_REQUIRE_ESM`) is cryptic — could benefit from a Node version check on startup.
2. **Auth for interactive mode**: Even local headless rendering requires auth. Consider making local-only operations (batch_design, batch_get, save) work offline, with auth only for API-dependent tools (get_style_guide, AI image generation).
3. **`pencil login` in non-interactive shells**: Fails with ExitPromptError when stdin isn't a TTY. A `pencil login --token <key>` non-interactive auth flow would help CI/CD.
4. **No `mcp-server` subcommand**: The Desktop-installed CLI has `pencil mcp-server`. The npm CLI doesn't expose this, making the existing detection in check_deps.sh miss it. The version string `pencil 0.2.3` also doesn't match the `pencil\.dev` or `pencil v` patterns used for detection.
5. **Package size**: 58MB unpacked is large for an npm package. Consider shipping platform-specific packages to avoid bundling all 6 MCP server binaries.
