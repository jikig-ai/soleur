---
title: An absent config with an upstream blocker + watcher is not drift — verify intent before proposing a fix
date: 2026-07-16
category: integration-issues
module: infra/github
tags: [terraform, github-ruleset, merge-queue, codeql, config-diagnosis, false-drift, review-reasoning]
related_issues: [6512, 5780, 5840, 6458]
related_learnings:
  - knowledge-base/project/learnings/2026-07-15-false-comment-shipped-the-bug-then-plan-guard-adr-and-tests-each-restated-it.md
---

# Learning: an absent config that is absent-*by-design* looks identical to drift

## Problem

While closing out the #6458 session I hit real, repeated pain: the strict
"require branches up to date" policy sent the PR back to `BEHIND` three times as
`main` advanced, forcing a manual `gh pr update-branch` each time. I noticed
`infra/github/ruleset-ci-required.tf` *mentions* a GitHub merge queue — the exact
mechanism that would absorb this churn — but the live ruleset has no `merge_queue`
rule. I flagged it as **config drift** ("documented intent, never applied") and
proposed fixing it by adding the rule.

That was wrong, and the fix would have been a security regression.

## Investigation

Reading the file properly instead of skimming its comments:

- The `merge_queue` block was **added by #5780 and deliberately REVERTED on
  2026-06-30**. Its absence is the intended state, not an omission.
- Reason (stated verbatim in the file): a merge queue posts status checks on the
  `merge_group` ref, but **CodeQL reports no status on `merge_group` in ANY setup
  mode** (upstream `github/codeql-action#1537`). A merge queue and a *required*
  `CodeQL` check are therefore mutually exclusive on GitHub.
- `CodeQL` is a required context in the same ruleset (`context = "CodeQL"`), and a
  comment says outright: *"DO NOT re-adopt the queue by converting CodeQL to
  advanced setup … decision is to keep CodeQL required."*
- The re-adoption window is already automated: `codeql-1537-revisit-watch.yml`
  polls #1537 monthly and, when it closes, comments on standing tracking issue
  **#5840** (`merge-queue-revisit`) and flags it `needs-attention`.

Live check at the time: `gh issue view 1537 --repo github/codeql-action` → still
**OPEN** (updated 2026-05-22). The blocker is current, not stale. Re-adding the
rule would have dropped a required security gate to buy merge-queue convenience.

## Root cause

Two ordinary things combined to make a correct state read as a bug:

1. **A recurring symptom primed the wrong diagnosis.** The `BEHIND` starvation was
   genuinely painful and genuinely what a merge queue fixes, so "the queue is
   missing" felt *confirmed by the symptom* before the file was read. The pain was
   real; the causal story ("missing because nobody applied it") was invented.
2. **Absent-by-design is visually identical to drift.** A file that discusses a
   mechanism it does not currently declare looks the same whether the mechanism was
   never added or was added and removed on purpose. The distinguishing evidence —
   REVERT date, upstream-issue ref, a watcher, a tracking issue — lives in prose
   comments that a skim glides over.

## Key insight

**Before flagging a missing/absent piece of infrastructure as fixable drift,
prove the absence is accidental rather than deliberate.** The tell for
*deliberate* absence is cheap to grep for in the same file:

```bash
# In the file that "should" declare the missing thing, look for intent-to-omit:
grep -niE 'revert|removed|do not (re-?adopt|re-?add|enable)|mutually exclusive|kill.?switch|upstream (issue|bug)|#[0-9]+' infra/github/ruleset-ci-required.tf
```

If any of those hit near the mechanism, the absence is a decision — find the
decision's blocker and its re-visit trigger (a watcher workflow, a tracking issue)
before proposing to "fix" it. Re-adding a by-design omission can *undo the reason
it was omitted*; here that reason was a required security check.

Corollary: a painful recurring symptom is evidence that *a* problem exists, never
evidence for *your* explanation of it. Read the authoritative source before letting
the symptom pick the cause.

## Prevention

- **Grep the owning file for revert/blocker/upstream markers** (above) as step 1 of
  any "this infra looks missing" claim. Absence + an upstream issue ref + a watcher
  is the signature of by-design, not drift.
- **Check for a standing watcher/tracking issue.** Repos that revert something
  pending an upstream fix tend to leave a monthly watcher and a labelled tracking
  issue. If one exists, the omission is managed; there is nothing to fix.
- **Name the security/consistency cost of re-adding** before proposing it. If
  re-adding the thing weakens a required gate, that is a regression regardless of
  the convenience gained.

This is the sibling of `hr-verify-repo-capability-claim-before-assert`: that rule
guards against asserting a capability *exists*; this guards against asserting a
capability is *missing-as-a-bug*. Both are "read the source before you assert."

## Session Errors

- **Misdiagnosed absent `merge_queue` as fixable drift** — Recovery: read the file's
  own revert comment + checked upstream #1537 live (still OPEN) + confirmed the
  watcher/#5840 apparatus, then withdrew the proposal. Prevention: the grep
  heuristic above, run before flagging absent infra as drift.
- **`cleanup-merged` deleted a freshly-created empty worktree** — a branch created
  at `main`'s HEAD has no commits, so `git branch --merged main` classifies it as
  merged and the sweeper removes it. Recovery: recreated the worktree and gave the
  branch a commit immediately. Prevention: when creating a worktree purely to hold
  new work, make the first commit before running any `cleanup-merged`, or have the
  sweeper skip zero-commit-ahead branches younger than N minutes (candidate
  follow-up — different subsystem, not fixed here).
- **`gh issue create` rejected without `--milestone`** — Recovery: re-ran with
  `--milestone "Post-MVP / Later"` (the documented default for operational issues).
  Prevention: already hook-enforced; no change needed.

## Tags

category: integration-issues
module: infra/github
