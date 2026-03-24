---
module: pencil-setup
date: 2026-03-24
problem_type: integration_issue
component: tooling
symptoms:
  - "Pencil headless CLI interactive mode speaks custom REPL format, not MCP protocol"
  - "Existing check_deps.sh detection patterns do not match headless CLI version string"
  - "Binding names ephemeral across batch_design calls — adapter must track node IDs"
root_cause: wrong_api
resolution_type: documentation_update
severity: high
tags: [pencil, headless, mcp, interactive-mode, cli-integration]
---

# Troubleshooting: Pencil Headless CLI Uses Custom REPL, Not MCP Protocol

## Problem

The Pencil headless CLI npm package was expected to expose an MCP server subcommand like the Desktop-installed CLI (`pencil mcp-server`). Instead, it provides an interactive shell (`pencil interactive`) that speaks a custom REPL format (`tool_name({ key: value })`), requiring an MCP adapter wrapper for Claude Code integration.

## Environment

- Module: pencil-setup
- Node Version: >=22.9.0 required
- Affected Component: Pencil MCP integration, check_deps.sh detection
- Date: 2026-03-24

## Symptoms

- `pencil interactive --out output.pen` starts a REPL, not an MCP server
- The CLI help shows no `mcp-server` subcommand (Desktop CLI has it, headless doesn't)
- Version string `pencil 0.2.3` doesn't match existing detection patterns (`pencil\.dev` or `pencil v`)
- MCP server binaries are bundled in `dist/out/` but require `--app` flag for Desktop/IDE connection
- Auth is required even for local headless rendering (no offline mode)

## What Didn't Work

**Attempted: Using bundled MCP server binary directly**

- The `dist/out/mcp-server-linux-x64` binary requires `-app` flag connecting to Desktop/IDE
- Without a running GUI app, the binary has nothing to connect to
- The headless rendering is in the Node.js CLI layer, not the Go MCP binary

**Attempted: npm global install**

- `npm install -g` failed with EACCES (no sudo)
- Fix: `npm install --prefix ~/.local` works

**Attempted: Running with system Node**

- Node v21.7.3 threw `ERR_REQUIRE_ESM` — CLI requires >=22.9.0
- Fix: Source nvm from `.bashrc` and use `nvm use 22`

## Session Errors

**npm global install EACCES permission denied**

- **Recovery:** Used `npm install --prefix ~/.local` to install without sudo
- **Prevention:** Always try `--prefix ~/.local` first for npm global installs in no-sudo environments

**Node version ERR_REQUIRE_ESM**

- **Recovery:** Found nvm via `.bashrc` grep, switched to Node 22
- **Prevention:** Check Node version before running npm-installed CLIs. When Node is too old, probe for nvm/fnm in shell config files

**fnm binary not found (3 attempts)**

- **Recovery:** Discovered nvm was the actual version manager (not fnm) by grepping `.bashrc`
- **Prevention:** Check `.bashrc`/`.zshrc` for version manager sourcing patterns before assuming a specific manager

**printf escape handling broke pipe input**

- **Recovery:** Used temp file instead of inline printf for multi-line stdin
- **Prevention:** For multi-line stdin to interactive processes, write to temp file and redirect, don't use printf with escape sequences through pipes

**Confidentiality leak — committed npm package name to public repo**

- **Recovery:** Redacted all references, updated GitHub issue, force-pushed
- **Prevention:** When handling confidential external package information, redact identifiers BEFORE first commit, not after. Check with CMO assessment before any public artifact creation

**WebFetch 403 on npm page**

- **Recovery:** Used npm registry API (`registry.npmjs.org`) directly via curl
- **Prevention:** npm package pages often block automated fetching. Use the registry JSON API instead

## Solution

The Pencil headless CLI has two modes:

1. **Agent mode** (`pencil --out design.pen --prompt "Create X"`) — autonomous agent using Claude Agent SDK
2. **Interactive mode** (`pencil interactive --out output.pen`) — direct MCP-like tool access via REPL

The interactive mode exposes the same tools as Desktop/IDE MCP (batch_design, batch_get, get_screenshot, etc.) but through stdin/stdout with format `tool_name({ key: value })`.

**Integration approach:** Write a Node.js MCP adapter that:

1. Spawns `pencil interactive --out <file.pen>` as a child process
2. Speaks MCP protocol on stdio (to Claude Code)
3. Translates MCP tool calls to interactive shell commands
4. Parses responses and maps binding names to actual node IDs

**Key discoveries from testing:**

```bash
# Auth works via Doppler-stored PENCIL_CLI_KEY
export PENCIL_CLI_KEY=$(doppler secrets get PENCIL_CLI_KEY -p soleur -c dev --plain)
pencil status  # Shows authenticated

# Interactive mode works headlessly (no display server needed)
echo 'get_editor_state({ include_schema: false })
exit()' | pencil interactive --out /tmp/test.pen

# batch_design creates nodes with correct API
# save() works programmatically (no Ctrl+S needed!)
# Bindings (hero, heading) are ephemeral within single batch_design call
```

**Detection approach for check_deps.sh:**

```bash
# Detect npm headless CLI (Tier 0)
npm list -g @pencil.dev/cli 2>/dev/null | grep -q "@pencil.dev/cli" && return 0
# Or check local install
test -x ~/.local/node_modules/.bin/pencil && return 0
```

## Why This Works

The headless CLI bundles CanvasKit (Skia) for server-side rendering, eliminating the Desktop/IDE dependency. The `pencil interactive` shell provides the same design primitives as the MCP server but through a different transport. An MCP adapter wrapper bridges this gap transparently — the ux-design-lead agent calls the same MCP tools, unaware that they're being proxied through the adapter.

The `save()` command resolves a longstanding constraint documented in constitution.md line 101 where changes only persisted via manual Ctrl+S.

## Prevention

- When investigating a new CLI tool, always run `--help` and test actual behavior before assuming it matches the Desktop/IDE version's API surface
- Check npm registry JSON API (`registry.npmjs.org/<package>/latest`) for package metadata — more reliable than WebFetch on npm pages
- For confidential pre-announcement packages: redact identifiers from all public artifacts (issues, PRs, committed files) BEFORE first commit
- When a CLI requires a newer Node version, probe for nvm/fnm in shell config before declaring the version unavailable

## Related Issues

- See also: [pencil-desktop-standalone-mcp-three-tier-detection](./2026-03-10-pencil-desktop-standalone-mcp-three-tier-detection.md) — the original three-tier cascade design
- See also: [pencil-mcp-local-binary-constraint](./2026-02-14-pencil-mcp-local-binary-constraint.md) — now partially outdated (npm package exists)
- See also: [electron-appimage-crashes-in-headless-terminal](./2026-03-10-electron-appimage-crashes-in-headless-terminal.md) — headless CLI solves this
