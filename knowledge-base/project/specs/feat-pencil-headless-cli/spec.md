# Pencil Headless CLI Integration

**Issue:** #1087
**Branch:** feat-pencil-headless-cli
**Brainstorm:** [2026-03-24-pencil-headless-cli-brainstorm.md](../../brainstorms/2026-03-24-pencil-headless-cli-brainstorm.md)

## Problem Statement

The current Pencil integration requires either Pencil Desktop running or an IDE with the Pencil extension. This blocks fully headless design sessions and CI/CD design workflows. The pencil.dev team has released a headless CLI (npm package) that bundles its own Skia renderer and exposes the same design tools through an interactive shell.

## Goals

- G1: Add headless CLI as Tier 0 (highest priority) in the Pencil detection stack
- G2: Write an MCP adapter that wraps `pencil interactive` so existing agents work unchanged
- G3: Auto-install `the Pencil npm CLI` when headless tier is selected
- G4: Maintain backward compatibility with Desktop/IDE tiers
- G5: Document friction points as feedback for the pencil.dev founder

## Non-Goals

- Replacing the Desktop/IDE integration paths (they remain as fallbacks)
- Using `pencil --prompt` agent delegation mode (loses control, doubles API cost)
- Building a full MCP server from scratch (adapter wraps existing tools)
- Public announcement of the headless CLI (founder hasn't announced yet)

## Functional Requirements

- **FR1:** `check_deps.sh` detects `the Pencil npm CLI` via `npm list -g` or local install check as Tier 0
- **FR2:** `check_deps.sh` auto-installs `the Pencil npm CLI` to `~/.local/node_modules` when not found and auto-install is enabled
- **FR3:** `check_deps.sh` verifies Node >= 22.9.0 before attempting headless tier
- **FR4:** MCP adapter spawns `pencil interactive --out <file.pen>` and speaks MCP protocol on stdio
- **FR5:** MCP adapter translates all Pencil tools: batch_design, batch_get, export_nodes, find_empty_space_on_canvas, get_editor_state, get_guidelines, get_screenshot, get_style_guide, get_style_guide_tags, get_variables, replace_all_matching_properties, search_all_unique_properties, set_variables, snapshot_layout
- **FR6:** MCP adapter handles `open_document` by (re)starting `pencil interactive` with the target file
- **FR7:** `pencil-setup` SKILL.md registers the adapter as MCP server when headless tier is selected
- **FR8:** Auth check: detect auth status via `pencil status` and guide user through `pencil login` if needed
- **FR9:** Graceful degradation: if headless tier fails (auth, Node version, crash), fall through to next tier

## Technical Requirements

- **TR1:** MCP adapter written in Node.js, zero external dependencies beyond the MCP SDK
- **TR2:** Adapter uses stdio transport (standard MCP pattern)
- **TR3:** Child process management: spawn, restart, graceful shutdown of `pencil interactive`
- **TR4:** Node version detection must handle nvm and fnm version managers
- **TR5:** No secrets in code — auth uses `PENCIL_CLI_KEY` env var or `pencil login` session
- **TR6:** The adapter script must be platform-independent (macOS + Linux)

## Acceptance Criteria

- [ ] `check_deps.sh` correctly identifies and prioritizes headless CLI as Tier 0
- [ ] `check_deps.sh` auto-installs `the Pencil npm CLI` when missing and `--auto` flag is set
- [ ] MCP adapter successfully translates batch_design, batch_get, and get_screenshot calls
- [ ] ux-design-lead agent can create a .pen file end-to-end using the headless adapter
- [ ] Existing Desktop/IDE paths still work unchanged when headless CLI is not available
- [ ] Auth failure produces clear guidance (not a cryptic error)
