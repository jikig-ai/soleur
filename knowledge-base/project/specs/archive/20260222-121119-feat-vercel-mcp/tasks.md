# Tasks: Integrate Vercel MCP

**Issue:** #258
**Plan:** `knowledge-base/plans/2026-02-22-feat-integrate-vercel-mcp-plan.md`

## Phase 1: Core Implementation

### 1.1 Add Vercel MCP entry to plugin.json

- Add `vercel` key to `mcpServers` in `plugins/soleur/.claude-plugin/plugin.json`
- Set `type: "http"` and `url: "https://mcp.vercel.com"`
- Update `description` field to reflect 2 MCP servers instead of 1

### 1.2 Update README.md MCP Servers section

- Add Vercel row to MCP Servers table
- Add Vercel subsection with tool list (grouped by category)
- Update Known Issues section to include Vercel MCP workaround
- Update component counts table (MCP Servers: 1 -> 2)

### 1.3 Update CHANGELOG.md

- Add `## [2.32.0] - 2026-02-22` section with `### Added` entry

## Phase 2: Version Bump

### 2.1 Bump version across all locations

- `plugins/soleur/.claude-plugin/plugin.json` version: 2.32.0
- `README.md` (root) version badge: 2.32.0
- `.github/ISSUE_TEMPLATE/bug_report.yml` placeholder: 2.32.0

## Phase 3: Verification

### 3.1 Verify all version locations match

- Grep for old version (2.31.5) to ensure no stale references
- Verify plugin.json is valid JSON
- Verify CHANGELOG follows Keep a Changelog format
