# Learning: A path-rename sweep must exclude the feature's OWN planning artifacts

## Problem

The `feat-one-shot-consolidate-engineering-ops-into-operations` refactor moved
`knowledge-base/engineering/ops/` → `engineering/operations/` (`git mv` + a
boundary-anchored sed sweep of the literal path across all non-archive files).

The plan's acceptance criteria were internally contradictory:

- **AC4** asserted the residual gate `git grep "engineering/ops" | grep -v
  operations | grep -v /archive/` returns **0**.
- **AC5** asserted the plan file *intentionally* still contains `engineering/ops`
  (its Research Reconciliation table documents the before-state).

These cannot both hold unless the feature's own artifacts are excluded from BOTH
the sweep and the residual gate. Worse, the Phase 2 sweep file-list excluded only
`**/archive/**` — it did NOT exclude the feature's own `plan.md` (42 refs),
`tasks.md` (14 refs), or `session-state.md` (2 refs). Running the sweep verbatim
would have rewritten the plan's own title to "consolidate engineering/**operations**
into engineering/operations" and turned `tasks.md`'s literal command
`rmdir knowledge-base/engineering/ops` into a no-op nonsense line — corrupting the
migration record.

## Solution

Treat the feature's OWN planning artifacts exactly like `**/archive/**`: they are
point-in-time migration records that MUST cite the old path. Exclude all three
(`plans/<this-plan>.md`, `specs/feat-<branch>/tasks.md`,
`specs/feat-<branch>/session-state.md`) from:

1. the Phase 2 sweep file-list, AND
2. the Phase 5 / AC4 residual gate (extend the `grep -vE` to match the
   feature's plan + spec dir, alongside the existing `/archive/` filter).

Post-sweep verification then cleanly returns 0 residual references in all LIVE
files while the migration's own record stays coherent. The four review agents
(git-history, pattern-recognition, security-sentinel, code-quality) all
independently confirmed the exclusion set was correct and complete.

## Key Insight

When a refactor renames a path and sweeps every reference, the sweep's own
planning artifacts are a third immutable bucket alongside `archive/`. AC5-style
"the plan intentionally keeps the old path" carve-outs are incomplete if they
name only `plan.md` — `tasks.md` and `session-state.md` describe the same
migration and break identically. Generalize the carve-out to the whole
`specs/feat-<branch>/` dir + the plan file, and make the residual gate exclude
the same set so AC4 and AC5 are consistent by construction.

Corollary (substring-safety): `ops` is NOT a substring of `operations`
(`op`+`erations`), so a naive global replace cannot corrupt already-migrated
refs. The boundary-anchored form `s#engineering/ops(/|[^a-z]|$)#…\1#g` is still
preferred as defense-in-depth and to skip lone prose tokens like `engineering/ops)`.

## Session Errors

1. **Task tool unavailable inside the planning subagent** — Recovery: one-shot's
   plan subagent ran research via Bash/Read; DHH/Kieran/code-simplicity
   plan-reviewers did not spawn. Prevention: known limitation
   ([[2026-05-12-task-subagent-prompt-text-only]]); for mechanical refactors,
   parent-level multi-agent code review (which DID run, 4 agents) is sufficient
   coverage.
2. **Bash-tool CWD persisted across calls** — a `cd apps/web-platform && vitest`
   left CWD at `apps/web-platform`, so a later `git add knowledge-base/...`
   resolved against the wrong root and failed `pathspec did not match`.
   Recovery: re-ran with an explicit `cd <worktree-root> &&` prefix. Prevention:
   in multi-step pipeline bash, always prefix the worktree-root `cd` when the
   prior call may have changed directory.
3. **Plan AC4/AC5 internal contradiction (design gap)** — caught at work-time
   before sweeping; see Problem/Solution above. Prevention: the routing edit
   below adds the rule to the plan skill so future rename plans pre-specify the
   own-artifact exclusion.

## Tags
category: best-practices
module: refactor / knowledge-base path migration
