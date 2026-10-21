# Tasks - feat-one-shot-compound-promote-server-quorum

Plan: `knowledge-base/project/plans/2026-10-20-fix-compound-promote-server-quorum-plan.md`.
Rulings: `knowledge-base/project/specs/feat-one-shot-compound-promote-server-quorum/decision-challenges.md`.

## Phase 0 - RED (tests first)

- 0.1 Add the inert constant `export const PROMOTION_QUORUM = 5;` to `cron-compound-promote.ts` (unused) so fixtures compile and RED is an assertion failure.
- 0.2 `cron-compound-promote-draft-edit.test.ts`: rebuild `summaries`/`cluster` and the prompt-grammar row from the constant; replace the T20 `no-source` row; add Q1-Q4; also read T10/T11/T12, T10b, T16 and the prompt-grammar row, which share the 2-source fixture; separate RED rows from GREEN-by-design pins.
- 0.3 `cron-compound-promote-draft-handler.test.ts`: widen the corpus seed (`2 * PROMOTION_QUORUM + 2`, computed from the constant; multi-cluster fixtures use different source sets), rebuild `AGENTS_CLUSTER`, `SKILL_CLUSTER`, the `second` clusters, the evil-path and duplicate-collapse tests from the constant, change the all-unknown test to `quorum-not-met`, add H1-H8; confirm RED.
- 0.4 `cron-compound-promote-outcome-census.test.ts`: add Guard 1d (one declaration, three identifier uses, one emit site, not in `EDIT_REFUSAL_REASONS`, dispatch-throws rows, in-test mutations); confirm RED.
- 0.5 `cron-compound-promote.test.ts`: value pin V1 and phase-1 prompt check.
- 0.6 `compound-promote-draft-edit-10552.test.sh`: rows P-4b and P-4c and mutation arms M-14, M-15; confirm P-4b and M-14 RED.

## Phase 1 - GREEN, production

- 1.1 `EditRefusal`: add `"quorum-not-met"` to `reason`, optional `sourceCount`.
- 1.2 `draftAdditiveEdit`: move `sources` above `readEditTarget`; add the `sources.length < PROMOTION_QUORUM` refusal; delete the `no-source` branch.
- 1.3 Handler: record `raw_source_count` before the normalisation filter and forward `proposed_count` (and `source_count`) to the Sentry `extra`; prompt reads the constant and asks for exact corpus key paths; trailer denominator reads the constant; `!result.ok` branch forwards `source_count` to `extra`; slot-crowding comment at the phase-1 slice; update the normalisation and CO-MOVING comments.
- 1.4 Re-run the four vitest files; Guards 1b, 1c, 3, 3b must pass unmodified.

## Phase 2 - GREEN, probe

- 2.1 Add `quorum-not-met` to `nset`; update the header comment.
- 2.2 Run the probe suite; set `MIN_CASES` to exactly the measured total (baseline 175 plus the added assertions).

## Phase 3 - docs and record

- 3.1 `betterstack-log-query.md`: pre-draft refusal table row, drop "no resolvable source learning" from `edit-invalid`, cause and `source_count` paragraph.
- 3.2 `compound-promote-runbook.md`: server-enforced quorum, drafting-flow step, streak bullet, `last_updated`.
- 3.3 ADR-092 Amendment dated 2026-10-20 via `soleur:architecture`.
- 3.4 Work-phase compound learning (topic only; date at write time).

## Phase 4 - mutation proof

- 4.1 Execute every Guard 1 matrix row (8) and Guard 2 row (3): scratchpad copy, one-line edit, run named suite, record RED, restore.
- 4.2 Record the table in the PR body.

## Phase 5 - verify

- 5.1 Four vitest files, probe suite, `tsc --noEmit` in `apps/web-platform`.
- 5.2 Run the discoverability command once; record the output.
- 5.3 `lint-guard-contract.py`, `lint-infra-no-human-steps.py --changed`, markdownlint on touched `.md`.
- 5.4 Repo-wide ratchets: `lint-betterstack-emitter-read.sh`, `fixture-relative-assert.test.sh`, `grep-q-pipe-guard.test.sh`, `test-affected-kb-consumers.test.sh`, `c4-count-parity.test.sh`.
- 5.5 `git diff --name-only origin/main...HEAD` contains nothing under `knowledge-base/legal/`, no `compound-promote-marker.ts`, no `scripts/compound-promote.sh`.
- 5.6 PR body: `Ref #10552`, first line states the production effect on the next scheduled fire.
