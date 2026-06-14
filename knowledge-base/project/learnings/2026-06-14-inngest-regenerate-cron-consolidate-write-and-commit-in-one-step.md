# Learning: a regenerate-from-external-source Inngest cron must keep the file write and the commit in ONE step.run

## Problem

`cron-github-cidr-refresh` (#5284) fetches GitHub `/meta`, runs a shell generator
that rewrites a committed file in a cloned working tree, and on drift opens a
direct-merge PR via `safeCommitAndPr`. The tempting structure — mirroring
`cron-content-vendor-drift`'s separate `detect-drift` and `safe-commit-pr` steps —
is **wrong** for this shape.

Inngest `step.run` memoizes the step's **return value**, NOT filesystem side
effects. The generator's file write is a side effect. If the write happens in
`step.run("detect-drift")` (returning `{drifted: true}`) and the commit happens in
a *separate* `step.run("safe-commit-pr")`, then on a `retries:1` replay that
resumes at the commit step, the memoized `{drifted:true}` returns instantly but
the working tree is **clean** (the write never re-ran) → `safeCommitAndPr` scans,
finds no changes, returns `no-changes`, and posts an OK heartbeat → a **silently
missed refresh** (the exact failure class #5284 exists to kill).

## Solution

Do the fetch + generate + drift-detect + `safeCommitAndPr` **all inside ONE**
`step.run("refresh-cidr")`. The write and the commit are then in the same
execution unit — a crash discards both and re-does both; they can never be
replay-separated. `safeCommitAndPr` is itself replay-idempotent (branch name
derived from a memoized `runStartedAt`; PR-create 422 "already exists" treated as
success), so re-running the whole consolidated step on a mid-step crash is safe.

Why `cron-content-vendor-drift` CAN split: its detect result is a serializable
value (SHAs/labels) that survives memoization, and its working-tree mutation (the
3-way merge) is re-derivable inside the commit step from the clone. A
regenerate-then-commit cron has neither property — the write is the only carrier
of the new content, so it must live with the commit.

## Key Insight

When a cron's "produce" step has a **non-memoized side effect** (a file write, a
local mutation) that the "persist" step consumes, consolidate them into one
`step.run`. Splitting is only safe when the producer's output is fully captured in
the step's serializable return value. Match the precedent's *building blocks*
(`_cron-shared`, `_cron-safe-commit`, heartbeat-on-every-path), not its step
*decomposition* — the decomposition depends on whether the inter-step payload is
memoizable.

## Related

- The new-cron registry lockstep is SIX dimensions, not five — see
  [[2026-06-05-new-inngest-cron-requires-five-registry-lockstep]] (the
  `cron-containment-classify.test.ts` `KNOWN_DIRECT_SPAWN_CRONS` grandfather set
  is the sixth, and fires on any cron that spawns `git`/`bash` directly). This
  cron is `direct-spawn`; the full webplat suite caught the missing entry.

## Session Errors

- **Followed the plan's "five-registry lockstep" framing literally** and did not
  pre-add the `KNOWN_DIRECT_SPAWN_CRONS` entry; the full `vitest run` caught it
  (`cron-containment-classify.test.ts`). Recovery: added the grandfather entry
  with a one-line justification. Prevention: the containment gate is already
  documented as a sixth dimension in the linked learning — read it before adding
  a spawn-based cron; the plan should cite "six-registry" not "five".
- **Generator IPv6-drop test grepped the whole file** (the header source-URL
  contains a `:`) instead of the extracted body → false failure. Recovery:
  asserted against `$ACTUAL_BODY` (comment/blank-stripped). Prevention: when a
  test asserts "no `:` in the CIDR output", scope the grep to the body, never the
  header.
- **First cron tsc failed twice**: `runProc` opts param was required (the `git
  clone` call passed only 2 args) and the env literal omitted `NODE_ENV`
  (Next.js augments `NodeJS.ProcessEnv` with required keys). Recovery: defaulted
  opts to `{}` and added `NODE_ENV`. Prevention: when building a `ProcessEnv`
  literal for `spawn`, include `NODE_ENV`/`PATH`/`HOME` (mirror the vendor-drift
  precedent's env block).
- **cron `.test.ts` failed at import** (`INNGEST_SIGNING_KEY missing`) — the
  registration-smoke test imports the handler which loads the inngest client.
  Recovery: added `vi.hoisted(() => { process.env.NEXT_PHASE =
  "phase-production-build"; })` before the import (the vendor-drift test
  precedent). Prevention: every cron registration-smoke test needs this hoisted
  guard.
- *(forwarded from session-state.md)* IaC-routing PreToolUse hook fired on
  `systemctl` prose in the plan; an initial plan Write landed in the bare-root
  mirror. Both resolved during planning (ack comment + worktree-path rewrite).
  One-off — existing ack mechanism + CWD-verify step already cover these.

## Tags
category: integration-issues
module: apps/web-platform/server/inngest
