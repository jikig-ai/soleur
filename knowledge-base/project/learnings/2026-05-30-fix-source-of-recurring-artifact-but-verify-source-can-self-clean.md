---
title: "Fix the source of a recurring artifact — but verify the source CAN self-clean (async fire-and-forget creators need a reactive event handler, not a per-creator patch)"
date: 2026-05-30
category: workflow-patterns
tags: [git-branches, ci, inngest, github-actions, cleanup-design, source-vs-symptom, blast-radius, bare-repo-staleness, config-coverage-subset]
related_prs: ["#4651"]
---

# Learning: fix the source of a recurring artifact — but first verify the source CAN self-clean

## Problem

A triage of ~72 cleanup-eligible stale remote branches raised the natural
question (the operator's, correctly pushing past my first idea of a cron
"janitor"): **"shall we fix the jobs creating those branches to clean up after
themselves?"** — fix the source, not the symptom.

That instinct is right, but it gets misapplied as **"patch every producer."**
Here the producers are 7 Inngest cron functions (`cron-content-generator`,
`cron-growth-audit`, `cron-community-monitor`, `cron-campaign-calendar`,
`cron-content-publisher`, `cron-weekly-analytics`, `cron-growth-execution`)
plus the `rule-metrics-aggregate` GHA. **All eight persist branches via the
same async pattern:**

```
git push origin "$BRANCH" && gh pr create ... && gh pr merge --squash --auto
```

`gh pr merge --auto` resolves **later**, when checks pass — the creating run
has already exited. So the creator **physically cannot** clean up a branch
whose PR is eventually *closed without merging*: by the time the close event
exists, the run that could act is long gone. "Make each job clean up after
itself" is unbuildable for this path.

## Root Cause

Two separate misconceptions compounded:

1. **"Patch every producer" is the wrong shape of source-fix for async
   creators.** When N producers emit an artifact through a fire-and-forget /
   detached path, the cleanup-triggering *state* (PR closed unmerged) comes
   into existence after every producer run has exited. The knowledge of "this
   branch should now be deleted" lives at the **leak event**, not in any
   producer. The source-aligned fix is therefore a **single reactive handler
   on that event**, which is automatically source-agnostic across all N
   producers (and across local-agent branches too).

2. **"We already have setting X" hid the actual leak.** The repo sets
   `delete_branch_on_merge: true`, which *sounds like* "branches self-clean."
   It does — but **only for the MERGE transition.** GitHub never auto-deletes a
   head branch when a PR is **closed without merging**. That one uncovered
   sibling transition was the entire source of the 30+ leaked branches.

## Solution

Shipped **one** reactive workflow (PR #4651,
`.github/workflows/cleanup-unmerged-bot-branches.yml`):

```yaml
on:
  pull_request:
    types: [closed]
```

It fires on the exact event that leaks (a bot-prefixed PR closing unmerged),
deletes the head ref via `gh api -X DELETE`, and deletes **nothing on a
schedule**. It is source-agnostic: one handler covers all 8 bot creators plus
local-agent branches, with no per-creator patch and no cron janitor.

Merged PRs are excluded (already auto-deleted by `delete_branch_on_merge`).
The one residual gap — branches pushed where `gh pr create` *failed*, so no
PR-close event ever fires — is documented in the workflow header as an
intentionally-uncovered tail, not papered over with a cron sweep.

## Key Insight

- **"Fix the source not the symptom" ≠ "patch every producer."** When the
  producer is async / fire-and-forget and exits before the leak-triggering
  state exists, the source-aligned fix lives at the **leak event**, and one
  reactive event handler is source-agnostic across all producers. Before
  choosing a source-fix, ask: *can the source still act when the cleanup
  trigger occurs?* If it has already exited, a reactive handler — not a
  per-creator patch and not a cron janitor — is the source-aligned answer.
- **A built-in setting named for transition X covers only X.** When an
  existing config/guard appears to address a problem (`delete_branch_on_merge`,
  `on_create`, `on_success`), reflexively enumerate the **sibling transitions
  it does NOT fire on** (`on_close`, `on_delete`, `on_failure`) before
  declaring the surface covered. "We already have setting X" must be followed
  by "X covers only subset Y; which transitions leak?" Here: merge is covered,
  close-without-merge leaks.

## Session Errors

- **Cited stale GHA workflow files read from the bare-repo root.** My first
  analysis named workflow files (`scheduled-content-generator.yml` etc.) as the
  branch creators, read from the bare-repo root's on-disk working files. Those
  files were **stale** — on true `origin/main` those workflows were deleted in
  #4483 (migrated to Inngest). Only the worktree (true main) *lacking* the
  files surfaced the error; the corrected analysis identified the 7 Inngest
  crons + 1 GHA as the real creators.
  **Prevention:** already codified by `hr-when-in-a-worktree-never-read-from-bare`
  (AGENTS.core.md) and learnings 2026-05-21 / 2026-03-13 / 2026-05-19. When
  citing files as evidence, read from a worktree (or `git show origin/main:<path>`),
  never the bare-repo root's synced-but-stale working files. This was an
  application failure, not a knowledge gap — no new rule needed.
