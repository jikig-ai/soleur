---
spec: knowledge-base/project/specs/feat-preflight-credit-balance-3605/spec.md
plan: knowledge-base/project/plans/2026-05-11-fix-preflight-credit-balance-soft-skip-plan.md
branch: feat-preflight-credit-balance-3605
draft_pr: 3606
status: ready
---

# Tasks: anthropic-preflight credit-balance soft-skip (#3605)

## Phase 1 — Edit

- [ ] **1.1** Edit `.github/actions/anthropic-preflight/action.yml` lines 41-48
  region. Three sub-edits in a single commit:
  - [ ] **1.1.1** Update comment block above the grep clause to cite both
    issues (#2715, #3605) and both literal strings (TR2). See plan Phase 1
    step 1 for suggested wording.
  - [ ] **1.1.2** Replace line 46 grep clause with
    `grep -qE "(specified API usage limits|credit balance is too low)"` (TR1).
  - [ ] **1.1.3** Replace line 48 warning text with
    `"::warning::Anthropic API unavailable (spend cap or credit balance) — skipping Claude steps. Body: $BODY"` (TR2).
- [ ] **1.2** Stage and commit only `action.yml` with message
  `fix(ci): soft-skip anthropic-preflight on credit-balance 400 (#3605)`.
  Do NOT amend the existing brainstorm/spec/plan commit `1f3cee58`.

## Phase 2 — Verify (V-B1)

- [ ] **2.1** Run the synthesized-fixture sanity script from plan Phase 2.
  Three fixtures (spend-cap, credit-balance, generic 400), three expected
  outcomes (MATCH, MATCH, NO MATCH).
- [ ] **2.2** Confirm output line-for-line matches:
  ```
  spend-cap → MATCH (soft-skip)
  credit-balance → MATCH (soft-skip)
  generic-400 → NO MATCH (hard-fail)
  ```
- [ ] **2.3** If any line disagrees, abort. Re-read the grep clause for a
  literal-string typo. Do NOT proceed to Phase 3.

## Phase 3 — Ship

- [ ] **3.1** Verify PR #3606 body contains `Closes #3605`. If missing, edit
  via `gh pr edit 3606 --body-file <body.md>`. Title must NOT contain
  `Closes` per `wg-use-closes-n-in-pr-body-not-title-to`.
- [ ] **3.2** `gh pr ready 3606` to mark draft ready for review.
- [ ] **3.3** Run `bash plugins/soleur/skills/preflight/scripts/preflight.sh`
  if applicable, or rely on CI checks per `wg-after-marking-a-pr-ready-run-gh-pr-merge`.
- [ ] **3.4** `gh pr checks 3606 --watch` — wait for all required checks green.
- [ ] **3.5** `gh pr merge 3606 --squash --delete-branch`.
- [ ] **3.6** Verify #3605 auto-closed by the `Closes` link on merge.

## Phase 4 — Cleanup

- [ ] **4.1** Switch back to main: `git checkout main && git pull`.
- [ ] **4.2** Drop the worktree:
  `bun run plugins/soleur/scripts/cleanup-merged.ts`.

## Acceptance Criteria

See plan: `knowledge-base/project/plans/2026-05-11-fix-preflight-credit-balance-soft-skip-plan.md#acceptance-criteria`.

## Out of Scope

- Track A (#3604 compound-promote workflow_dispatch validation). Dispatch is
  already in flight on main as workflow run `25688627107`. Do NOT couple the
  #3604 close into this PR — independent tracks per brainstorm Key Decisions.
- Sentry mirror retrofit on existing soft-skip branches.
- New action inputs / env vars.
- Changes to any `.github/workflows/*.yml` consuming this action.
- Expansion to other HTTP 400 message classes.
