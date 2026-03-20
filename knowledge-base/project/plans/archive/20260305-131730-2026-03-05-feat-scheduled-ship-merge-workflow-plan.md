---
title: "feat: Scheduled Ship-Merge Workflow"
type: feat
date: 2026-03-05
---

# feat: Scheduled Ship-Merge Workflow

## Overview

Create a GitHub Actions workflow (`scheduled-ship-merge.yml`) that runs `soleur:ship --headless` on qualifying PRs. One PR per run, `workflow_dispatch` trigger for v1 (cron added after #419 resolves).

## Problem Statement / Motivation

- PRs accumulate waiting for manual `/ship` invocation
- The `--headless` flag convention is implemented (ship, compound, work) but has no CI consumer
- Manual shipping is repeatable, mechanical work consuming developer attention
- Descoped from #393 (headless mode) as follow-up work

## Proposed Solution

A thin workflow YAML that handles PR selection in bash, checks out the PR branch, then invokes `skill: soleur:ship --headless` via `claude-code-action`. Follows the `scheduled-bug-fixer.yml` template.

### Workflow Architecture

```
workflow_dispatch (with optional pr_number override)
  |
  v
Pre-create labels (bash, idempotent)
  |
  v
Select qualifying PR (bash + gh CLI + jq)
  |-- No qualifying PR -> exit 0
  |-- PR found -> continue
  |
  v
Verify required checks pass (gh pr checks --required)
  |-- Checks failing -> exit 0
  |
  v
Setup Bun + bun install
  |
  v
gh pr checkout <number>
  |
  v
claude-code-action: skill: soleur:ship --headless
  |
  v
Post step (if: always())
  |-- PR state == MERGED -> exit 0
  |-- PR state != MERGED -> apply ship/failed + PR comment with run URL
```

### PR Selection Query

```bash
CUTOFF=$(date -u -d '24 hours ago' +%Y-%m-%dT%H:%M:%SZ)
PR=$(gh pr list \
  --state open \
  --json number,createdAt,isDraft,labels,baseRefName \
  --jq "
    [.[] | select(
      .isDraft == false and
      .baseRefName == \"main\" and
      (.createdAt < \"$CUTOFF\") and
      (.labels | map(.name) |
        (index(\"ship/failed\") | not) and
        (index(\"no-auto-ship\") | not))
    )] | sort_by(.createdAt) | .[0].number // empty
  ")
```

After selection, verify required checks pass:

```bash
gh pr checks "$PR" --required --fail-fast 2>/dev/null || { echo "Required checks not passing"; exit 0; }
```

This defers CI gating to GitHub's own notion of "required checks" rather than reimplementing it in jq.

## Acceptance Criteria

- [ ] `.github/workflows/scheduled-ship-merge.yml` created
- [ ] PR selection: not draft, 24h+ old, targets main, no `ship/failed` or `no-auto-ship` labels
- [ ] Post-selection CI gate via `gh pr checks --required`
- [ ] Post step uses PR state (MERGED vs. not) as success signal
- [ ] `workflow_dispatch` trigger with optional `pr_number` override

## Test Scenarios

- Given no qualifying PRs exist, when the workflow runs, then it exits 0
- Given a qualifying PR exists, when the workflow runs, then ship --headless is invoked
- Given ship succeeds and the PR merges, when the post step runs, then it exits cleanly
- Given ship fails, when the post step runs, then `ship/failed` label + PR comment are applied

## Dependencies & Risks

| Risk | Severity | Mitigation |
|------|----------|------------|
| PreToolUse hooks unverified in Actions (#419) | HIGH | `workflow_dispatch` only for v1. Add cron after #419 resolves. |
| `claude-code-action` exits 0 on ship abort | HIGH | Post step uses PR state (MERGED) as success signal. |

## References & Research

### Internal References

- Bug-fixer workflow (template): `.github/workflows/scheduled-bug-fixer.yml`
- Ship skill: `plugins/soleur/skills/ship/SKILL.md`
- Headless mode plan: `knowledge-base/project/plans/2026-03-03-feat-headless-mode-repeatable-workflows-plan.md`
- Brainstorm: `knowledge-base/project/brainstorms/2026-03-05-scheduled-ship-merge-brainstorm.md`
- Spec: `knowledge-base/project/specs/feat-scheduled-ship-merge/spec.md`
- GITHUB_OUTPUT sanitization: commit `6f8a06f`

### Related Work

- Issue: #417
- Parent issue: #393 (headless mode)
- Prerequisite: #419 (PreToolUse hooks verification)
- Sibling: #418 (scheduled-compound-review)
- `claude-code-action` SHA: `64c7a0ef71df67b14cb4471f4d9c8565c61042bf` (v1)
- `actions/checkout` SHA: `34e114876b0b11c390a56381ad16ebd13914f8d5` (v4.3.1)
- `oven-sh/setup-bun` SHA: `3d267786b128fe76c2f16a390aa2448b815359f3` (v2)
