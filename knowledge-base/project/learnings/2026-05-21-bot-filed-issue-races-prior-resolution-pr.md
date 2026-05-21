---
title: "Bot-filed issue races prior-resolution PR — extend triage-time duplicate detection to file-deletion case"
date: 2026-05-21
category: engineering
tags: [triage, bot, stale-issue, duplicate-detection, race-condition]
related_prs: [4220, 4221-followup]
related_issues: [4221]
related_learnings:
  - knowledge-base/project/learnings/2026-04-22-triage-time-duplicate-detection-for-workflow-fixes.md
  - knowledge-base/project/learnings/best-practices/2026-05-20-plan-time-pr-vs-issue-disambiguation-and-self-derived-counts.md
---

# Bot-filed issue races prior-resolution PR

## Problem

On 2026-05-21, a bot filed issue [#4221](https://github.com/jikig-ai/soleur/issues/4221) reporting that `.github/workflows/auto-approve-trusted-applies.yml` was failing on every push to main. The bot's evidence (4 failure runs at 08:18Z, 08:23Z, 08:25Z, 08:29Z) was real — but the workflow file no longer existed in the repository.

PR [#4220](https://github.com/jikig-ai/soleur/pull/4220) (`fix(ci): remove env-reviewer gates on apply-*-infra workflows; revert PR #4218`) had merged at **2026-05-21T08:34:57Z** and deleted the workflow. Issue #4221 was filed at **2026-05-21T08:35:59Z** — exactly **62 seconds later**. The bot was working from a stale snapshot of the repo state.

Without a detection at triage consumption time, the issue would have absorbed a planning cycle (≈30k tokens, hours of clock) producing fixes for a file that does not exist.

## Why existing rules missed it

The 2026-04-22 learning [`triage-time-duplicate-detection-for-workflow-fixes.md`](2026-04-22-triage-time-duplicate-detection-for-workflow-fixes.md) prescribed greping the file the issue body cites for the current value — to detect the "current value already matches the proposed fix" case (#2519 → #2526). The recipe **assumed the file still exists**. When the resolution is a *deletion*, the grep returns empty (file gone), which the heuristic conflated with "file not yet touched (proceed with fix)" instead of "issue is stale (file deleted)".

AGENTS.md `hr-before-asserting-github-issue-status` fires on assertions about issue state (open/closed/merged), not on the upstream "does the referenced artifact still exist" check. AGENTS.md `hr-when-triaging-a-batch-of-issues-never` covers triage hygiene (don't auto-comment on N issues unverified) but not the existence sub-check. The gap is at issue-read boundary: we read the body, extract the workflow path, and proceed without checking `git ls-files <path>`.

## Heuristic to add at triage / one-shot Step 0

Before treating a bot-filed issue (or any issue whose body cites a specific file path) as actionable, check whether the referenced file still exists. If absent, search recent merged PRs for a deletion.

```bash
# 1. Extract file path(s) from the issue body.
path=".github/workflows/auto-approve-trusted-applies.yml"   # example
issue_created_at=$(gh issue view 4221 --json createdAt -q .createdAt)

# 2. If the path no longer exists on main, search the prior 1-hour window for a PR that deleted it.
if ! git ls-files "$path" | grep -q .; then
  # Window: issue_created_at - 1 hour (timestamps come from independent clocks; widen the window)
  window_start=$(python3 -c "import datetime; t=datetime.datetime.fromisoformat('${issue_created_at}'.replace('Z','+00:00')) - datetime.timedelta(hours=1); print(t.strftime('%Y-%m-%dT%H:%M:%SZ'))")
  gh pr list --state merged --search "${path} merged:>=${window_start}" \
    --json number,title,mergedAt,files \
    | jq --arg p "$path" '.[] | select(.files[]?.path == $p) | {number,title,mergedAt}'
  # If any match: close the issue as duplicate, citing the PR that removed the file.
fi

# 3. Belt-and-braces for workflow files: cross-check the Actions API for registration.
gh api "repos/${OWNER}/${REPO}/actions/workflows" --paginate \
  | jq --arg p "$(basename "$path")" '.workflows[] | select(.path|endswith($p))'
# Empty result is the canonical "workflow is gone" signal.

# 4. Symmetric PR-vs-issue disambiguation (see 2026-05-20 learning).
# A bare number `#N` may resolve to an issue OR a PR — probe BOTH before routing:
gh issue view "$N" --json state,title 2>/dev/null   # issue probe
gh pr view "$N" --json state,title 2>/dev/null      # pr probe
# If both succeed, the body's references should disambiguate which is the subject.
```

## Sharp edge — detection must run at consumption, not at filing

A bot that races a prior-resolution PR by N seconds is **indistinguishable at issue-filing time from a real new failure**. The bot saw 4 real failures and filed; there was no broken bot behavior to fix at filing time.

The catch is at the *consumption* boundary: whenever `/soleur:triage`, `/soleur:one-shot`, or a human triager reads the issue and decides to act on it. The added cost is:

- One `git ls-files <path>` (<10ms local)
- One conditional `gh pr list --search` (≈300ms when triggered)

The avoided cost is hours of clock plus ≈30k tokens for a planning cycle on an empty target. Net: ≈1-second probe at every triage-read, saving one full planning cycle per stale-issue race. Worth it.

Trying to prevent the bot from filing in the first place is a separate (harder) problem: race-condition detection across independent agents requires either (a) shared state the filing agent reads, or (b) a holdback window the filing agent enforces. Both are out of scope for the learning system.

## References

- Prior art (value-matches-fix detection, file-exists case): [`2026-04-22-triage-time-duplicate-detection-for-workflow-fixes.md`](2026-04-22-triage-time-duplicate-detection-for-workflow-fixes.md)
- PR-vs-issue disambiguation (symmetric `gh issue view` + `gh pr view` probe): [`best-practices/2026-05-20-plan-time-pr-vs-issue-disambiguation-and-self-derived-counts.md`](best-practices/2026-05-20-plan-time-pr-vs-issue-disambiguation-and-self-derived-counts.md)
- AGENTS.md `hr-before-asserting-github-issue-status` — fires on state assertions; this learning plugs the upstream "does the artifact still exist" gap.
- AGENTS.md `hr-when-triaging-a-batch-of-issues-never` — triage hygiene; this learning adds the file-existence sub-check.
- PR [#4220](https://github.com/jikig-ai/soleur/pull/4220) — the deletion that raced issue #4221.
- Issue [#4221](https://github.com/jikig-ai/soleur/issues/4221) — the stale-bot-filing this learning is named for.
