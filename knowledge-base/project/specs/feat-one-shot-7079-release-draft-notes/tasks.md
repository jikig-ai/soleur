# Tasks - feat-one-shot-7079-release-draft-notes

Branch: feat-one-shot-7079-release-draft-notes | Draft PR: #10157 | Ref #7079 (never Closes)
Plan: knowledge-base/project/plans/2026-10-12-fix-release-self-heal-regenerate-draft-notes-plan.md
Rulings: knowledge-base/project/specs/feat-one-shot-7079-release-draft-notes/decision-challenges.md

## Phase 1: Tests first (RED) - plugins/soleur/test/reusable-release-idempotency.test.sh

- [ ] 1.1 Extend the `gh` stub's `edit` branch to also write one argument per line to `$GH_ARGV` (keep `$GH_TRACE` as is)
- [ ] 1.2 Add T8 behavioral section: read the Finalise run block via `wf_step_field ... run`; run under the stub in `bash -eo pipefail`; four rows a, b, c (parametrized: whitespace-only, zero bytes, missing), d; argv and stdout asserted in ONE comparison per row; assert the block is non-empty and contains `gh release edit`
- [ ] 1.3 Add T8b wiring section after T7b: three wiring literals plus the full `wf_ref_check` string `refs=check_changed,create_release,idempotency,pr,tmpfiles,version;unresolved=`
- [ ] 1.4 Raise `MIN_ASSERTIONS` from 77 to 77 plus the measured number of added assertions (compute from a real run)
- [ ] 1.5 Run the suite against the UNMODIFIED workflow; T8 rows a, b, c and the T8b wiring rows RED; row d and all pre-existing assertions GREEN

## Phase 2: Workflow edits - .github/workflows/reusable-release.yml

- [ ] 2.1 Finalise step env: add `RELEASE_NOTES_FILE`, `DRAFT_EXISTS`, `PR_NUMBER` (`${{ steps.pr.outputs.number }}`)
- [ ] 2.2 Finalise run block: single `gh release edit "$TAG" --notes-file "$RELEASE_NOTES_FILE" --draft=false` when `DRAFT_EXISTS=true`, `PR_NUMBER` non-empty and notes file non-blank; otherwise plain `--draft=false` (with `::warning::` when DRAFT_EXISTS=true); never fail on blank notes
- [ ] 2.3 Rewrite the self-heal comment block above the step
- [ ] 2.4 Add one line to the idempotency-step comment (notes overwritten at publish from the current run's PR)
- [ ] 2.5 Append "(a retry with a different bump orphans the prior draft)" to the `bump_type` description; `git grep -nF "Override bump type"` for pinned copies

## Phase 3: Mutation proof (against a COPY via REUSABLE_RELEASE_WF; variable unset for the real run)

- [ ] 3.1 Run Guard Contract mutations 1-9 each RED, 10 GREEN; PR body gets a one-line result

## Phase 4: Gates (only these)

- [ ] 4.1 `bash plugins/soleur/test/reusable-release-idempotency.test.sh` green, REUSABLE_RELEASE_WF unset
- [ ] 4.2 `actionlint`, `python3 scripts/lint-workflow-step-env-refs.py`, `python3 scripts/lint-workflow-errexit-capture.py`, shellcheck on the extracted block: nothing new versus origin/main
- [ ] 4.3 `bun test plugins/soleur/test/workflow-file-size.test.ts`
- [ ] 4.4 `git grep -nF "Finalise release (publish draft)" -- '*.test.sh' 'plugins/**/test/**'`; run any other suite found
- [ ] 4.5 `npx markdownlint-cli2` over the plan and this file

## Phase 5: Ship hygiene

- [ ] 5.1 PR body: `Ref #7079`, `## Changelog`, already-done table (#10016 for zot-entry-gate.sh; cloud-init.yml `/v2/` gates gone), the not-fixed-alone rationale for cloud-init-registry.yml ~2618 (do NOT touch it), the ruling rows, the one-line mutation result, the known limit (a later different merge recomputing the same tag publishes only that merge's notes)
- [ ] 5.2 Before the final push: read `BASELINE_DECLARED_PROBES` from `origin/main` (65 at planning time); this PR changes nothing in that test file
- [ ] 5.3 Rebase onto origin/main (never merge main); batch pushes; no sync push once queued in the merge queue
- [ ] 5.4 Cite the plan by its archived path once archived
