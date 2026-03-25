---
title: "fix: bug fixer workflow resilience for max-turns exhaustion"
type: fix
date: 2026-03-25
---

# Fix Bug Fixer Workflow Resilience

## Problem

The `scheduled-bug-fixer.yml` workflow has a failure mode where the agent successfully creates a PR but then hits the `--max-turns 25` limit. When this happens:

1. The `claude-code-action` step exits with a non-zero status (`error_max_turns`)
2. GitHub Actions applies the implicit `success()` condition to all subsequent steps
3. All three post-fix steps are skipped: **Detect bot-fix PR**, **Auto-merge gate**, **Discord notification**
4. The PR sits orphaned -- no auto-merge evaluation, no notification

This has been flagged in the project learnings (`2026-03-20-claude-code-action-max-turns-budget.md`): the bug fixer's 25-turn budget is "at risk" given the formula `plugin overhead (~10) + task tool calls + error/retry buffer (~5)`.

The fix-issue skill requires turns for: reading the issue (~1), running baseline tests (~1-2), creating a worktree (~1), reading/locating/fixing the bug (~3-5), running tests again (~1-2), committing + pushing (~2), creating PR (~1), labeling PR (~1), plus AGENTS.md/constitution overhead (~10). That totals ~21-25 turns with zero margin for retries or edge cases.

## Root Cause

Two independent issues:

1. **Insufficient turn budget.** 25 turns leaves no headroom for the fix-issue skill when plugin overhead is accounted for.
2. **Missing `always()` on post-fix steps.** GitHub Actions skips steps with the default `success()` condition when any prior step fails. The post-fix steps should run whenever a PR *might* exist, regardless of the agent's exit status.

## Solution

### Change 1: Increase `--max-turns` from 25 to 35

In the `Fix issue` step, change `--max-turns 25` to `--max-turns 35`.

**Rationale:** The learning document suggests `required turns = plugin overhead (~10) + task tool calls (~15) + error/retry buffer (~5) = ~30`. Setting to 35 provides a 5-turn margin above the formula. This aligns with the pattern of other workflows (ship-merge: 40, competitive-analysis: 45, community-monitor: 50).

**File:** `.github/workflows/scheduled-bug-fixer.yml`, line 126

### Change 2: Add `always()` to post-fix step conditions

Three steps need their `if` conditions updated:

| Step | Current `if` | New `if` |
|------|-------------|----------|
| Detect bot-fix PR | `steps.select.outputs.issue` | `always() && steps.select.outputs.issue` |
| Auto-merge gate | `steps.detect_pr.outputs.pr_number` | `always() && steps.detect_pr.outputs.pr_number` |
| Discord notification | `steps.detect_pr.outputs.pr_number` | `always() && steps.detect_pr.outputs.pr_number` |

**Rationale:** The `always()` function overrides the implicit `success()` condition, ensuring these steps run even when the `Fix issue` step exits non-zero (e.g., due to `error_max_turns`). The existing `&&` condition still gates on the relevant output being present -- if no issue was selected or no PR was detected, the steps correctly skip.

**Precedent:** `scheduled-ship-merge.yml` line 131 uses this exact pattern: `if: always() && steps.select.outputs.pr_number`.

**File:** `.github/workflows/scheduled-bug-fixer.yml`, lines 136, 157, 214

## Acceptance Criteria

- [ ] `--max-turns` is set to 35 in the `Fix issue` step (`.github/workflows/scheduled-bug-fixer.yml`)
- [ ] "Detect bot-fix PR" step uses `if: always() && steps.select.outputs.issue`
- [ ] "Auto-merge gate" step uses `if: always() && steps.detect_pr.outputs.pr_number`
- [ ] "Discord notification" step uses `if: always() && steps.detect_pr.outputs.pr_number`
- [ ] Workflow YAML passes GitHub Actions syntax validation (no invalid `if` expressions)
- [ ] Update the learnings document `2026-03-20-claude-code-action-max-turns-budget.md` to reflect the new budget (25 -> 35)

## Test Scenarios

- Given the agent completes successfully within 35 turns, when all steps run, then behavior is unchanged from today (detect PR, evaluate auto-merge, send notification)
- Given the agent hits the 35-turn limit but has already created a PR, when the `Fix issue` step exits non-zero, then the "Detect bot-fix PR" step still runs and finds the PR
- Given the agent hits the turn limit before creating a PR, when the "Detect bot-fix PR" step runs, then `pr_number` output is empty and subsequent steps correctly skip
- Given no qualifying issue is found in the "Select issue" step, when `steps.select.outputs.issue` is empty, then all downstream steps (including those with `always()`) are skipped due to the `&&` condition
- Given the agent fails for a non-turn-limit reason (e.g., API error), when the `Fix issue` step exits non-zero, then post-fix steps still evaluate correctly (same `always()` behavior)

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- infrastructure/tooling change.

## Context

### Relevant Files

- `.github/workflows/scheduled-bug-fixer.yml` -- the workflow being modified
- `.github/workflows/scheduled-ship-merge.yml:131` -- precedent for `always()` pattern
- `knowledge-base/project/learnings/2026-03-20-claude-code-action-max-turns-budget.md` -- documents the turn budget formula and flags bug fixer as "at risk"
- `plugins/soleur/skills/fix-issue/SKILL.md` -- the skill invoked by the workflow (turn consumption analysis)

### References

- [GitHub Actions: `always()` status check function](https://docs.github.com/en/actions/writing-workflows/choosing-what-your-workflow-does/evaluate-expressions-in-a-workflow#always)
- Related learning: `2026-03-03-scheduled-bot-fix-workflow-patterns.md`
