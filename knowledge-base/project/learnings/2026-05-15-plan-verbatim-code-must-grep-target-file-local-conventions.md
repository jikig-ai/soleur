# Learning: Plan-prescribed verbatim code must grep target file's local conventions

## Problem

PR #3839 (API-budget operator preamble backport) shipped a new test block in
`plugins/soleur/test/components.test.ts` that the multi-agent review (3 of 4
agents — pattern-recognition-specialist, user-impact-reviewer,
code-simplicity-reviewer) flagged as inconsistent with the file's local
path-resolution convention:

- **Prescribed (plan §10):** `` const skillPath = `plugins/soleur/skills/${skillName}/SKILL.md` ``
- **Local convention (helpers.ts:6, exported):** `const PLUGIN_ROOT = resolve(import.meta.dir, "..")`
- **All sibling describe blocks** in the same file resolve through `PLUGIN_ROOT`,
  decoupling from `process.cwd()`. The new block used a bare relative path that
  fail-opens with ENOENT if `bun test` is invoked from any non-repo-root cwd
  (e.g., `cd plugins/soleur && bun test test/components.test.ts`).

User-impact-reviewer escalated: the disclosure-presence gate is the
brand-survival mechanism preventing surprise Anthropic invoices; a
path-resolution flake that hides a real disclosure regression *is* the
brand-survival event.

## Root Cause

The plan supplied verbatim TypeScript code for a new block to insert into an
existing test file. /work executed the plan-prescribed code without grepping
`components.test.ts` for the file's local path-resolution helpers — even though
those helpers (`PLUGIN_ROOT`, `discoverSkills`, `parseComponent`) were
already imported at the top of the same file.

The plan's "verbatim code" framing made the snippet feel authoritative. The
work skill's existing "Follow Existing Patterns" gate is qualitative; it does
not mechanically require a target-file-helper grep when a plan supplies code.

## Solution

Inline fix at commit `952e7a40`:

```diff
+import { resolve } from "node:path";
+import { PLUGIN_ROOT } from "./helpers";
-const skillPath = `plugins/soleur/skills/${skillName}/SKILL.md`;
+const skillPath = resolve(PLUGIN_ROOT, "skills", skillName, "SKILL.md");
```

`PLUGIN_ROOT` was already exported by `helpers.ts:53` for exactly this purpose.

## Key Insight

A plan that prescribes **verbatim code** for an **existing file** must include a
"local-conventions audit" in its drafting step: grep the target file for
existing imports, helper exports, path-resolution patterns, and fixture-loading
patterns. The verbatim snippet must adopt those patterns.

Two failure shapes this catches:

1. **Path resolution drift** (this incident) — bare relative paths vs. anchored
   `resolve(import.meta.dir, ...)` helpers.
2. **Mock chain drift** — extending a Supabase wrapper with a new chained method
   (`.eq`, `.in`, `.maybeSingle`) without extending every sibling
   `vi.mock("@supabase/supabase-js", ...)` setup in the same edit cycle.
   `tsc` is silent on chain-shape drift.

Both are caught by the same mechanical step: **before writing verbatim code,
read the target file's top-level imports and exported helpers, and confirm the
new code uses the same primitives.**

## Prevention

For plan authors:

- When drafting a snippet that inserts into an existing TS/JS file, grep that
  file's first ~30 lines for imports and resolve helpers. If a path-resolution
  helper (`PLUGIN_ROOT`, `__dirname` equivalent, `path.join(__dirname, ...)`)
  exists, use it. Do not write bare relative paths.

For /work:

- The existing "Follow Existing Patterns" gate covers this in spirit. No new
  hard rule needed — the failure mode is **plan-authoring**, not /work
  execution. The multi-agent review caught it, so the safety net worked.

For /review prompts:

- The pattern-recognition-specialist's review prompt naturally surfaces
  "consistency with file-local conventions" — verified working here.

## Session Errors

**Plan precondition drift on rule body byte count** — Plan claimed
`hr-autonomous-loop-skill-api-budget-disclosure`'s body was ~536 bytes; actual
was 741 bytes (over 600-byte per-rule cap). Required trim mid-implementation.
**Recovery:** trimmed to 446 bytes.
**Prevention:** plan-author byte probes must hash the exact prose written into
the plan. Already covered by `hr-when-a-plan-specifies-relative-paths-e-g`
cousin "plan-quoted numbers are preconditions to verify, not facts" in the
/work skill's Phase 1 step 1 — same failure class as PR #3501.

**Verbatim-code plan didn't grep target file local conventions** —
Plan §10 prescribed `plugins/soleur/skills/${skillName}/SKILL.md` (relative
to `process.cwd()`) for the new test's `readFileSync`. Sibling tests use
`PLUGIN_ROOT`. **Recovery:** review caught it; fixed inline at commit
`952e7a40`.
**Prevention:** see Key Insight above. Plan-authoring step, not /work — the
review safety net worked.

## Tags

category: best-practices
module: plan-authoring, work-execution
related-issues: [#3819, #3501]
related-prs: [#3839, #3809]
