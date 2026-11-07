# Tasks: founder-acceptance-record text draft (#12197, HOLD)

Plan: `knowledge-base/project/plans/2026-11-07-feat-founder-acceptance-record-text-draft-plan.md`

DRAFT, HOLD: the PR (#12342) stays draft. Never `gh pr ready`, never merge, never enqueue, never touch the `approval-queue` flag, never record a decision. Read the prd flag state only if asked, and only read-only.

## Phase 1: Setup

- 1.1 Confirm the worktree and branch (`pwd`, `git branch --show-current`) and that PR #12342 is still a draft.
- 1.2 Re-read `apps/web-platform/server/legal-acceptance/texts/README.md` and `canonical.ts`; confirm nothing changed since the plan. If counsel has edited `founder-acceptance-record.proposed.md` since the plan, take the file as it is and recompute the hash.

## Phase 2: Core Implementation (RED first)

- 2.1 Write `apps/web-platform/test/legal-acceptance/founder-acceptance-record.test.ts`: `auditDir(dir)` raw-byte loop (no 0x0D, nothing above 0x7F, no BOM, at least one key) with a temp-dir negative control; shared `FORBIDDEN` regex with a planted-string control; the body's single `up to (\d+) characters` equals `REQUEST_CHANGES_MAX`; loader version matches `^\d{4}-\d{2}-\d{2}$` and `validUntil` is null; `it.skipIf(!process.env.CI)` merge guard (no `\[[^\]\n]*\]` token in the body). Run it and cite the RED output (the text does not exist yet).
- 2.2 Extend `apps/web-platform/test/legal-acceptance/cross-layer-limits.test.ts`: extract both note-limit literals from migration 184 (the `requested_edit` CHECK and the RPC `char_length(p_requested_edit) > 1000` guard) using the file's existing comment-stripping helpers; each equals `REQUEST_CHANGES_MAX`; an empty extraction fails.
- 2.3 Copy the proposal byte for byte: `cp knowledge-base/project/specs/feat-one-shot-12197-founder-acceptance-record-text-draft/founder-acceptance-record.proposed.md apps/web-platform/server/legal-acceptance/texts/founder-acceptance-record.md`, then `cmp` (exit 0). Do not run any formatter or `--fix` on it. Add a one-line superseded note to the `.proposed.md`.
- 2.4 Rename the stale `canonical.test.ts` title only; refresh the `routes.test.ts` comment and the `server/legal-acceptance/README.md` sentence.

## Phase 3: Verification

- 3.1 `sha256sum` the committed file; compare with `loadLegalTexts()` `textHash`; note the value for the PR body.
- 3.2 `LC_ALL=C grep -c -P '[^\x00-\x7F]'` and `grep -c $'\r'` on the committed file print 0; `git check-attr eol` reports `lf`.
- 3.3 markdownlint with the repo config on the committed path and on the README; rc=0.
- 3.4 Run vitest scoped to `apps/web-platform/test/legal-acceptance/`; then run the new file once with `CI=1` and cite the RED merge-guard output. Cite all outputs in the PR body.
- 3.5 After committing, re-run `cmp` (no hook rewrote the file) and check `git diff --stat` shows only the files in the plan.

## Phase 4: PR (draft, HOLD)

- 4.1 Push; keep PR #12342 DRAFT. Retitle it away from `WIP:` (for example `feat(legal-acceptance): DRAFT founder-acceptance-record text, HOLD for counsel`); the body leads with a HOLD banner, `Ref #12197`, `Ref #12011` (no `Closes`/`Fixes`/`Resolves`), the counsel items list (see plan AC8), #12344 as a merge precondition, the rulings, local test output, hash, and that the `test` aggregator is red by design on drafts (`CI_DRAFT_LIGHT=on`).
- 4.2 List the light-set checks with `gh pr checks` and confirm green; report any pre-existing failure with evidence. Do not mark ready, do not merge, do not enqueue, do not run ship's merge phase.
