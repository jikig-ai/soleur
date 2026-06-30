# Learning: Inventory existing scoping mechanisms before accepting a "no scoping exists" premise (harness/tool-surface brainstorms) + the two-tier fail-open rule

## Problem

Issue #5768 ("L3 per-phase tool/skill scoping") framed Soleur's harness as having "no
per-phase scoping," with "~92 skills + ~68 agents + MCP loaded simultaneously." Taken at
face value, that premise sizes the work as greenfield: build a phase→tool-scope framework
from scratch. Verification during the brainstorm showed the premise under-credited two
already-shipped, fail-open scoping mechanisms — which narrowed the real residual to a
fraction of the imagined scope.

## Solution

Before accepting an issue-body "X does not exist / everything is loaded at once" premise on
a harness or tool-surface-reduction feature, **inventory what scoping already exists**:

1. **ToolSearch deferred tools.** MCP tool schemas (the heaviest surface — ~100 tools:
   Supabase ~40, Playwright ~30, Pencil ~25) are **already deferred** — names are listed
   but schemas are withheld until fetched on demand. This is a working, inherently
   fail-open L3 reduction at the heaviest surface. Confirm via the session's deferred-tool
   system-reminder.
2. **Change-class rule loader.** `.claude/hooks/session-rules-loader.sh` (#3493) classifies
   the diff (docs/code/infra) and injects only the relevant `AGENTS.{core,docs,rest}.md`
   bodies — fail-open (multi-class/empty → load all). This is the architectural template
   for any phase scoping.

The counts (92 skill dirs via `find plugins/soleur/skills -name SKILL.md`; 68 agents) were
accurate — but "loaded simultaneously / no scoping" was not. The genuine residual: the **92
always-loaded skill descriptions** (the Claude Code runtime, not Soleur, owns the menu — a
hook can only *hint*, never un-advertise a skill) + the **absence of a phase signal**.

## Key Insight

A correct *count* in an issue body does not validate the *framing* built on it. "N things
exist" ≠ "N things are unscoped." For harness/tool-surface work, the verification target is
the **scoping layers already in place** (ToolSearch defer, change-class loader,
progressive-disclosure skill bodies, the web `canUseTool` floor), not just the inventory
size. Inventorying them first usually shrinks the work and reveals the real gap.

### Corollary: the two-tier fail-open rule

When scoping a tool surface, **deny-by-default is safe only on an already-fail-open layer**
(MCP/ToolSearch re-fetches schemas on demand, so withholding by default cannot strip a
needed tool). On every other layer the scoping must be **additive-hint only**:

- **Built-in tools + the ~20 PreToolUse safety hooks (CLI):** a hard deny can route an agent
  *around* the very safety hook that would have caught it (`prod-write-defer-gate`,
  `git-commit-secret-scan`). Hint, never deny.
- **Web SDK `canUseTool` (agent-runner):** a deny (or simply not loading a tool the model
  then reaches for) produces a silent "unknown tool" error to a paying user — see
  `2026-05-13-claude-agent-sdk-canusetool-not-invoked-for-unknown-mcp-tools.md`. Phase
  scoping must stay a prompt-level hint + a high-confidence never-needed subset, with the
  full set restored on any classifier ambiguity. The `canUseTool` deny-by-default stays the
  *security* floor only — never a *feature*-phase gate.

Any phase-classifier ambiguity → full surface (mirror the loader's multi-class/empty →
load-all branch).

## Tags
category: workflow-patterns
module: brainstorm, harness, hooks, agent-sdk

## Cross-References
- Brainstorm: `knowledge-base/project/brainstorms/2026-06-30-harness-l3-phase-tool-scoping-brainstorm.md`
- Spec: `knowledge-base/project/specs/feat-harness-l3-phase-tool-scoping/spec.md`
- [GitHub #5768](https://github.com/jikig-ai/soleur/issues/5768) · PR #5769
- Sibling harness gaps: #5765 (L1), #5766/#5767 (L5)
- `2026-05-13-claude-agent-sdk-canusetool-not-invoked-for-unknown-mcp-tools.md` — the web silent-fail mode
- `2026-04-06-mcp-tool-canusertool-scope-allowlist.md` — `canUseTool` deny-by-default as security floor
- `2026-03-25-check-mcp-api-before-playwright.md` — tool-surface size is a real cost/quality lever

## Session Errors
- **Scratchpad write failed once (`No such file or directory`)** — the session scratchpad
  dir was not pre-created before the first write. Recovery: `mkdir -p` then re-run.
  **Prevention:** one-off; `mkdir -p <scratchpad>` is the standing idiom before writing
  there. No rule/hook change warranted.
