---
title: "A fail-loud guard for state-class X must not nest under a gate that exists only for state-class Y"
date: 2026-07-02
category: best-practices
module: git-worktree
tags: [set-e, bash, fail-loud, work-phase, plan-literalism, review-convergence]
related_prs: [5907]
related_learnings:
  - knowledge-base/project/learnings/workflow-patterns/2026-07-02-merged-is-not-deployed-on-concierge-instrument-dont-ask.md
---

# Learning: fail-loud guard for one state class must not nest under a different state class's gate

## Problem

Instrumenting `sweep_stale_git_locks()` (worktree-manager.sh) to fail loud on an
unremovable `config.lock`, the deepen-plan structured the act-block as:

```bash
if (( age >= threshold )); then          # staleness gate
  if regular; then rm ...                # in-flight-writer safety
  else unremovable=1; echo UNREMOVABLE   # <-- non-regular emit nested here
  fi
fi
```

The staleness gate exists for ONE reason: a legitimate in-flight git writer holds
a **regular** `config.lock` for single-digit ms, so removing a fresh regular lock
would clobber it. But the non-regular `UNREMOVABLE` emit was nested under the same
gate — so a *fresh* directory/symlink `config.lock` (age < threshold) emitted only
its DIAG line, left `unremovable=0`, and `ensure_bare_config` marched straight into
the doomed `git config` write (EEXIST) — the exact outcome the fail-loud contract
exists to prevent. A `config.lock` is never legitimately non-regular (git creates
it via `open(O_CREAT|O_EXCL)`), so the in-flight-writer rationale never applied to
the non-regular branch.

## Solution

Split the two state classes so each gets only the gate it needs:

```bash
if regular; then
  if (( age >= threshold )); then rm ... ; fi   # staleness gate scoped to regular
else
  unremovable=1; echo UNREMOVABLE               # non-regular: flagged unconditionally
fi
```

## Key Insight

Two failures compounded, and the second is the transferable one:

1. **A fail-loud/short-circuit guard whose intent is "never proceed on ANY observed
   instance of bad-state X" must not be nested under a precondition that only holds
   for a DIFFERENT state class.** Here the staleness gate is a *regular-lock*
   concern; nesting the *non-regular* emit under it silently narrowed "never march
   into the doomed write" to "never march in *once the bad state is also stale*."
   When you place a guard, ask: does the enclosing condition belong to the SAME
   state class the guard protects, or did I inherit it from an adjacent branch?

2. **When you notice during `/work` that the plan's literal structure undercuts the
   plan's own stated GOAL, fix it inline — do not implement literally and defer to
   review.** I saw this gap while writing the code and followed the plan's placement
   anyway; three independent review agents (silent-failure-hunter, pattern-
   recognition, code-quality) then converged on it. The plan is authoritative for
   *intent* (here: "never march into the doomed git config write"), never for the
   exact control-flow placement that realizes it (same class as
   `hr-when-a-plan-specifies-relative-paths-e-g`). A self-noticed goal-vs-structure
   gap is the cheapest possible fix at write-time and the most wasteful one to
   round-trip through review.

Corollary caught in the same review: `_rm_errno` mapped GNU `rm` strerror TEXT, so
a non-C locale degraded every errno to `OTHER` — pin `LC_ALL=C` on any capture whose
value is a strerror-text match.

## Session Errors

- **Self-noticed design gap implemented-as-planned, caught by review.** The
  non-regular `UNREMOVABLE` emit was nested under the staleness gate per the plan's
  literal structure; a fresh non-regular lock slipped the fail-loud contract.
  Recovery: restructured so non-regular locks flag `unremovable=1` regardless of
  age; added Test 4b. **Prevention:** during `/work`, when a plan's literal
  control-flow placement undercuts the plan's stated goal, fix inline at write-time
  (route only genuine *architecture* forks to the CTO agent; a ≤10-line correctness
  fix is not a fork).
- **`TEST_GROUP=scripts` shard exceeded the 2-min foreground Bash timeout (twice).**
  Recovery: re-ran with `run_in_background: true` and appended `SHARD_EXIT=$?` to the
  log for authoritative exit capture. **Prevention:** run the full scripts shard
  (133 suites, >2min) in the background from the start; never rely on the foreground
  Bash timeout for it. One-off/known-constraint, already standard practice.
