---
lane: procedural
plan: knowledge-base/project/plans/2026-05-21-fix-stale-issue-auto-approve-trusted-applies-4221-plan.md
issue: 4221
---

# Tasks — fix: close stale bot-filed issue #4221

This is a triage-cleanup PR. No source files are edited; a single learning file is added and one GitHub issue is closed.

## Phase 0 — Verify the stale-issue claim (pre-merge, ~30 seconds)

- [x] 0.1 Confirm the workflow file is absent on `main`:
  ```bash
  git ls-files .github/workflows/ | grep -i approve   # must be empty
  ```
- [x] 0.2 Confirm zero registered presence in GitHub Actions API:
  ```bash
  gh api repos/jikig-ai/soleur/actions/workflows --paginate \
    | jq '.workflows[] | select(.path|test("auto-approve|trusted"))'   # must be empty
  ```
- [x] 0.3 Confirm no runs after PR #4220 merge:
  ```bash
  gh run list --workflow=auto-approve-trusted-applies.yml --limit 100 --json createdAt \
    | jq '[.[] | select(.createdAt > "2026-05-21T08:34:57Z")] | length'   # must be 0
  ```
- [x] 0.4 Confirm latest push to main does NOT fire this workflow:
  ```bash
  gh run list --limit 50 --branch=main --json workflowName,createdAt \
    | jq '[.[] | select(.workflowName | test("auto-approve|trusted"; "i"))]'   # must be []
  ```
  (Verified: 2 entries returned are both pre-deletion timestamps 08:23Z and 08:29Z, < 08:34:57Z merge.)

## Phase 1 — Write the learning file

- [x] 1.1 Create `knowledge-base/project/learnings/2026-05-21-bot-filed-issue-races-prior-resolution-pr.md` with the structure prescribed in the plan body §"Phase 1 — Write the learning file" (YAML frontmatter, Problem, Why existing rules missed it, Heuristic with `git ls-files` + `gh pr list --search` recipe, Sharp Edge, References).
- [x] 1.2 Cross-reference `2026-04-22-triage-time-duplicate-detection-for-workflow-fixes.md`, AGENTS.md `hr-before-asserting-github-issue-status`, AGENTS.md `hr-when-triaging-a-batch-of-issues-never`, and the PR-vs-issue disambiguation rule from `2026-05-20-plan-time-pr-vs-issue-disambiguation-and-self-derived-counts.md`.
- [x] 1.3 Verify the learning file's frontmatter includes `title`, `date: 2026-05-21`, `category: engineering`, and `tags: [triage, bot, stale-issue, duplicate-detection, race-condition]`.

## Phase 2 — Commit, push, open PR with Closes #4221

- [ ] 2.1 Stage the plan, the spec directory (tasks.md + session-state.md), and the new learning file:
  ```bash
  git add knowledge-base/project/plans/2026-05-21-fix-stale-issue-auto-approve-trusted-applies-4221-plan.md \
    knowledge-base/project/specs/feat-one-shot-ci-auto-approve-trusted-applies-mismatch-4221/ \
    knowledge-base/project/learnings/2026-05-21-bot-filed-issue-races-prior-resolution-pr.md
  ```
- [ ] 2.2 Commit with conventional title: `fix(triage): close stale issue #4221 + codify bot-races-prior-PR detection (closes #4221)`.
- [ ] 2.3 Push the branch and open the PR with `Closes #4221` in the body.

## Phase 3 — Post-merge verification

- [ ] 3.1 Confirm issue #4221 closed (auto-closed by `Closes #4221`):
  ```bash
  gh issue view 4221 --json state | jq -r .state   # must be CLOSED
  ```
- [ ] 3.2 If still OPEN (auto-close did not fire — e.g., body parsed differently), close explicitly:
  ```bash
  gh issue close 4221 --reason "not planned" --comment "Already resolved by PR #4220 — see plan in $PLAN."
  ```

## Acceptance Criteria (mirrored from plan §"Acceptance Criteria")

### Pre-merge (PR)

- AC1: Plan file exists at the canonical path.
- AC2: Learning file exists with valid YAML frontmatter (≥5 tags including `triage`, `bot`, `stale-issue`).
- AC3: Learning body cross-references the 2026-04-22 prior-art learning.
- AC4: `Files to Edit` names no source files.
- AC5: Workflow file absent on main.
- AC6: Zero workflow runs after `2026-05-21T08:34:57Z`.

### Post-merge (operator-automatable via `gh` CLI)

- AC7: Issue #4221 state is `CLOSED`.
- AC8: A referencing comment naming PR #4220 is present on #4221.

## Out of scope

- Restoring the deleted workflow file (the design is unworkable per PR #4220's commit message).
- Editing `.github/workflows/` (the workflow is already gone; nothing to edit).
- Routing the new learning heuristic into `/soleur:triage` skill body (deferred — if the pattern recurs, file a tracking issue; the learning carries the heuristic in the meantime).
