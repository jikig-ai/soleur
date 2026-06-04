# Deferred capability — Concierge autonomous write for LikeC4 diagrams

**Status:** Deferred (follow-up to the LikeC4 visualizer feature, branch `feat-likec4-visualizer`)
**Date:** 2026-06-03

## What shipped

The LikeC4 C4-model visualizer replaces static Mermaid C4 in the KB viewer:
interactive drill-down diagrams + an in-browser `.c4` code editor. The single
write path is `server/c4-writer.ts` (`writeC4Diagram`, scoped to
`engineering/architecture/diagrams/` via `isC4DiagramPath`), exposed over HTTP at
`PUT /api/kb/c4/[...path]` and used by the editor's **Save** button.

The Soleur Concierge can already **read** the canonical `.c4` sources (they are
inlined into its system prompt by `server/kb-document-resolver.ts` when a diagram
page is open) and **propose** edited DSL in conversation. The user applies a
proposal with one click via the Code-tab **Save** — a complete
"concierge-conversation-edits-the-diagram" loop with human-in-the-loop review.

## What was deferred and why

An *autonomous* Concierge write — i.e. the agent calling a
`mcp__soleur_platform__edit_c4_diagram` tool that invokes `writeC4Diagram`
directly, with no human apply step — was deferred.

Rationale:

- The cc-router MCP surface (`server/cc-dispatcher.ts`) is **deliberately
  Phase-1 scaffolded**: `readCcMcpAllowlist()` returns `{}` and tool promotion
  is explicitly staged as Phase 2 (#3722), behind a tier-classification +
  cross-tenant denylist model with ~12 dedicated invariant tests
  (`cc-mcp-tier-allowlist.test.ts`, `canusertool-tiered-gating.test.ts`, …).
- Generic `Edit`/`Write` are hard-blocked for the Concierge by design
  (`CC_PATH_DISALLOWED_TOOLS`). Granting a write tool ad-hoc, outside the
  Phase-2 promotion path, would bypass that governance.
- The user-approved write mechanism for this feature was the **dedicated KB
  write endpoint** (delivered), not a lifted tool allowlist.

## How to pick it up (Phase 2)

1. Add `edit_c4_diagram` as a registered platform tool via the #3722 promotion
   path (tier classification + `CC_MCP_ALLOWLIST` / `CC_REGISTERED_PLATFORM_TOOL_NAMES`).
2. Build an `createSdkMcpServer({ name: "soleur_platform", tools: [tool("edit_c4_diagram", …)] })`
   whose handler closes over the dispatch user's GitHub context (resolve
   owner/repo/installation alongside `fetchUserWorkspacePath`) and calls the
   existing `writeC4Diagram`.
3. Gate availability behind the `c4-visualizer` runtime flag so it is off by
   default and only active for targeted identities.
4. Approve it through `canUseTool` (scoped) — the `isC4DiagramPath` guard in
   `writeC4Diagram` already constrains the blast radius to the diagrams dir.
