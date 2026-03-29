# Tasks: fix export_nodes filenames

## Phase 1: Setup

- [ ] 1.1 Read `plugins/soleur/skills/pencil-setup/scripts/pencil-mcp-adapter.mjs` to confirm current state

## Phase 2: Core Implementation

- [ ] 2.1 Add `sanitizeFilename(name)` helper function after the existing `saveScreenshot` function (~line 113)
  - [ ] 2.1.1 Replace `/`, `\`, `:`, `*`, `?`, `"`, `<`, `>`, `|` with hyphens
  - [ ] 2.1.2 Collapse consecutive hyphens
  - [ ] 2.1.3 Trim leading/trailing hyphens and whitespace
  - [ ] 2.1.4 Truncate to 200 characters
  - [ ] 2.1.5 Return empty string if result is empty (caller handles fallback)
- [ ] 2.2 Remove `registerReadOnlyTool("export_nodes", ...)` call (lines 498-504)
- [ ] 2.3 Add custom `server.tool("export_nodes", ...)` handler with:
  - [ ] 2.3.1 Same Zod schema as the removed registration
  - [ ] 2.3.2 Call `batch_get({ nodeIds })` via command queue to retrieve node names
  - [ ] 2.3.3 Parse batch_get JSON response into `nodeId -> name` map
  - [ ] 2.3.4 Send original `export_nodes(...)` command to REPL
  - [ ] 2.3.5 Rename exported files from `<nodeId>.<ext>` to `<sanitizedName>.<ext>` using `fs.renameSync`
  - [ ] 2.3.6 Append summary line to response listing final filenames
  - [ ] 2.3.8 Wrap `batch_get` and rename in try/catch -- fall back to node IDs on any failure

## Phase 3: Testing

- [ ] 3.1 Verify `sanitizeFilename` handles edge cases: slashes, colons, long names, empty names, Unicode
- [ ] 3.2 Verify export_nodes MCP tool schema is unchanged (no breaking API change)
- [ ] 3.3 Manual test with pencil MCP if available: create a named frame, export, verify filename
