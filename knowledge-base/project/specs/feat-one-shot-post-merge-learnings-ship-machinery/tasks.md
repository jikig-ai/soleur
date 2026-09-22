# Tasks: post-merge learnings from the ship-machinery refactor (PR #8474)

Plan: `knowledge-base/project/plans/2026-09-22-docs-post-merge-learnings-ship-machinery-plan.md`

## Phase 1: Setup

- 1.1 Re-read the plan's Research Reconciliation table. Every fact in the learnings comes from it,
  not from the brief (DC-1 in `decision-challenges.md`).
- 1.2 Record the baselines: ship `SKILL.md` byte count, and
  `git grep -l 'sync-pr-behind' -- '*.test.*' '*test*.sh'` (6 suites).

## Phase 2: Core Implementation

- 2.1 Write the new learning under `knowledge-base/project/learnings/workflow-issues/`, slug
  `the-test-my-merge-broke-merged-cleanly-so-it-was-never-in-my-conflict-list`, dated with the
  write date. Cover Deliverable 1's points, and use full paths for both `sync-pr-behind.test.sh` files.
- 2.2 Insert `## Recurrence: PR #8474, 2026-09-21` into
  `knowledge-base/project/learnings/2026-06-02-auto-merge-livelock-fast-moving-main.md` before
  `## Session Errors`. Make additions only; leave the frontmatter unchanged.
- 2.3 Add the one bullet to `plugins/soleur/skills/ship/SKILL.md` after the "A DIRTY that recurs on
  every landing" bullet. Fill in the learning path from 2.1.
- 2.4 Append the one sentence to the `NOT eligible` paragraph in
  `plugins/soleur/skills/ship/references/settle-then-admin-merge.md`.

## Phase 3: Testing

- 3.1 Run AC1 through AC7 exactly as written in the plan.
- 3.2 AC8: run every suite that
  `git grep -l -e 'settle-then-admin-merge' -e 'ship/SKILL.md' -- 'plugins/soleur/test/*.test.*'`
  lists, then `bash scripts/markdown-lint.sh` on the four changed files.
- 3.3 AC9: check the diff scope with `git diff --name-only origin/main...HEAD`.
