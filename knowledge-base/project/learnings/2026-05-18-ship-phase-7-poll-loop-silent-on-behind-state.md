---
date: 2026-05-18
related: [3947, 3984]
related_rules:
  - hr-when-a-workflow-concludes-with-an
  - hr-exhaust-all-automated-options-before
  - wg-ship-push-before-merge
category: workflow-adherence
---

# `/soleur:ship` Phase 7 poll loop sat on `OPEN BEHIND` indefinitely

## What happened

On PR #3984 (PR-G cohort onboarding) after `gh pr merge --squash --auto` queued auto-merge, the Phase 7 poll loop observed:

```
16:56:39 [1/15] PR 3984 OPEN BLOCKED
16:59:43 [4/15] PR 3984 OPEN BLOCKED
17:00:45 [5/15] PR 3984 OPEN UNKNOWN
17:01:46 [6/15] PR 3984 OPEN BEHIND
17:02:47 [7/15] PR 3984 OPEN BEHIND
17:05:51 [10/15] PR 3984 OPEN BEHIND
```

The transition `BLOCKED → UNKNOWN → BEHIND` happened because origin/main received commit `4c918c05 feat(runtime): migrate scheduled-daily-triage to Inngest cron (#3985)` while PR-G's CI was running. GitHub's auto-merge feature does not fire while the head ref is behind base — it silently waits. The poll loop had no `BEHIND` handler; it just observed the state every minute and would have exhausted its 15-minute budget without progress, then timed out.

The operator noticed and asked: "why is auto-merge not firing?" The answer surfaced the gap: BEHIND requires merging main into the branch and pushing; the poll loop wasn't doing that.

## Why the existing pre-merge hook didn't cover this

`.claude/hooks/pre-merge-rebase.sh` is a PreToolUse hook on Bash. It fires when the operator (or agent) runs git/gh commands and auto-merges main into the current branch when the branch is behind. **It did fire** earlier in this same session — after `gh pr merge --disable-auto` was called to cancel auto-merge for a fix, the hook auto-synced main into the branch and pushed. That's the "Pre-merge hook: merged origin/main into feat-pr-g-cohort-onboarding and pushed. Branch is now current." system-reminder we saw.

But the hook fires on Bash tool calls. During the Phase 7 poll loop, the only Bash call running is the `gh pr view` poll — and that doesn't qualify as a merge-adjacent operation. The hook's trigger set doesn't include `gh pr view`. So once the poll loop is running, no Bash call fires that would trigger the hook, and the BEHIND state sits.

The two surfaces are complementary:
- **Hook** (operator-triggered Bash on commit/push/merge): handles BEHIND BEFORE auto-merge is queued.
- **Poll loop** (fixed 60-second cadence after auto-merge is queued): now handles BEHIND AFTER auto-merge is queued.

## The fix

`plugins/soleur/skills/ship/SKILL.md` Phase 7 poll loop adds a `BEHIND` branch that:

1. Fetches origin/main.
2. `git merge origin/main --no-edit`. If conflicts: abort the merge, list conflicted paths, stop the poll (operator must resolve).
3. `git push`. If conflicts with a concurrent push: stop the poll.

Capped at `MAX_BEHIND_SYNCS=3` per poll invocation to defend against a parallel-active-repo pathology where every sync produces a fresh BEHIND state and consumes the entire poll budget. After 3 syncs the loop falls through to the heartbeat path, and the timeout warning surfaces that the operator needs to merge during a quieter window.

## Why this gap existed for so long

Two conditions both have to hold:
- **An active-enough main** that commits land while a PR's CI is running. Pre-2026-Q2 the merge cadence was low enough that BEHIND was rare during the 15-minute poll window. As the team's velocity grew in Q1-Q2 2026, BEHIND-during-poll became routine.
- **Auto-merge being used** (not synchronous `gh pr merge --squash`). Auto-merge is queue-based; sync merge would have failed loudly with "branch is behind base" and forced manual intervention. Auto-merge sits silent.

The combination produces a class of stuck PRs that the operator only notices when they check on a PR they expected to be merged.

## How to prevent this class going forward

- **Auto-handle every `mergeStateStatus` value the poll observes.** The known values per the GitHub API: `BEHIND`, `BLOCKED`, `CLEAN`, `DIRTY`, `DRAFT`, `HAS_HOOKS`, `UNKNOWN`, `UNSTABLE`. `BEHIND` is now handled; `DIRTY` (merge conflicts on main) was already handled in Phase 6.5 BEFORE auto-merge is queued; `UNSTABLE` (required checks pass but optional checks fail) is GitHub's signal that auto-merge will fire on its own. `BLOCKED` is the long-wait state; the poll loop just heartbeats through it. Add a handler whenever a state value would cause the loop to "wait forever" with no recovery.
- **The hook layer and the poll loop are not redundant — they're staged.** PRs created without `/ship` (manual `gh pr create`, GitHub UI) skip the hook surface but still hit the poll loop if `/ship` is invoked later. PRs created via `/ship` whose auto-merge stays queued for >1 minute hit the poll loop regardless of hook coverage. Treat the two as complementary; coverage of one does not justify omitting the other.
- **When debugging a stuck merge, the first probe is `gh pr view <N> --json mergeStateStatus`.** A `BEHIND` value answers "why isn't auto-merge firing?" in one call. A `BLOCKED` value points to a required check that's failing or has not registered. A `DIRTY` value points to a merge conflict that must be resolved.

## Cross-reference

This sits next to `2026-05-18-work-skill-stopped-before-phase-11-7-pre-merge-acs.md` — that learning covers the workflow violation of stopping mid-pipeline; this one covers the workflow gap of polling without an auto-recover handler. Both surfaced on the same PR (#3984) and contribute to the same pattern: long-running orchestrators must not have "wait forever" states without an automatic-recovery path.
