---
title: "Pencil adapter: converting read-only tools to custom handlers for post-processing"
date: 2026-03-29
category: integration-issues
tags: [pencil, mcp-adapter, file-rename, sanitization]
module: plugins/soleur/skills/pencil-setup/scripts/pencil-mcp-adapter.mjs
---

# Learning: Pencil adapter export_nodes rename pattern

## Problem

The pencil MCP adapter's `export_nodes` tool was registered via `registerReadOnlyTool`, which passes commands straight through to the REPL. Exported files were named by node ID (e.g., `wZrMw.png`) instead of the human-readable node name (e.g., `Pricing OG Image.png`), requiring a manual `mv` after every export.

## Solution

Converted `export_nodes` from `registerReadOnlyTool` to a custom `server.tool()` handler (same pattern as `get_screenshot` and `set_variables`). The handler:

1. Calls `batch_get({ nodeIds })` to retrieve node names
2. Runs the original `export_nodes` REPL command
3. Renames files from `<nodeId>.<ext>` to `<sanitizedName>.<ext>` using `fs.renameSync`
4. Falls back to node ID if `batch_get` fails or name is empty

Filename sanitization was extracted to a standalone module (`sanitize-filename.mjs`) for testability.

## Key Insight

The pencil adapter has two tool registration patterns: `registerReadOnlyTool`/`registerMutatingTool` (factory) for simple passthrough, and custom `server.tool()` for handlers that need pre/post-processing. When a tool needs to correlate data across REPL calls (e.g., batch_get names + export_nodes files), the custom handler pattern is required. The `get_screenshot` handler (base64 parsing + disk save) and `set_variables` handler (value coercion) are the reference implementations.

## Tags

category: integration-issues
module: plugins/soleur/skills/pencil-setup/scripts/pencil-mcp-adapter.mjs
