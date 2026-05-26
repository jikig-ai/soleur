---
issue: 2724
parent_issue: 2718
status: deferred
lane: cross-domain
brand_survival_threshold: single-user incident
---

# Spec: mcp-server-builder (deferred)

**Status: Deferred.** No implementation planned. See brainstorm for full rationale:

- `knowledge-base/project/brainstorms/2026-05-12-mcp-server-builder-brainstorm.md`

## Decision Summary

Four-leader brainstorm (CPO, CMO, CTO, CLO) on 2026-05-12 concluded defer. No founder outcome named; off-axis from CaaS-for-founders positioning; cannibalizes #2718 "no wholesale port" reject decision; deliverable shape (static-bearer MCP servers) is not bundle-compatible with `plugin.json`.

## Reopen Criteria

See the brainstorm's `## Reopen Criteria` section. Summary:

1. A Phase 3/4 roadmap vendor requires integration and has no published MCP server.
2. A founder ICP interview names this gap and upstream MIT alternative does not solve it.
3. Claude Code plugin runtime gains support for headers in `plugin.json` MCP entries.

Absent any of these, this spec stays in `status: deferred` and #2724 stays closed.
