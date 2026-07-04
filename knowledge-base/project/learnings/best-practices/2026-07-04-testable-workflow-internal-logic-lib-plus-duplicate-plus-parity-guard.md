---
title: "Deterministic no-live-agent tests of Workflow-internal logic: importable lib + self-contained duplicate + logic-parity drift guard"
date: 2026-07-04
category: best-practices
module: plugins/soleur/skills/*/workflows
tags: [workflow-tool, testing, self-contained-duplication, drift-guard, plan-review]
pr: 6020
issue: 5985
---

# Learning: Unit-testing decision logic that lives inside a `.workflow.js`

## Problem

`#5985` wired a relevance-gated named panel into `plan-review`, gated by a pure
decision function `computeNamedPanel(signals) → lenses`. Two acceptance criteria
(AC11 independent-activation, AC12 each-lens-exercised) required **deterministic
fixture tests with NO live agents**. But a Workflow-tool script
(`skills/*/workflows/*.workflow.js`) cannot be unit-tested by import:

- It runs `export const meta` + top-level `await agent(...)` / `return report`,
  so `await import("…workflow.js")` executes the body immediately → throws
  (`requires a plan file path`) or hits `return` at module top level.
- The Workflow runtime has **no filesystem/import access**, so the workflow
  cannot itself `import` a shared helper (this is the documented reason
  `safeTitle`/`safeId` are duplicated per script).

So the logic that actually runs is unreachable from `bun test`.

## Solution

Three-part pattern (all three are load-bearing):

1. **Extract the pure decision function into an importable ESM module** —
   `skills/plan-review/lib/named-panel.mjs` exporting `computeNamedPanel` +
   `NAMED_LENSES`. This is the copy the AC11/AC12 fixtures import and exercise.
2. **Duplicate it verbatim into the `.workflow.js`** (self-contained convention
   — the runtime can't import). This is the copy that actually runs.
3. **Add a normalized logic-parity drift guard** — a test that extracts
   `NAMED_LENSES = […]` and `function computeNamedPanel(…){…}` from BOTH source
   files, strips comments/`export`/whitespace, and asserts the two bodies are
   equal. Without it, a logic edit to the runtime copy passes CI while the tested
   copy silently diverges (the copy that runs ≠ the copy that is tested).

Keep design decisions that are ambiguous or fuzzy OUT of the pure function so it
stays deterministic: the plan's "threshold bias" (Step 3) was wired at the
**detect-prompt** layer (nudging the model's fuzzy signals) rather than inside
`computeNamedPanel`, so the function remains a pure signals→lenses mapping and
the fixtures stay deterministic.

## Key Insight

When a Workflow script contains decision logic that deserves a unit test, the
testable unit is a **pure function of the agent-returned signals**, extracted to
an importable module, duplicated into the (un-importable) workflow, and pinned by
a **logic-parity** guard — not a mere presence grep. A `src.toContain("function
foo(")` guard proves the function exists, not that the running copy matches the
tested copy; normalize-and-compare both bodies.

## Syntax-checking a `.workflow.js`

`node --check path.workflow.js` reports a false-positive `Illegal return
statement` because the top-level `return report` is legal only inside the
Workflow runtime's async wrapper. To validate edits, wrap the body first:

```bash
node -e 'const fs=require("fs");let s=fs.readFileSync(F,"utf8").replace(/^export const meta/,"const meta");
new Function("async function __wf(args,agent,parallel,pipeline,log,phase,budget,workflow){\n"+s+"\n}");'
```

## Session Errors

1. **Planning subagent returned a garbled mid-stream snippet instead of its
   `## Session Summary` block.** Recovery: read the on-disk plan artifact
   (`plans/*.md`) directly and verify completeness. Prevention: one-shot's
   partial-artifact recovery path already handles this — trust the on-disk
   artifact over the subagent's return text. One-off.
2. **Two review subagents' first `Read` calls hit the main-repo path (checked
   out to `main`) instead of the worktree, returning stale pre-PR content.**
   Recovery: the agents re-ran in the worktree cwd (grep/awk) and reported true
   diff. Prevention: already documented in
   `2026-05-19-bare-repo-grep-and-subagent-infra-claim-verification.md`; pass
   worktree-absolute paths to review subagents. Recurring, already-covered.
3. **`node --check` false-positive on the `.workflow.js` top-level `return`.**
   Recovery: wrapped-async `new Function(...)` syntax check (above). Prevention:
   this learning + the plugins AGENTS.md workflow-script note. Recurring, low-value.
