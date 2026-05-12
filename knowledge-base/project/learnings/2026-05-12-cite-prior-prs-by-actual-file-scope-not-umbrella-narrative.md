---
title: "Cite prior PRs by actual file scope, not umbrella narrative, when narrating plan-precondition drift"
date: 2026-05-12
type: best-practice
category: documentation-accuracy
tags: [pr-narrative, commit-messages, plan-drift, git-history]
related-prs: [3662, 3603]
related-learnings:
  - 2026-05-10-handshake-schema-drift-and-stale-precondition-budgets
---

# Cite prior PRs by actual file scope, not umbrella narrative

## Problem

PR #3662 (PR-C of #3603) discovered at edit time that the v2 plan's Research Reconciliation table was substantially stale — prior PRs had already forward-ported most rows the plan claimed were "absent from canonical." The PR body and commit footers narrated this scope-realignment honestly, but bundled three distinct prior PRs under one umbrella citation:

> "Verified at edit time that the plan's Research Reconciliation table was substantially stale — PR-A1 (#3447 → main) and #1860 already forward-ported most of what the v2 plan said was 'absent from canonical'."

`git-history-analyzer` (in the review phase) caught the misattribution by running `git show <sha> --stat` against each cited commit:

- `c46dd0c2` (#3447, "PR-A1") touched **only** `docs/legal/privacy-policy.md`.
- `de5f37fb` (#1048/#1297, 2026-03) was the actual source of DPD §2.3(i) + GDPR §3.7 + GDPR §10 #10 forward-ports.
- `5237793b` (#1860) added GDPR §10 #11 KB sharing.

The PR body claim that #3447 forward-ported DPD/GDPR was false. Three distinct file scopes (Privacy / DPD+GDPR / KB sharing) had been bundled under two PR citations.

## Solution

When narrating plan-precondition drift in PR/commit messages and citing prior PRs as the cause:

1. **Run `git show <sha> --stat` for each cited commit** before including it in the narrative.
2. **Bundle citations by file scope, not by umbrella narrative.** If three distinct files were forward-ported by three distinct PRs at three distinct times, cite three PRs.
3. **Prefer concrete SHA + PR# pairs** over alias-only references ("PR-A1") when the alias resolves to a different scope than the reader expects from the narrative.

Corrected PR-C body:

> "prior PRs already forward-ported most of what the v2 plan said was 'absent from canonical': `#1048`/`#1297` (`de5f37fb`, 2026-03) added canonical DPD §2.3(i) + GDPR §3.7 + GDPR §10 #10; `#3447` (`c46dd0c2`, 2026-05) added canonical Privacy §4.7 Conversation-data bullet; `#1860` (`5237793b`) added canonical GDPR §10 #11 KB sharing."

## Key Insight

A scope-realignment narrative that uses bundled-PR citations is brittle: a single git log lookup by a reviewer (or the next operator reading the PR archive) falsifies the claim. The cost of `git show <sha> --stat` per citation is ~1 second; the cost of a false-attribution citation is reviewer-cycle waste + a small permanent inaccuracy in the PR archive.

This is symmetric to the broader plan-precondition principle: plan-quoted numbers are preconditions to verify, not facts. Commit-message-cited prior PRs are claims to verify, not facts.

## Session Errors

- **PR body misattributed prior-PR forward-ports** (PR #3662 initial body). Recovery: `gh pr edit --body-file` with corrected three-PR mapping. Prevention: run `git show <sha> --stat` per cited PR before including in narrative. Bundle by file-scope, not umbrella.
- **Initial bash commands failed at bare repo root.** Recovery: cd into worktree absolute path. Prevention: skill setup probes pwd and auto-redirects when invoked from bare repo root with a target worktree present (or fails-fast with a recovery prompt). Per `hr-when-in-a-worktree-never-read-from-bare`.
- **Edit tool "File has not been read yet" on plugin DPD file.** Recovery: Read then re-issue edits. Prevention: already mechanically enforced by Edit tool; agent reminder that structural analogy to a sibling file just read does not waive Read-before-Edit. Per `hr-always-read-a-file-before-editing-it`.

## Tags

category: documentation-accuracy
module: pr-narrative
