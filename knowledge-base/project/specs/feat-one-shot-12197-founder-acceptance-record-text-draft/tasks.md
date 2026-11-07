# Tasks: founder-acceptance-record text draft (#12197, HOLD)

Plan: `knowledge-base/project/plans/2026-11-07-feat-founder-acceptance-record-text-draft-plan.md`

DRAFT, HOLD: the PR (#12342) stays draft. Never `gh pr ready`, never merge, never enqueue, never touch the `approval-queue` flag, never record a decision.

## Phase 1: Setup

- 1.1 Confirm the worktree and branch (`pwd`, `git branch --show-current`) and that PR #12342 is still a draft.
- 1.2 Re-read `apps/web-platform/server/legal-acceptance/texts/README.md` and `canonical.ts`; confirm nothing changed since the plan.

## Phase 2: Core Implementation

- 2.1 Write `apps/web-platform/test/legal-acceptance/founder-acceptance-record.test.ts` first (RED): loader parse, LF and ASCII for every key, version and no `valid_until`, placeholder present, forbidden words, no em dash, `REQUEST_CHANGES_MAX` and SQL `BETWEEN 1 AND 1000` parity, negative controls (Guard 1 rows 1 to 7, harness rows a and b).
- 2.2 Copy the proposal byte for byte: `cp knowledge-base/project/specs/feat-one-shot-12197-founder-acceptance-record-text-draft/founder-acceptance-record.proposed.md apps/web-platform/server/legal-acceptance/texts/founder-acceptance-record.md`, then `cmp` (exit 0). Do not run any formatter or `--fix` on it.
- 2.3 Rename the stale `canonical.test.ts` title; refresh the `routes.test.ts` comment and the `server/legal-acceptance/README.md` sentence.

## Phase 3: Verification

- 3.1 `sha256sum` the committed file; compare with `loadLegalTexts()` `textHash` and the plan value; note the value for the PR body.
- 3.2 Run markdownlint with the repo config on the committed path; expect rc=0.
- 3.3 Run vitest scoped to `apps/web-platform/test/legal-acceptance/`; cite the output in the PR body.
- 3.4 Run `plugins/soleur/test/c4-count-parity.test.sh` to confirm it stays green.
- 3.5 Confirm `git diff --stat` shows only the files in the plan.

## Phase 4: PR (draft, HOLD)

- 4.1 Push; keep PR #12342 DRAFT. Retitle it away from `WIP:`; body leads with a HOLD banner, `Ref #12197`, `Ref #12011` (no `Closes`), the counsel item list, rulings, local test output, hash, and the note that the `test` aggregator is red by design on drafts (`CI_DRAFT_LIGHT=on`).
- 4.2 Check the light-set CI checks are green. Do not mark ready, do not merge, do not enqueue, do not run ship's merge phase.
