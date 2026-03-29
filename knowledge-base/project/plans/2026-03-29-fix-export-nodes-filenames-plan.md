---
title: "fix: export_nodes uses node IDs as filenames instead of node names"
type: fix
date: 2026-03-29
---

# fix: export_nodes uses node IDs as filenames instead of node names

## Overview

When `export_nodes` is called via the pencil MCP adapter, exported files are named after the node ID (e.g., `wZrMw.png`) instead of the human-readable node name (e.g., `Pricing OG Image.png`). This requires a manual rename step after every export, which breaks automated workflows.

## Problem Statement

The pencil CLI's `export_nodes` REPL command names exported files using the internal node ID. The MCP adapter (`pencil-mcp-adapter.mjs`) currently passes the command through to the REPL and returns the raw response without any post-processing. There is no mechanism to use the node's `name` property as the filename.

Discovered during #656 Phase 3 (OG Image via Pencil). Current workaround is manual `mv` after export.

## Proposed Solution

Convert `export_nodes` from a read-only passthrough tool to a custom `server.tool()` handler (same pattern as `get_screenshot` and `set_variables`) that:

1. Calls `batch_get` with the requested `nodeIds` to retrieve each node's `name` property
2. Calls the original `export_nodes` REPL command to produce the exported files
3. Renames each exported file from `<nodeId>.<format>` to `<sanitizedName>.<format>`
4. Falls back to the node ID as filename if the node has no `name` property or `batch_get` fails
5. Returns the response with the final (renamed) file paths

### Filename Sanitization

The node `name` property can contain any characters (spaces, slashes, dots, Unicode). The sanitization function must:

- Replace path separators (`/`, `\`) with hyphens
- Replace other filesystem-unsafe characters (`:`, `*`, `?`, `"`, `<`, `>`, `|`) with hyphens
- Collapse consecutive hyphens into one
- Trim leading/trailing hyphens and whitespace
- Truncate to a reasonable max length (200 chars) to avoid filesystem limits
- Preserve spaces (they are valid in filenames and maintain readability)
- Return the original node ID if sanitization produces an empty string

### Implementation Detail

The key change is in `plugins/soleur/skills/pencil-setup/scripts/pencil-mcp-adapter.mjs`:

1. Remove the `registerReadOnlyTool("export_nodes", ...)` call (lines 498-504)
2. Add a `sanitizeFilename(name)` helper function
3. Add a custom `server.tool("export_nodes", ...)` handler that:
   a. Queries node names via `batch_get({ nodeIds })` through the command queue
   b. Parses the `batch_get` JSON response to build a `nodeId -> name` map
   c. Sends the original `export_nodes(...)` command to the REPL
   d. Renames files using `fs.renameSync` from `<nodeId>.<ext>` to `<sanitizedName>.<ext>`
   e. Updates the response text to reflect renamed filenames
   f. Falls back gracefully if `batch_get` fails or returns no name (uses node ID)

### Handling Duplicate Names

If multiple nodes share the same name (after sanitization), append `-<index>` to avoid overwrites (e.g., `Frame.png`, `Frame-2.png`).

## Acceptance Criteria

- [ ] Exported files use the node's `name` property as the filename (`plugins/soleur/skills/pencil-setup/scripts/pencil-mcp-adapter.mjs`)
- [ ] Filenames are sanitized for filesystem safety (no path separators, no reserved characters)
- [ ] Falls back to node ID if node has no name or `batch_get` fails
- [ ] Duplicate names are disambiguated with a numeric suffix
- [ ] Response text reflects the final (renamed) file paths
- [ ] Existing `export_nodes` MCP tool schema is unchanged (no breaking API change)

## Test Scenarios

- Given a node with `name: "Pricing OG Image"`, when `export_nodes` is called with its ID, then the exported file is named `Pricing OG Image.png` (not `wZrMw.png`)
- Given a node with `name: "hero/banner"`, when `export_nodes` is called, then the exported file is named `hero-banner.png` (slashes sanitized)
- Given a node with `name: "test:::file"`, when `export_nodes` is called, then the exported file is named `test-file.png` (consecutive unsafe chars collapsed)
- Given a node with no name (unnamed), when `export_nodes` is called, then the exported file uses the node ID as filename (fallback)
- Given `batch_get` fails or times out, when `export_nodes` is called, then the exported files use node IDs as filenames (graceful degradation)
- Given two nodes both named "Frame", when `export_nodes` is called with both IDs, then files are named `Frame.png` and `Frame-2.png`
- Given a node with a very long name (200+ chars), when `export_nodes` is called, then the filename is truncated to 200 characters

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- internal tooling bug fix in the pencil MCP adapter.

## Context

- **File to modify:** `plugins/soleur/skills/pencil-setup/scripts/pencil-mcp-adapter.mjs`
- **Pattern to follow:** The `get_screenshot` handler (lines 428-468) and `set_variables` handler (lines 526-566) both use custom `server.tool()` registration instead of the `registerReadOnlyTool` factory, for the same reason -- they need access to parameters and custom post-processing
- **Existing precedent:** The `saveScreenshot` function (lines 103-113) already demonstrates file path manipulation and `writeFileSync` usage in the adapter
- **batch_get response format:** JSON object `{"nodes": [...]}` where each node object includes a `name` property

## References

- Issue: #1116
- Learning: `knowledge-base/project/learnings/2026-03-25-pencil-og-image-design-export-patterns.md`
- Adapter source: `plugins/soleur/skills/pencil-setup/scripts/pencil-mcp-adapter.mjs`
- Prior art (custom tool handler pattern): `get_screenshot` handler at line 428, `set_variables` handler at line 526
