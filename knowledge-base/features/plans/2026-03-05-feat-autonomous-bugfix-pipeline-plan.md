---
title: "feat: full autonomous bug-fix pipeline"
type: feat
date: 2026-03-05
---

## Enhancement Summary

**Deepened on:** 2026-03-05
**Sections enhanced:** 7
**Research sources:** Web research (GitHub Actions revert patterns, workflow_run trigger, merge queue), Context7, institutional learnings (6 relevant), repo analysis (9 workflow files, 2 rulesets, 5 merged bot-fix PRs)

### Key Improvements

1. **Use `workflow_run` trigger instead of polling** -- the post-merge monitor should trigger via `workflow_run` on CI completion rather than polling `gh run list`, eliminating timing races and reducing workflow minutes
2. **Direct revert push instead of revert PR** -- the revert should push directly to main (matching the `version-bump-and-release.yml` pattern) rather than creating a revert PR that would itself need to pass CLA/CI gates; `GITHUB_TOKEN` with existing `contents: write` permission suffices for reverts
3. **Squash commit message format differs from branch commit format** -- `gh pr merge --squash` uses the PR title as the commit message, so the `[bot-fix]` prefix detection in the post-merge monitor must match against the squashed PR title, not the branch commit messages
4. **`GITHUB_TOKEN` cascade limitation applies to auto-merge too** -- PRs created by `GITHUB_TOKEN` don't trigger `pull_request` events, but PRs created by `claude-code-action` (App token) DO trigger them; the auto-merge gate step must run the `gh pr merge` command, not the agent
5. **Add `workflow_dispatch` trigger to post-merge-monitor for testing** -- the monitor can only be tested on actual main pushes; a manual dispatch with a commit SHA input enables dry-run testing

### New Considerations Discovered

- The revert commit message must NOT start with `[bot-fix]` to prevent infinite loops; use `Revert "[bot-fix] ..."` (GitHub's default revert message format) or a custom prefix like `[bot-revert]`
- `gh run watch --exit-status` has known issues in GitHub-hosted runners (cli/cli#8194); prefer `workflow_run` trigger over polling
- The CLA Required ruleset's `strict_required_status_checks_policy: false` means status checks don't require the branch to be up-to-date, which is favorable for auto-merge

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

A new workflow triggered via `workflow_run` on CI completion (not `push` to main) that:

1. Filters to only process CI runs triggered by bot-fix commits (squashed PR title starts with `[bot-fix]`)
2. Checks CI conclusion (`success` or `failure`)
3. If CI fails:
   - Reverts the commit directly on main: `git revert HEAD --no-edit && git push origin main`
   - Comments on the original issue: "Autonomous fix was reverted due to CI failure on main"
   - Removes `bot-fix/attempted` label so the issue re-enters the queue (with a `bot-fix/reverted` label to track history)
4. If CI passes: adds `bot-fix/verified` label to the source issue, then closes it

### Research Insight: `workflow_run` over polling

Using `workflow_run` instead of polling `gh run list` eliminates timing races where the CI run hasn't been created yet when the monitor checks. The `workflow_run` event fires only after the target workflow completes, providing the conclusion directly in `github.event.workflow_run.conclusion`. This also avoids consuming workflow minutes on sleep loops.

### Research Insight: Direct revert push over revert PR

Creating a revert PR would require it to pass CLA checks and CI before merging -- adding delay to an urgent rollback. The version-bump-and-release workflow already pushes directly to main using `GITHUB_TOKEN`, establishing precedent. For reverts (which are mechanically generated, not human-authored), the PR audit trail is unnecessary. The revert commit itself is the audit trail.

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

### Research Insight: Auto-merge gate must run OUTSIDE claude-code-action

The `gh pr merge --squash --auto` command must execute in a separate workflow step after `claude-code-action` completes, not inside the agent prompt. Reasons:

1. **Token identity matters for auto-merge.** The auto-merge is queued by `GITHUB_TOKEN` (acting as `github-actions[bot]`). GitHub evaluates required status checks against the PR, not the merge requestor. Since `allow_auto_merge` is enabled and the CLA ruleset has `strict_required_status_checks_policy: false`, auto-merge will proceed once CI passes.

2. **claude-code-action token revocation.** The agent's App installation token is revoked in post-step cleanup. If the auto-merge is queued inside the agent, and the merge hasn't completed before token revocation, the merge may silently fail. Running `gh pr merge` in a subsequent step uses `GITHUB_TOKEN` which persists for the entire workflow.

3. **PR number discovery.** The agent creates the PR during its run. The workflow step after the agent can discover the PR via:
   ```bash
   PR_NUM=$(gh pr list --head "bot-fix/" --state open --json number --jq '.[0].number // empty')
   ```

### Research Insight: CLA check behavior with auto-merge

The CLA Required ruleset's `cla-check` status is required for merging to main. Bot-fix PRs created by `claude-code-action` trigger `pull_request_target`, which runs the CLA workflow. The CLA allowlist includes `dependabot[bot]` and `github-actions[bot]` but NOT the Claude App. However, the CLA ruleset has the Claude App as a bypass actor (Integration ID 262318 or 1236702), so the `cla-check` requirement is bypassed entirely for bot-fix PRs.

**Estimated effort:** 1 hour

#### Phase 3: Post-Merge CI Monitor

**Files:** `.github/workflows/post-merge-monitor.yml`

New workflow using `workflow_run` trigger (preferred over `push` + polling):

```yaml
name: "Post-Merge Monitor"

on:
  workflow_run:
    workflows: ["CI"]
    types: [completed]
    branches: [main]
  workflow_dispatch:
    inputs:
      commit_sha:
        description: 'Commit SHA to evaluate (dry-run testing)'
        required: false
        type: string

permissions:
  contents: write
  issues: write

jobs:
  monitor:
    # Only process CI runs for bot-fix commits on main
    if: >-
      (github.event_name == 'workflow_dispatch') ||
      (github.event.workflow_run.head_branch == 'main' &&
       startsWith(github.event.workflow_run.head_commit.message, '[bot-fix]'))
    runs-on: ubuntu-latest
    timeout-minutes: 10

    steps:
      - name: Checkout
        uses: actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5 # v4.3.1
        with:
          fetch-depth: 2
          token: ${{ github.token }}

      - name: Extract issue number
        id: extract
        env:
          COMMIT_MSG: ${{ github.event.workflow_run.head_commit.message || '' }}
          GH_TOKEN: ${{ github.token }}
        run: |
          # Extract issue number from squashed commit: "[bot-fix] Fix title (#PR)" -> find Ref #N in PR body
          # Or from commit message: "[bot-fix] Fix #N: description"
          ISSUE_NUM=$(echo "$COMMIT_MSG" | grep -oP '#\K\d+' | head -1)
          if [[ -z "$ISSUE_NUM" ]]; then
            echo "::warning::Could not extract issue number from commit message"
            exit 0
          fi
          echo "issue=$ISSUE_NUM" >> "$GITHUB_OUTPUT"

      - name: Revert on CI failure
        if: >-
          github.event.workflow_run.conclusion == 'failure' &&
          steps.extract.outputs.issue
        env:
          GH_TOKEN: ${{ github.token }}
          ISSUE_NUM: ${{ steps.extract.outputs.issue }}
        run: |
          # Configure git for revert commit
          git config user.name "github-actions[bot]"
          git config user.email "41898282+github-actions[bot]@users.noreply.github.com"

          # Revert the bot-fix commit directly on main
          git revert --no-edit HEAD
          git push origin main

          # Comment on source issue
          gh issue comment "$ISSUE_NUM" --body "**Bot Fix Reverted**

          The autonomous fix was merged but caused CI failure on main.
          The commit has been automatically reverted.

          This issue is available for another fix attempt or manual investigation."

          # Label management
          gh issue edit "$ISSUE_NUM" --add-label "bot-fix/reverted"
          gh issue edit "$ISSUE_NUM" --remove-label "bot-fix/attempted" 2>/dev/null || true

      - name: Verify on CI success
        if: >-
          github.event.workflow_run.conclusion == 'success' &&
          steps.extract.outputs.issue
        env:
          GH_TOKEN: ${{ github.token }}
          ISSUE_NUM: ${{ steps.extract.outputs.issue }}
        run: |
          gh issue edit "$ISSUE_NUM" --add-label "bot-fix/verified"
          gh issue close "$ISSUE_NUM" --comment "Autonomous fix verified -- CI passed on main. Closing."

      - name: Discord alert on revert
        if: >-
          github.event.workflow_run.conclusion == 'failure' &&
          steps.extract.outputs.issue
        env:
          DISCORD_WEBHOOK_URL: ${{ secrets.DISCORD_WEBHOOK_URL }}
          ISSUE_NUM: ${{ steps.extract.outputs.issue }}
          COMMIT_SHA: ${{ github.event.workflow_run.head_sha }}
        run: |
          if [[ -z "$DISCORD_WEBHOOK_URL" ]]; then
            echo "DISCORD_WEBHOOK_URL not set, skipping"
            exit 0
          fi
          REPO_URL="${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}"
          MESSAGE=$(printf '**[ALERT] Bot-fix reverted on main**\n\nIssue: %s/issues/%s\nCommit: %s/commit/%s\n\nCI failed after autonomous merge. Commit has been auto-reverted.' \
            "$REPO_URL" "$ISSUE_NUM" "$REPO_URL" "$COMMIT_SHA")
          PAYLOAD=$(jq -n \
            --arg content "$MESSAGE" \
            --arg username "Sol" \
            --arg avatar_url "https://raw.githubusercontent.com/jikig-ai/soleur/main/plugins/soleur/docs/images/logo-mark-512.png" \
            '{content: $content, username: $username, avatar_url: $avatar_url, allowed_mentions: {parse: []}}')
          curl -s -o /dev/null -w "%{http_code}" \
            -H "Content-Type: application/json" \
            -d "$PAYLOAD" \
            "$DISCORD_WEBHOOK_URL" || echo "::warning::Discord notification failed"
```

**Sharp edges:**
- **Infinite loop prevention:** The `workflow_run` trigger fires when CI completes on main. The revert commit pushed to main will trigger a new CI run, which will trigger another `workflow_run`. But the revert commit message starts with `Revert "[bot-fix]..."` (GitHub's default format), NOT `[bot-fix]`, so the `startsWith` guard blocks it. If using a custom revert message, ensure it does NOT start with `[bot-fix]`.
- **Squashed commit message format:** `gh pr merge --squash` uses the PR title as the first line of the commit message. Since the PR title starts with `[bot-fix]`, the squashed commit message will too. This is the string the `startsWith` guard matches against.
- **`workflow_run` only triggers if the workflow file exists on main.** This means the post-merge-monitor workflow must be merged to main before it can be tested via `workflow_run`. The `workflow_dispatch` input provides a testing escape hatch.
- **Direct push for reverts:** The revert pushes directly to main using `GITHUB_TOKEN`. The CLA Required ruleset requires the `cla-check` status, but `GITHUB_TOKEN` pushes bypass required status checks when the actor has `contents: write` permission on the repo. Verify this works by testing with `workflow_dispatch` after initial merge.
- **Issue number extraction:** The squashed commit message format is `[bot-fix] PR Title (#PR_NUMBER)`. The source issue number may be in the PR body (`Ref #N`) rather than the commit message title. The extraction step should first check the commit message, then fall back to querying the PR body via `gh api repos/{owner}/{repo}/commits/{sha}/pulls`.
- **Concurrency:** No concurrency group needed -- `workflow_run` events are serialized by GitHub (one CI run completes before the next starts on the same branch).
- **Token revocation:** Not applicable -- this workflow uses `GITHUB_TOKEN`, not `claude-code-action`.

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

- [x] `fix-issue` skill sets `bot-fix/auto-merge-eligible` or `bot-fix/review-required` label on created PRs
- [x] Auto-merge eligibility requires: single file changed, p3-low source issue, all tests pass
- [x] `scheduled-bug-fixer.yml` auto-merges eligible PRs via `gh pr merge --squash --auto`
- [x] `post-merge-monitor.yml` detects bot-fix merges on main and waits for CI
- [x] Post-merge CI failure triggers automatic revert PR, issue comment, and `bot-fix/reverted` label
- [x] Post-merge CI success triggers issue closure and `bot-fix/verified` label
- [x] Revert commits do NOT trigger the post-merge monitor (no infinite loop)
- [x] Discord notifications on auto-merge and auto-revert events
- [x] All new labels pre-created by workflows before use

### Non-Functional Requirements

- [x] Post-merge monitor workflow completes within 15 minutes
- [x] No additional secrets required (uses `GITHUB_TOKEN` and existing `ANTHROPIC_API_KEY`)
- [ ] Revert mechanism tested via `workflow_dispatch` trigger before relying on scheduled runs

### Quality Gates

- [ ] SpecFlow analysis completed on all workflow files
- [ ] Rollback tested end-to-end (force a failing test, merge, verify revert)
- [x] Compound run captures learnings before commit

## Test Scenarios

### Acceptance Tests

- Given a bot-fix PR with 1 file changed from a p3-low issue and passing tests, when the auto-merge gate runs, then `gh pr merge --squash --auto` is executed
- Given a bot-fix PR with 2 files changed, when the auto-merge gate evaluates, then `bot-fix/review-required` label is added and no auto-merge occurs
- Given a bot-fix PR from a p2-medium issue (cascaded priority), when the auto-merge gate evaluates, then `bot-fix/review-required` label is added
- Given a bot-fix commit merged to main, when CI passes, then the source issue is closed with `bot-fix/verified` label
- Given a bot-fix commit merged to main, when CI fails, then the commit is reverted directly on main and the source issue gets `bot-fix/reverted` label

### Regression Tests

- Given a revert commit (`Revert "[bot-fix]..."`) pushed to main, when the post-merge monitor triggers, then the job is skipped (no infinite revert loop)
- Given a bot-fix PR where the agent could not determine the source priority, when auto-merge gate runs, then it defaults to `bot-fix/review-required`
- Given no qualifying issues exist and the workflow runs, then it exits 0 with no action (existing behavior preserved)
- Given the Discord webhook secret is not configured, when a notification is attempted, then the step logs a warning and continues

### Edge Cases

- Given a bot-fix PR is auto-merged and the revert push's CI run completes, when the monitor checks the commit message, then it does NOT match `[bot-fix]` (revert uses `Revert "[bot-fix]..."`) and skips processing
- Given two bot-fix PRs merge in quick succession, when both trigger the monitor, then each processes independently (no race condition on issue labels)
- Given the source issue was closed manually before the monitor runs, when the monitor tries to close it, then `gh issue close` succeeds idempotently (closing an already-closed issue is a no-op)
- Given the commit message does not contain an issue number, when the extract step runs, then it exits 0 with a warning (no revert or close action taken)
- Given `GITHUB_TOKEN` push is blocked by a ruleset not yet discovered, when the revert push fails, then the step exits non-zero and the workflow fails visibly (no silent failure)
- Given the `workflow_run` event fires but CI was triggered by a non-bot-fix push to main, when the monitor evaluates, then the `startsWith` guard skips processing

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
| Auto-merged fix breaks main | Medium | High | Post-merge monitor auto-reverts within ~5 min of CI completion |
| Infinite revert loop | Low | Critical | Commit message prefix guard: `[bot-fix]` does not match `Revert "[bot-fix]..."` |
| Bot-fix PR bypasses CLA check | N/A | N/A | Claude App already has CLA ruleset bypass (Integration IDs in ruleset) |
| Revert push itself fails CI | Low | High | Monitor only fires on `[bot-fix]`-prefixed commits; revert commit has different prefix, so no recursive monitoring |
| Race condition: two bot merges overlap | Very Low | Medium | Only 1 issue per scheduled run; concurrency group on bug-fixer prevents parallel runs |
| Agent over-scopes fix (edits multiple files) | Medium | Low | Mechanical check in auto-merge gate (1-file diff via `gh pr diff --stat`) catches this even if prompt constraint fails |
| Cost runaway from daily runs | Low | Medium | Existing `--max-turns 25` + `timeout-minutes: 20`; 1 issue per run caps at ~$0.50/day at Sonnet rates |
| `workflow_run` doesn't trigger until workflow exists on main | Certain (bootstrap) | Low | Merge workflow file first (human PR), then test via `workflow_dispatch` |
| Direct revert push blocked by branch protection | Low | Medium | `GITHUB_TOKEN` with `contents: write` can push to main; Force Push Prevention ruleset only blocks deletion and non-fast-forward, not normal pushes |
| Squash commit message doesn't contain issue number | Medium | Medium | Fall back to `gh api repos/{owner}/{repo}/commits/{sha}/pulls` to find PR, then parse `Ref #N` from PR body |

### Research Insight: Revert commit idempotency

If the post-merge monitor's revert push fails mid-flight (network, runner crash), the next CI run on main will still pass (the bad commit is still there), and the next `workflow_run` event will fire, re-triggering the monitor. However, `git revert HEAD` on the second attempt would try to revert a different commit. Guard: check if the current HEAD commit message starts with `[bot-fix]` before reverting, and skip if it doesn't (someone else may have pushed in between).

### Research Insight: GITHUB_TOKEN push and recursive workflow triggering

Pushes made with `GITHUB_TOKEN` do NOT trigger `push` or `pull_request` events (GitHub's anti-recursion protection). This is actually beneficial: the revert push will NOT trigger another `push`-triggered CI run. However, the CI workflow triggers on `push: branches: [main]` AND `pull_request`. The revert push using `GITHUB_TOKEN` will be invisible to CI. This means:
- The revert itself is NOT CI-tested before landing on main
- This is acceptable because `git revert` is mechanically correct (it applies the inverse diff)
- If the revert somehow introduces issues, the next human PR will catch them in CI

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

### External References

- Auto-revert on CI failure pattern: https://some-natalie.dev/blog/undo-commit-on-failure/
- GitHub community discussion on automated revert: https://github.com/orgs/community/discussions/140805
- `gh run watch` runner issues: https://github.com/cli/cli/issues/8194
- `workflow_run` event documentation: https://docs.github.com/actions/using-workflows/triggering-a-workflow
- Managing merge queues: https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/configuring-pull-request-merges/managing-a-merge-queue

### Related Work

- Phase 1 (Daily Triage): #370
- Phase 2 (Supervised Fix): #376, PR #385
- Phase 3 Issue: #377
- Merged bot-fix PRs: #387, #388, #401
