---
title: "feat: full autonomous bug-fix pipeline"
type: feat
date: 2026-03-05
---

# feat: Full Autonomous Bug-Fix Pipeline (Phase 3 of #370)

## Overview

Upgrade the supervised bug-fix pipeline (Phase 2) to a fully autonomous loop: the agent triages, fixes, auto-merges qualifying PRs, monitors post-merge CI, and auto-reverts on failure. Graduated autonomy starts with the narrowest scope (single-file p3-low fixes) and expands based on track record.

Ref #377. Prereqs #370 (Phase 1 -- triage, CLOSED), #376 (Phase 2 -- supervised fix, CLOSED).

## Problem Statement

Phase 2 produces bot-fix PRs that sit in the review queue because human review is a bottleneck for trivial single-file fixes. The bot already handles issue selection, fix generation, test validation, and PR creation. The remaining gap is merge authority and post-merge safety -- the human reviewer is currently the only safety gate, but for the narrowest scope of fixes (single-file, p3-low, tests pass), the safety gate can be mechanical instead.

## Non-Goals

- Multi-file autonomous fixes. The single-file constraint remains for autonomous merges; multi-file PRs still require human review.
- Expanding fix scope to p1-high or p2-medium autonomously. Only p3-low issues qualify for auto-merge in v1.
- Dependency, schema, or infrastructure changes. The constraint list from Phase 2 remains unchanged.
- Replacing human review entirely. The graduated autonomy model adds auto-merge as a parallel path, not a replacement.
- Dollar-based cost caps (Claude Code CLI has no `--max-cost` flag).
- Custom PAT or GitHub App token. The existing `claude-code-action` App installation token and `GITHUB_TOKEN` are sufficient given the CLA ruleset bypass already in place.

## Proposed Solution

Four components layered on top of the existing Phase 2 infrastructure:

### 1. Auto-Merge Gate in `scheduled-bug-fixer.yml`

After the agent creates a PR, a new workflow step evaluates auto-merge eligibility. Criteria:

- PR was created by the bot (title starts with `[bot-fix]`)
- Only one file changed (`gh pr diff --stat` shows exactly 1 file)
- All CI checks pass (tests green)
- Source issue was `priority/p3-low` (not a cascaded higher-priority pick)
- PR has label `bot-fix/auto-merge-eligible` (set by the agent when criteria met)

If all criteria pass, the workflow enables auto-merge: `gh pr merge <number> --squash --auto`.

### 2. Post-Merge CI Monitor Workflow (`post-merge-monitor.yml`)

A new workflow triggered on `push` to `main` that:

1. Detects if the push is from a bot-fix PR (commit message starts with `[bot-fix]`)
2. Waits for CI to complete on main
3. If CI fails:
   - Creates a revert PR: `git revert HEAD --no-edit && git push -u origin revert-bot-fix-<N>`
   - Auto-merges the revert PR
   - Comments on the original issue: "Autonomous fix was reverted due to CI failure on main"
   - Removes `bot-fix/attempted` label so the issue re-enters the queue (with a `bot-fix/reverted` label to track history)
4. If CI passes: adds `bot-fix/verified` label to the source issue, then closes it

### 3. Graduated Autonomy Labels

Three-tier labeling system:

| Label | Meaning | Merge Path |
|-------|---------|-----------|
| `bot-fix/review-required` | Default for all bot PRs today | Human review |
| `bot-fix/auto-merge-eligible` | Single-file, p3-low, tests pass | Auto-merge after CI |
| `bot-fix/verified` | Post-merge CI passed | Issue closed automatically |
| `bot-fix/reverted` | Auto-merged but CI failed on main | Issue reopened, re-queued |

The fix-issue skill sets the appropriate label based on the fix scope and source issue priority.

### 4. Monitoring and Alerting

- Discord webhook notification on auto-merge (reuse existing pattern from `version-bump-and-release.yml`)
- Discord webhook notification on auto-revert (critical alert)
- Weekly summary: count of auto-merged, reverted, and review-required PRs (can be a simple `gh pr list` query in a scheduled workflow)

## Technical Approach

### Architecture

```
scheduled-bug-fixer.yml (daily 06:00 UTC)
  |
  +-- Select issue (existing)
  +-- claude-code-action: /soleur:fix-issue (existing)
  |     |
  |     +-- Creates bot-fix/<N>-<slug> branch
  |     +-- Makes fix, runs tests
  |     +-- Opens PR with [bot-fix] prefix
  |     +-- NEW: Sets bot-fix/auto-merge-eligible label if criteria met
  |
  +-- NEW: Auto-merge gate step
        |
        +-- Validates: 1 file changed, p3-low source, CI green
        +-- If eligible: gh pr merge --squash --auto
        +-- If not eligible: adds bot-fix/review-required label

post-merge-monitor.yml (on push to main)
  |
  +-- Detect bot-fix commit
  +-- Wait for CI
  +-- If CI fails: revert + alert
  +-- If CI passes: close issue + label
```

### Implementation Phases

#### Phase 1: Auto-Merge Eligibility in fix-issue Skill

**Files:** `plugins/soleur/skills/fix-issue/SKILL.md`

Update the skill to:
1. After opening the PR, evaluate auto-merge eligibility
2. If eligible (single-file, p3-low source, tests passed with no new failures): add `bot-fix/auto-merge-eligible` label to the PR
3. If not eligible: add `bot-fix/review-required` label

**Estimated effort:** 1 hour

#### Phase 2: Auto-Merge Gate in Workflow

**Files:** `.github/workflows/scheduled-bug-fixer.yml`

Add a post-fix step that:
1. Checks if the fix-issue agent created a PR (parse PR number from agent output or list open `bot-fix/*` PRs)
2. If PR exists and has `bot-fix/auto-merge-eligible` label: run `gh pr merge <number> --squash --auto`
3. Pre-create required labels (`bot-fix/auto-merge-eligible`, `bot-fix/review-required`, `bot-fix/verified`, `bot-fix/reverted`)

**Sharp edges:**
- The `gh pr merge --squash --auto` step runs **outside** the `claude-code-action` step, using `GITHUB_TOKEN`. This is fine because auto-merge queues the merge -- it doesn't push directly. The actual merge happens when GitHub's bot processes the queue, which respects ruleset bypass for the merge.
- The CLA Required ruleset has Integration bypass actors (IDs 262318, 1236702) already configured. Bot-fix PRs created by `claude-code-action` use the Claude App identity, which has bypass. Auto-merge will work because GitHub evaluates required status checks for the merge queue, not the actor identity.
- `allow_auto_merge` is already `true` on the repo (verified via API).

**Estimated effort:** 1 hour

#### Phase 3: Post-Merge CI Monitor

**Files:** `.github/workflows/post-merge-monitor.yml`

New workflow:

```yaml
name: "Post-Merge Monitor"

on:
  push:
    branches: [main]

permissions:
  contents: write
  pull-requests: write
  issues: write

jobs:
  monitor:
    if: startsWith(github.event.head_commit.message, '[bot-fix]')
    runs-on: ubuntu-latest
    timeout-minutes: 15

    steps:
      - name: Checkout
        uses: actions/checkout@<SHA> # v4.3.1
        with:
          fetch-depth: 2

      - name: Wait for CI
        # Wait for the CI workflow to complete on this commit
        # Poll ci.yml run status

      - name: Revert on failure
        if: # CI failed
        # git revert HEAD, push, create revert PR, auto-merge revert
        # Comment on source issue
        # Add bot-fix/reverted label

      - name: Verify on success
        if: # CI passed
        # Close source issue
        # Add bot-fix/verified label
        # Discord notification
```

**Sharp edges:**
- The post-merge monitor must NOT trigger on its own revert commits (infinite loop). Guard: `startsWith(github.event.head_commit.message, '[bot-fix]')` matches original bot-fix commits but not `Revert "[bot-fix]..."` commits.
- The revert PR also needs to pass CI. If the revert itself fails CI, that's a genuine emergency requiring human intervention. Do NOT auto-revert the revert.
- Token revocation: this workflow runs on `push` to main, not via `claude-code-action`, so it uses `GITHUB_TOKEN` which is valid for the entire workflow. No token revocation issue.
- The monitor must extract the source issue number from the commit message (`[bot-fix] Fix #N: ...` pattern) to comment on the issue.

**Estimated effort:** 2 hours

#### Phase 4: Monitoring and Alerting

**Files:** `.github/workflows/post-merge-monitor.yml` (add Discord step), `.github/workflows/scheduled-bug-fixer.yml` (add Discord step)

- On auto-merge: Discord notification with PR link and issue link
- On auto-revert: Discord critical alert with details
- Reuse webhook pattern from `version-bump-and-release.yml`

**Estimated effort:** 30 minutes

## Alternative Approaches Considered

### 1. PAT-Based Bot Identity

Creating a dedicated bot PAT to bypass CLA and merge restrictions. Rejected because the existing `claude-code-action` App installation already has CLA ruleset bypass (Integration IDs 262318, 1236702), and `allow_auto_merge` is enabled. Adding a PAT introduces secret management overhead for no additional capability.

### 2. Direct Push to Main (Skip PRs)

Having the bot push fixes directly to main instead of going through PRs. Rejected because:
- Loses the PR-based audit trail
- No opportunity for CI check before merge
- No revert PR mechanism (would need force-push revert, which is blocked by ruleset)
- Contradicts graduated autonomy principle

### 3. External CI Monitoring Service

Using a third-party service to monitor post-merge CI. Rejected because GitHub Actions `push` trigger on main already provides this capability with zero additional infrastructure.

### 4. Approval Bot (Separate GitHub App)

Creating a separate GitHub App to approve and merge bot PRs. Rejected as overengineered for v1. `gh pr merge --squash --auto` with existing repo settings is sufficient.

## Acceptance Criteria

### Functional Requirements

- [ ] `fix-issue` skill sets `bot-fix/auto-merge-eligible` or `bot-fix/review-required` label on created PRs
- [ ] Auto-merge eligibility requires: single file changed, p3-low source issue, all tests pass
- [ ] `scheduled-bug-fixer.yml` auto-merges eligible PRs via `gh pr merge --squash --auto`
- [ ] `post-merge-monitor.yml` detects bot-fix merges on main and waits for CI
- [ ] Post-merge CI failure triggers automatic revert PR, issue comment, and `bot-fix/reverted` label
- [ ] Post-merge CI success triggers issue closure and `bot-fix/verified` label
- [ ] Revert commits do NOT trigger the post-merge monitor (no infinite loop)
- [ ] Discord notifications on auto-merge and auto-revert events
- [ ] All new labels pre-created by workflows before use

### Non-Functional Requirements

- [ ] Post-merge monitor workflow completes within 15 minutes
- [ ] No additional secrets required (uses `GITHUB_TOKEN` and existing `ANTHROPIC_API_KEY`)
- [ ] Revert mechanism tested via `workflow_dispatch` trigger before relying on scheduled runs

### Quality Gates

- [ ] SpecFlow analysis completed on all workflow files
- [ ] Rollback tested end-to-end (force a failing test, merge, verify revert)
- [ ] Compound run captures learnings before commit

## Test Scenarios

### Acceptance Tests

- Given a bot-fix PR with 1 file changed from a p3-low issue and passing tests, when the auto-merge gate runs, then `gh pr merge --squash --auto` is executed
- Given a bot-fix PR with 2 files changed, when the auto-merge gate evaluates, then `bot-fix/review-required` label is added and no auto-merge occurs
- Given a bot-fix PR from a p2-medium issue (cascaded priority), when the auto-merge gate evaluates, then `bot-fix/review-required` label is added
- Given a bot-fix commit merged to main, when CI passes, then the source issue is closed with `bot-fix/verified` label
- Given a bot-fix commit merged to main, when CI fails, then a revert PR is created, auto-merged, and the source issue gets `bot-fix/reverted` label

### Regression Tests

- Given a revert commit (`Revert "[bot-fix]..."`) pushed to main, when the post-merge monitor triggers, then the job is skipped (no infinite revert loop)
- Given a bot-fix PR where the agent could not determine the source priority, when auto-merge gate runs, then it defaults to `bot-fix/review-required`
- Given no qualifying issues exist and the workflow runs, then it exits 0 with no action (existing behavior preserved)
- Given the Discord webhook secret is not configured, when a notification is attempted, then the step logs a warning and continues

### Edge Cases

- Given a bot-fix PR is auto-merged and the revert PR itself fails CI, when the monitor evaluates, then it does NOT attempt to revert the revert (stops at one level, logs critical alert)
- Given two bot-fix PRs merge in quick succession, when both trigger the monitor, then each processes independently (no race condition on issue labels)
- Given the source issue was closed manually before the monitor runs, when the monitor tries to close it, then the step succeeds idempotently

## Dependencies and Prerequisites

| Dependency | Status | Notes |
|-----------|--------|-------|
| Phase 1 (#370) -- Daily Triage | CLOSED | Shipped |
| Phase 2 (#376) -- Supervised Fix | CLOSED | Shipped via #385 |
| `allow_auto_merge` on repo | ENABLED | Verified via `gh api` |
| CLA bypass for Claude App | CONFIGURED | Integration IDs 262318, 1236702 in ruleset |
| Fix-issue skill validated | IN PROGRESS | 2+ weeks production runs recommended per #377 comment |
| Cost monitoring baseline | PENDING | Need to establish API spend baseline from Phase 2 runs |

## Risk Analysis and Mitigation

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Auto-merged fix breaks main | Medium | High | Post-merge monitor auto-reverts; revert happens within ~5 min |
| Infinite revert loop | Low | Critical | Commit message prefix guard: `[bot-fix]` does not match `Revert "[bot-fix]..."` |
| Bot-fix PR bypasses CLA check | N/A | N/A | Claude App already has CLA ruleset bypass |
| Revert PR itself fails CI | Low | High | Monitor stops at one revert level, sends critical Discord alert |
| Race condition: two bot merges overlap | Low | Medium | Concurrency group on post-merge-monitor prevents parallel runs |
| Agent over-scopes fix (edits multiple files) | Medium | Low | Mechanical check in auto-merge gate (1-file diff) catches this even if prompt constraint fails |
| Cost runaway from daily runs | Low | Medium | Existing `--max-turns 25` + `timeout-minutes: 20`; establish spend baseline |

## Rollback Plan

1. **Disable auto-merge:** Remove the auto-merge gate step from `scheduled-bug-fixer.yml`. Bot-fix PRs revert to human-review-only.
2. **Disable post-merge monitor:** Delete or disable `post-merge-monitor.yml`. No automatic revert capability, but also no risk of erroneous reverts.
3. **Emergency:** If a bad merge reaches main and the monitor fails to revert, manually run `git revert HEAD && git push origin main`.

## Semver Label Intent

`semver:minor` -- new autonomous merge capability and new workflow.

## Future Considerations

- **Expand scope:** After 4+ weeks of successful auto-merges with zero reverts, consider expanding to p2-medium single-file fixes
- **Multi-file autonomous fixes:** Requires mechanical enforcement (pre-merge hook checking file count) rather than prompt-only constraint
- **Cost dashboard:** Build a simple dashboard from workflow run logs to track per-run API cost
- **Confidence scoring:** Have the agent self-rate fix confidence (1-5) and only auto-merge high-confidence fixes

## References and Research

### Internal References

- Fix-issue skill: `plugins/soleur/skills/fix-issue/SKILL.md`
- Bug-fixer workflow: `.github/workflows/scheduled-bug-fixer.yml`
- CLA workflow: `.github/workflows/cla.yml`
- CI workflow: `.github/workflows/ci.yml`
- Version bump workflow: `.github/workflows/version-bump-and-release.yml` (Discord pattern)
- Phase 2 brainstorm: `knowledge-base/brainstorms/2026-03-02-supervised-bug-fix-agent-brainstorm.md`
- Phase 2 plan: `knowledge-base/plans/2026-03-03-feat-supervised-bug-fix-agent-plan.md`
- Learning -- bot-fix workflow patterns: `knowledge-base/learnings/2026-03-03-scheduled-bot-fix-workflow-patterns.md`
- Learning -- auto-push vs PR: `knowledge-base/learnings/2026-03-02-github-actions-auto-push-vs-pr-for-bot-content.md`
- Learning -- token revocation: `knowledge-base/learnings/2026-03-02-claude-code-action-token-revocation-breaks-persist-step.md`
- Learning -- CLA implementation: `knowledge-base/learnings/2026-02-26-cla-system-implementation-and-gdpr-compliance.md`
- Constitution CI rules: `knowledge-base/overview/constitution.md` (lines 84-113)

### Related Work

- Phase 1 (Daily Triage): #370
- Phase 2 (Supervised Fix): #376, PR #385
- Phase 3 Issue: #377
- Merged bot-fix PRs: #387, #388, #401
