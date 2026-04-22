# Triage-time duplicate detection for workflow-fix issues

**Date:** 2026-04-22
**Context:** Issue #2526 (bug(ci): web-platform-release deploy-verify 120s timeout) was filed 7 minutes after issue #2519 was closed by PR #2523 — both describing the same CI false-negative and prescribing the same fix (`STATUS_POLL_MAX_ATTEMPTS` bump). The duplicate survived triage, spun up a `/soleur:one-shot` pipeline, created a worktree, a draft PR, and a deepen-plan subagent run before the planner caught it by reading the current state of the referenced workflow file.

## What was wasted

- Worktree creation + dependency install (~60s)
- Draft PR #2764 creation
- Planning subagent (127k tokens, 42 tool uses, 6min 43s wall)
- Deepen-plan research pass

Total: one full planning cycle to produce a "no changes needed" conclusion.

## Why existing rules didn't catch it

The rule `hr-before-asserting-github-issue-status` mandates verifying issue status via `gh issue view` + knowledge-base before asserting — but it fires on *assertions about existing state*, not on the decision to start work on an open issue. An issue being `state: OPEN` is not a reliable signal that it still needs fixing; the fix may have landed without automation closing the issue.

## Heuristic to apply at triage boundary

When an issue prescribes a concrete fix to a specific file (workflow, config, terraform, doc), `/soleur:triage` and `/soleur:one-shot` Step 0 should:

1. **Extract the file path(s)** from the issue body (`.github/workflows/*.yml`, `apps/*/infra/*.tf`, etc.).
2. **Grep the current main state** for the symbol or value the fix targets:
   - Issue says "raise `STATUS_POLL_MAX_ATTEMPTS` from 24 to at least 60" → `git show main:<path> | grep STATUS_POLL_MAX_ATTEMPTS`
   - If the current value already matches the proposed fix, the issue is stale.
3. **Search closed PRs for the file path** in the window between issue creation and now:

   ```bash
   gh pr list --state merged --search "<path> merged:>=<issue-created-at>" --json number,title,mergedAt
   ```

4. **If either check indicates the fix is live,** close as duplicate before spinning up a worktree.

## The grep-based catch for #2526

One command would have caught this at triage:

```bash
$ git show main:.github/workflows/web-platform-release.yml | grep -E "STATUS_POLL_(MAX_ATTEMPTS|INTERVAL)"
          STATUS_POLL_MAX_ATTEMPTS: 60
          STATUS_POLL_INTERVAL_S: 5
```

The issue proposed bumping 24 → 60. Main already has 60. Duplicate detected.

## Recommended gate placement

Not in `/soleur:brainstorm` (too late — planning has already started) and not in `/soleur:plan` (too late — worktree exists). The cheapest detection point is `/soleur:triage` before any worktree work, or `/soleur:one-shot` Step 0a (before worktree creation).

## Cross-references

- AGENTS.md rule `hr-before-asserting-github-issue-status` — complementary but scoped to assertions, not triage decisions.
- Issue #2519 / PR #2523 — the original fix.
- Issue #2526 — the duplicate this learning came from.
