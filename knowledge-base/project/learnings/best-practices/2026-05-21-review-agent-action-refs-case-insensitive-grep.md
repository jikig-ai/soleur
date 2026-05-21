---
date: 2026-05-21
category: best-practices
module: review
tags: [review, grep, github-actions, case-sensitivity, false-positive]
related_pr: 4208
related_learnings:
  - 2026-05-12-multi-agent-review-cross-reconcile-catches-false-positive-high-findings.md
  - 2026-05-20-plan-acs-self-grep-scope-and-identifier-source-verification.md
---

# Review-agent action/SHA reference greps must be case-insensitive

## Problem

PR #4208 fixes a 1-line `dopplerhq/cli-action` SHA pin in `.github/workflows/kb-drift-walker.yml`. The plan's "v3 cohort: 7 files" claim was independently verified at plan time via `git grep -hE 'uses: [Dd]opplerHQ/cli-action@[0-9a-f]+'` (case-insensitive bracket class).

At review time, `git-history-analyzer` produced a P2 finding asserting that 3 of the 7 cited siblings (`scheduled-realtime-probe.yml`, `scheduled-ux-audit.yml`, `scheduled-community-monitor.yml`) don't reference `dopplerhq/cli-action` at all — claiming the plan's evidence list was overcounted.

The agent's grep was case-sensitive against lowercase `dopplerhq/`. Those 3 workflows use `DopplerHQ/cli-action` (CamelCase). GitHub Actions accepts both casings; the v3 cohort is genuinely mixed.

## Solution

Dismissed the finding per the cross-reconcile triad rule (no other agent surfaced the same concern). Re-ran the case-insensitive grep:

```bash
git grep -nE 'uses: [Dd]opplerHQ/cli-action@[0-9a-f]+' .github/workflows/
```

Confirmed the plan's "7 files" count was correct: 4 lowercase `dopplerhq/` sites (cla-evidence*, kb-drift-walker, web-platform-release ×3) + 3 CamelCase `DopplerHQ/` sites (scheduled-community-monitor, scheduled-realtime-probe, scheduled-ux-audit) = 7 unique files, 9 occurrences post-fix.

## Key Insight

GitHub Actions accepts mixed casing for the `<owner>/<action>` slug (`DopplerHQ/cli-action` and `dopplerhq/cli-action` resolve to the same action). Any review-time grep that searches for action references, SHA pin cohorts, or vendor-namespace literals MUST use a case-insensitive pattern (`[Dd]opplerHQ`, `(?i)`, or `grep -i`). Single-casing greps produce silent under-counts that look like real discrepancies and trigger false-positive findings.

Generalizes beyond GitHub Actions: any time a review agent enumerates references to an externally-named primitive whose canonical casing is mixed in the wild (Docker image owners, GitHub orgs, npm scopes that allow casing variants), default to case-insensitive matching.

## Prevention

When spawning review agents for PRs touching SHA pins / vendored references / cross-file cohorts, include in the spawn prompt: *"Use case-insensitive grep (`-i` or bracket class `[Aa]`) when enumerating action/vendor references — repos commonly mix CamelCase and lowercase for the same primitive."*

For the broader pattern (cross-reconcile triad), the existing learning `2026-05-12-multi-agent-review-cross-reconcile-catches-false-positive-high-findings.md` already covers the disposition rule. This learning narrows the *cause class* one level: case-sensitivity is a specific, mechanical contributor to single-agent false positives.

## Session Errors

- **PreToolUse `security_reminder_hook.py` blocked the first workflow Edit** — generic injection warning fires on any `.github/workflows/` edit regardless of whether the diff touches untrusted-input patterns. Recovery: re-ran Edit verbatim, second attempt succeeded. Prevention: hook could gate on whether the diff introduces a new `${{ github.event.* }}` / `github.head_ref` / similar token, not on the file path alone.
- **Chained bash verification short-circuited mid-pipe** — a `echo && grep -rn && echo && grep -c` chain stopped at an intermediate `grep -rn` returning exit 1 (no-match), even with `|| echo "fallback"` inside a subshell. Recovery: ran each check as a separate Bash call. Prevention: for multi-step verification scripts, prefer `; echo "rc=$?"` between probes (or wrap each in `(probe; true)`) so any single failure doesn't kill the whole pipe.
- **Review-agent false positive (this learning)** — see Problem section above. Prevention: case-insensitive default in review spawn prompts.
