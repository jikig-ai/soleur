# Tasks — feat-one-shot-12509-oracle-bot-author (#12509)

Plan: `knowledge-base/project/plans/2026-11-09-fix-oracle-bot-author-regex-plan.md`

## Phase 1 — driver fix (AC1, AC3)

- [x] 1.1 `scripts/ci-oracle-review.sh:133` — widen `PR_AUTHOR` validation to `^[A-Za-z0-9][A-Za-z0-9-]*(\[bot\])?$`.
- [x] 1.2 `scripts/ci-oracle-review.sh:45` — update the emitted-grammar comment: `author` admits the `(\[bot\])?` suffix.
- [x] 1.3 Verify locally: `[[ "soleur-infra[bot]" =~ ^[A-Za-z0-9][A-Za-z0-9-]*(\[bot\])?$ ]]` exits 0; `[[ "deruelle[bot]" = deruelle ]]` still false.

## Phase 2 — regression rows (AC2)

- [x] 2.1 `scripts/ci-oracle-review.test.sh` — add `row_bot_author` (`PR_AUTHOR=soleur-infra[bot]`, oracle diff, reviews-none → rc 1 `review-required`), `row_bot_not_oracle` (`dependabot[bot]`, docs diff → rc 0 `not-oracle`), `row_bot_owner_spoof` (`deruelle[bot]`, oracle diff, reviews-none → rc 1 `review-required`); register all three in the `for row` loop.
- [x] 2.2 Widen the `want()` marker-grammar pin `author=[A-Za-z0-9-]+` → `author=[A-Za-z0-9-]+(\[bot\])?`.

## Phase 3 — verify (AC2)

- [x] 3.1 `bash -n` on both edited scripts; `bash scripts/ci-oracle-review.test.sh` green.
- [x] 3.2 Mutation check: revert the regex in a scratch copy → `row_bot_author` re-fails `reason=input` (guard matrix row 1 measures this exact defect).

## Phase 4 — ship (AC4)

- [x] 4.1 PR body: `Closes #12509`, `Ref #12329`, `Ref #9927`, `Ref #12489` (live victim).
- [x] 4.2 Ready + green checks; do NOT merge unilaterally — `oracle_diff=1` requires a bound owner review (`verdict=fail reason=review-required` until a `deruelle` APPROVED review bound to head SHA lands). Report the owner-review requirement.
