# Tasks: Cloudflare MCP Integration

**Issue:** #254
**Plan:** `knowledge-base/plans/2026-02-22-feat-cloudflare-mcp-integration-plan.md`

## Phase 1: Plugin Configuration and OAuth Validation

- [x] 1.1 Add Cloudflare MCP server entry to `plugins/soleur/.claude-plugin/plugin.json`
- [x] 1.2 Validate OAuth flow for plugin-bundled MCP server
  - Run `/mcp` and verify Cloudflare server appears
  - Confirm OAuth prompt works and tools become available
  - If failed: fall back to `claude mcp add` documentation approach
  - **Gates Phase 2** -- do not start agent rewrite until this passes

## Phase 2: Agent Rewrite and Related Updates

- [x] 2.1 Rewrite infra-security description field (~60 words)
  - Run token budget check after: `shopt -s globstar && grep -h 'description:' agents/**/*.md | wc -w` (target: under 2,500)
- [x] 2.2 Rewrite Environment Setup section (remove env vars, add MCP auth check, add zone discovery)
- [x] 2.3 Rewrite Audit Protocol section (curl -> MCP, keep CLI checks)
- [x] 2.4 Rewrite Configure Protocol section (curl -> MCP, keep confirmation/idempotent patterns)
- [x] 2.5 Update Wire Recipes section (curl -> execute(), keep 10-step ordering and CLI verification)
- [x] 2.6 Update Scope section (expand in-scope, extend inline-only output rule)
- [x] 2.7 Update terraform-architect disambiguation sentence
- [x] 2.8 Update stale learning doc with [Updated 2026-02-22] section

## Workflow Completion

- [x] 3.1 Version bump (MINOR) across plugin.json, CHANGELOG.md, README.md, root README.md, bug_report.yml
