---
title: "feat: Scheduled Ship-Merge Workflow"
type: feat
date: 2026-03-05
---

# feat: Scheduled Ship-Merge Workflow

## Overview

Create a GitHub Actions workflow (`scheduled-ship-merge.yml`) that runs `soleur:ship --headless` on qualifying PRs daily. One PR per run, label-based deduplication, age + CI + opt-out filtering.

## Problem Statement / Motivation

- PRs accumulate waiting for manual `/ship` invocation
- The `--headless` flag convention is implemented (ship, compound, work) but has no CI consumer
- Manual shipping is repeatable, mechanical work consuming developer attention
- Descoped from #393 (headless mode) as follow-up work

## Proposed Solution

A thin workflow YAML that handles PR selection in bash, checks out the PR branch, then invokes `skill: soleur:ship --headless` via `claude-code-action`. Follows the `scheduled-bug-fixer.yml` template.

### Workflow Architecture

```
Cron (09:00 UTC daily) or workflow_dispatch
  |
  v
Pre-create labels (bash, idempotent)
  |
  v
Select qualifying PR (bash + gh CLI + jq)
  |-- No qualifying PR → exit 0
  |-- PR found → apply ship/scheduled label
  |
  v
Setup Bun (oven-sh/setup-bun)
  |
  v
gh pr checkout <number>
  |
  v
claude-code-action: skill: soleur:ship --headless
  |
  v
Post step (if: always())
  |-- PR state == MERGED → remove ship/scheduled, exit 0
  |-- Job failed → apply ship/failed + PR comment with run URL
  |-- Job succeeded but not merged → remove ship/scheduled (ship updated PR but didn't merge yet)
```

### PR Selection Query

```bash
CUTOFF=$(date -u -d '24 hours ago' +%Y-%m-%dT%H:%M:%SZ)
PR=$(gh pr list \
  --state open \
  --json number,createdAt,isDraft,labels,statusCheckRollup,baseRefName \
  --jq "
    [.[] | select(
      .isDraft == false and
      .baseRefName == \"main\" and
      (.createdAt < \"$CUTOFF\") and
      (.labels | map(.name) |
        (index(\"ship/scheduled\") | not) and
        (index(\"ship/failed\") | not) and
        (index(\"no-auto-ship\") | not)) and
      (.statusCheckRollup | length > 0) and
      (.statusCheckRollup | all(.[];
        .status == \"COMPLETED\" and .conclusion == \"SUCCESS\"))
    )] | sort_by(.createdAt) | .[0].number // empty
  ")
```

Key design decisions in the query:
- `isDraft == false` — drafts excluded
- `baseRefName == "main"` — only PRs targeting main
- `createdAt < CUTOFF` — 24+ hours old (ISO 8601 string comparison works)
- Label exclusion via jq (not `--label` flag, which is inclusion-only)
- `statusCheckRollup | length > 0` — PRs with zero CI checks excluded
- `all(.[]; .status == "COMPLETED" and .conclusion == "SUCCESS")` — all checks must pass

## Technical Considerations

### Ship Skill in CI Context

Ship was designed for local worktree-based development. In Actions:

- **Phase 0 (worktree detection):** Finds no worktrees, proceeds normally. Agent is on the feature branch via `gh pr checkout`.
- **Phase 2 (compound):** Runs with no session context. May produce low-quality learnings. Acceptable for v1 — compound's existing "no artifacts" path handles this.
- **Phase 4 (tests):** Requires `setup-bun`. Agent can handle `bun install` if dependencies missing.
- **Phase 6 (PR update):** Finds existing PR on current branch, updates title/body/semver. Works as designed.
- **Phase 6.5 (conflict resolution):** If conflicts can't be auto-resolved, headless ship aborts. Ship SKILL.md already has this behavior ("abort pipeline, log conflicting files").
- **Phase 7 (auto-merge + cleanup):** `cleanup-merged` finds no worktrees, exits cleanly.

### Post-Step Success Detection

`claude-code-action` exits 0 even when ship internally aborts. The post step must check **PR state** as the source of truth:
- `gh pr view <number> --json state --jq .state == "MERGED"` → success
- Otherwise → check job status to determine failure vs partial completion

### Known Limitations

1. **No branch protection on main.** If PreToolUse hooks don't fire in Actions (#419 unresolved), the agent could theoretically commit to main. Mitigation: use `workflow_dispatch` only until #419 is resolved or branch protection is added.
2. **Compound quality in CI.** Without session context, compound captures may be low-quality. Acceptable for v1.
3. **Stale `ship/scheduled` labels.** If the runner crashes between label application and the post step, the label persists. Requires manual cleanup. File a follow-up issue if this occurs in practice.
4. **Race with manual `/ship`.** A concurrent manual ship on the same PR may cause one to fail. Documented, accepted risk.

## Acceptance Criteria

- [ ] `.github/workflows/scheduled-ship-merge.yml` created
- [ ] PR selection query filters: not draft, 24h+ old, CI passing, correct labels, targets main
- [ ] `workflow_dispatch` trigger with optional `pr_number` override input
- [ ] `ship/scheduled` label applied at processing start
- [ ] Post step: checks PR state (MERGED = success, else failure handling)
- [ ] `ship/failed` label + PR comment with Actions run URL on failure
- [ ] `setup-bun` step before `claude-code-action`
- [ ] Concurrency group `schedule-ship-merge`, cancel-in-progress false
- [ ] `--max-turns 40`, `timeout-minutes: 30`, model `claude-sonnet-4-6`
- [ ] Pre-create labels `ship/scheduled`, `ship/failed`, `no-auto-ship` idempotently
- [ ] Security comment block at top of file (same pattern as bug-fixer)
- [ ] GITHUB_OUTPUT writes sanitized with `tr -d '\n\r'`

## Test Scenarios

- Given no qualifying PRs exist, when the workflow runs, then it exits 0 with "No qualifying PRs found"
- Given a qualifying PR exists (24h+ old, CI passing, no exclusion labels, not draft, targets main), when the workflow runs, then ship --headless is invoked on that PR
- Given a PR has `no-auto-ship` label, when the workflow runs, then that PR is skipped
- Given a PR has `ship/failed` label, when the workflow runs, then that PR is skipped
- Given a PR is a draft, when the workflow runs, then that PR is skipped
- Given a PR has pending CI checks, when the workflow runs, then that PR is skipped
- Given a PR targets a non-main branch, when the workflow runs, then that PR is skipped
- Given ship --headless succeeds and the PR is merged, when the post step runs, then `ship/scheduled` label is removed
- Given ship --headless fails, when the post step runs, then `ship/failed` label is applied and a PR comment is posted
- Given someone manually merges the PR during the ship run, when the post step runs, then it detects MERGED state and removes `ship/scheduled` without applying `ship/failed`
- Given `workflow_dispatch` with `pr_number` override, when the workflow runs, then the override PR is selected directly (bypassing the query)

## Dependencies & Risks

| Risk | Severity | Mitigation |
|------|----------|------------|
| PreToolUse hooks unverified in Actions (#419) | HIGH | Use `workflow_dispatch` only until resolved. Branch protection provides server-side guardrail. |
| Ship's compound produces low-quality output | MEDIUM | Acceptable for v1. Phase 2 handles "no artifacts" path. |
| Stale `ship/scheduled` labels from crashes | LOW | Manual cleanup. File follow-up if recurring. |
| `claude-code-action` exits 0 on ship abort | HIGH | Post step uses PR state (MERGED) as success signal. |
| `gh pr list --label` is inclusion-only | HIGH | Use jq post-filtering for label exclusion. |

## References & Research

### Internal References

- Bug-fixer workflow (template): `.github/workflows/scheduled-bug-fixer.yml`
- Ship skill: `plugins/soleur/skills/ship/SKILL.md`
- Headless mode plan: `knowledge-base/plans/2026-03-03-feat-headless-mode-repeatable-workflows-plan.md`
- Brainstorm: `knowledge-base/brainstorms/2026-03-05-scheduled-ship-merge-brainstorm.md`
- Spec: `knowledge-base/specs/feat-scheduled-ship-merge/spec.md`
- GITHUB_OUTPUT sanitization: commit `6f8a06f`
- Schedule template: `plugins/soleur/skills/schedule/SKILL.md`

### Related Work

- Issue: #417
- Parent issue: #393 (headless mode)
- Prerequisite: #419 (PreToolUse hooks verification)
- Sibling: #418 (scheduled-compound-review)
- `claude-code-action` SHA: `64c7a0ef71df67b14cb4471f4d9c8565c61042bf` (v1)
- `actions/checkout` SHA: `34e114876b0b11c390a56381ad16ebd13914f8d5` (v4.3.1)
- `oven-sh/setup-bun` SHA: `3d267786b128fe76c2f16a390aa2448b815359f3` (v2)
