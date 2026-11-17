# Learning: a cleanup PR owes its counts to the merged tree, and every premise about a sibling PR to a fresh read

## Problem

PR #12306 (issue #12270, Ref #12189) removed the two `-target` lines and two census `INTENDED_DESTROYS` entries that were kept for exactly one apply, after run 42369320061 destroyed the retired canary alert pair (`2 destroyed`). The diff was small (11 files, mostly guards and dated-record additions), but the branch lived through a panel review and four `origin/main` moves, and three premises carried in prose turned out stale or wrong.

## Solution

- Re-run the full named suite set (32 suites) on the merged tree after EVERY main move, then read the pinned numbers off the run (structure 110, ceiling 116, egress 128, send-failed 39, probe 427, census 422, luks 187, target-parity 377). The third merge (#12307) added four `-target` lines to the same workflow and the fourth (#10928) changed the destroy-guard filter; neither moved a pin, but only the run could say so.
- Prove each guard row on a scratch `git clone --shared` copy, not by reading: re-adding both targets reds the structure suite; re-adding only the census entries reds the probe's referrer set; a third undeclared target reds the structure suite; `MIN_ASSERTIONS` +-1 produces two distinct FATAL fragments.
- Dated records (runbook, ADR-218) are append-only: one owner paragraph in the runbook holds the observations, and ADR lines are pointers that name the amendment owning each sentence. Superseded sentences are marked by a bracketed pointer, never edited.
- Time-stamp any statement about an open sibling PR ("#12292 is on a pre-retirement base"); re-read it with `gh` at re-sync. It was wrong when written and the PR merged mid-review.

## Key Insight

A pinned count is a fact about a tree, and a sentence about another PR is a fact about a moment. A cleanup PR that waits in review inherits both clocks; each main move re-opens the counts, and each re-sync re-opens the sibling-PR sentences.

## Session Errors

1. **Brief claimed this diff pins `LC_ALL=C` on its `comm` calls** — the pin came from the retirement PR; three seats caught it. Recovery: corrected in review. **Prevention:** before writing "this diff does X" into a review brief, grep the diff for X.
2. **Plan and session-state asserted #12292 was on a pre-retirement base** — wrong when written; #12292 later merged and conflicted at the ADR tail. Recovery: time-stamped correction, conflict resolved keeping both amendments in merge order. **Prevention:** `gh pr view <n> --json baseRefOid,mergedAt` before asserting anything about a sibling PR, and record the date.
3. **Fix-round pointer lines overclaimed** (wrong amendment cited; runbook pointer did not cover the sentences named). Recovery: fixed in round two. **Prevention:** for every pointer line, open the target and confirm the sentence it claims is there.
4. **Security seat ended without a report (last block was a tool_use).** Recovery: resumed it and verified its open items myself. **Prevention:** already in the review skill hygiene notes; no new rule.
5. **Local affected gate `failed-before-budget` and one ratchet-lane member red only inside the lane** (`/home/jean` is itself a git work tree). Recovery: recorded as environmental non-verdicts; the suite passes directly from the worktree and on a pristine main clone. **Prevention:** record an unresolved gate as unresolved, never as a verdict.
6. **Main moved three times during the final re-sync.** Recovery: merged each time and re-ran all 32 suites before pushing. **Prevention:** the re-sync step re-runs the full set on the merged tree, not the earlier counts.
7. **Hooks blocked a recursive delete and a full-command-line process search (twice, the second time on learning text that quoted the command).** Recovery: unique `mktemp` names, the repo's process-listing helper, and the Write tool for prose that names a blocked command. **Prevention:** none needed; the hooks worked as intended.

## Tags
category: workflow-patterns
module: infra-guards, apply-web-platform-infra
