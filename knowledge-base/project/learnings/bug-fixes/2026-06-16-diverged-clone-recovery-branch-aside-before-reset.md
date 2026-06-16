---
title: "A `.git`-absent self-heal does not cover a `.git`-present-but-diverged clone — recover with branch-aside-before-reset"
date: 2026-06-16
category: bug-fixes
tags: [concierge, kb-sync, self-heal, git, workspace, recovery, durability]
module: apps/web-platform/server/workspace-sync.ts
closes: 5425
pr: 5423
---

# Diverged-clone recovery: branch-aside before reset (the gap a `.git`-absent re-clone self-heal misses)

## Problem

Production Sentry (2026-06-16): `Error: self-heal aborted: un-pushed local commits present` at
`POST /api/kb/sync`, `op:self-heal-aborted-dirty`. A connected Concierge workspace was **permanently
dead-ended**: every kb/sync re-fired the abort, **Reconnect did nothing**, and the dispatch readiness
gate reported "workspace isn't ready". This persisted AFTER the concierge reconnect/self-heal fix merged
the same day (release `3c8849655`, PRs #5409/#5413/#5415).

## Root cause — two recovery paths both refuse to act on a clone that EXISTS but has diverged

1. `selfHealNonFastForward()` aborted the `reset --hard` whenever `git rev-list --count @{u}..HEAD > 0`
   (to protect agent work) — so nothing ever cleared the divergence.
2. The re-clone paths (`repo-readiness-self-heal.ts`, `ensure-workspace-repo.ts`) and Reconnect are
   `.git`-**absent** gated. Reconnect's `use-reconnect.ts → attemptResetup` additionally only fires
   `/api/repo/setup` when `repo_status !== "ready"` — and a diverged clone (the clone *succeeded*; only
   the sync diverged) stays `"ready"`, so Reconnect short-circuits to a no-op. (Note: `/api/repo/setup`
   itself does an unconditional `rm -rf` + clone — so "fixing" Reconnect to re-clone would have
   **destroyed** the very un-pushed commits we must preserve. Wrong layer.)

The trigger: `session-sync.ts` auto-commits `knowledge-base/**` onto the checked-out **default branch**,
then a bare `git push`. A protected-branch push rejection strands the commit as an un-pushable orphan,
trapping kb/sync forever.

## Solution — branch-aside BEFORE reset (provably non-destructive)

In `selfHealNonFastForward`, on `localCommits > 0`, read `git rev-parse --abbrev-ref HEAD` and branch by HEAD:

- **HEAD == default branch** → un-pushable auto-sync orphans: `git branch soleur/recovered-kb-sync-<Date.now()> HEAD`
  (preserve on a durable gc-root ref) **then** `git reset --hard origin/<default>` → `{ok:true, recovered:true}`,
  `op:self-heal-recovered-diverged` (WARN, queryable recovery rate).
- **HEAD == a feature branch** → genuine agent work → keep aborting (`op:self-heal-aborted-dirty`).
- **HEAD == "HEAD" (detached)** → distinct `op:self-heal-aborted-detached-head` (never silently bucketed).
- **rev-list NaN (un-countable)** → fail safe, abort.

## Key insights

1. **A `.git`-absent re-clone self-heal and a `.git`-present diverged clone are disjoint failure states.**
   When you ship a "re-clone the missing checkout" fix, ask: what about a checkout that *exists* but is
   wrong? The two need separate recovery paths.
2. **Branch-aside-before-reset is the non-destructive primitive.** `git branch <name> HEAD` makes the
   commit objects reachable from a named ref (a gc-root, even in a `--depth 1` shallow clone) BEFORE
   `reset --hard` moves the default ref. The reset then discards nothing. This is how you relax an
   "abort to protect work" guard without losing work — add a preservation primitive, don't just delete
   the check. Honors the 2026-06-03 "do-nothing-when-uncertain" learnings: the default-branch case is
   now *provably* safe, so it's no longer uncertain; the genuinely-uncertain cases still abort.
3. **`git rev-parse --abbrev-ref HEAD` returns the literal `"HEAD"` when detached** — handle it as a
   distinct, observable abort, never let it fall into the feature- or default-branch arm.
4. **Recover downstream vs. fix the trigger.** Recovering in kb/sync heals already-trapped production
   clones (the live incident) with a minimal, low-risk change; the trigger fix (stop auto-committing
   onto a protected default branch) is a separate session-sync-contract change. Deferred to #5426.

## Session Errors

1. **`gh issue create` blocked by the `--milestone` hook, taking its inline heredoc body down with it.**
   Recovery: write the body with the Write tool first, then `gh issue create --body-file ... --milestone`.
   Prevention: already hook-enforced + documented — never heredoc an issue body in the same Bash call as
   a milestone-gated `gh issue create`.
2. **Background vitest's real EXIT code landed in the task's own output file, not the redirected log;**
   the log's top `MODULE_NOT_FOUND` + GitHub-404 lines were deliberate test fixtures, not a crash.
   Recovery: read the background task output file for `EXIT=` and the `Test Files`/`Tests` summary.
   Prevention (one-off): when backgrounding `cmd > log 2>&1; echo EXIT=$?`, the EXIT echo goes to the
   task output, not the log — read both.
3. **Plan-file "modified on disk since last read"** from concurrent `perl` checkbox edits + an Edit;
   applied cleanly. One-off.
