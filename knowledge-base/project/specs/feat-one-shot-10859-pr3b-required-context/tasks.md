# Tasks — feat-one-shot-10859-pr3b-required-context

Plan: `knowledge-base/project/plans/2026-11-07-ci-s4-pr3b-required-ratchet-context-plan.md`. Issue: #10859. Go-ahead receipt: issue comment 2026-11-07.

## Phase 1 — driver + verdicts

- [x] 1.1 Write `scripts/ci-oracle-review.sh` (env-only inputs; pull_request arm: base `RATCHET_ORACLE` classification, author==deruelle OR APPROVED review by deruelle bound to head SHA; merge_group arm: parity-pinned member enumeration, latest context completed/success per member head; fail-closed; `SOLEUR_ORACLE_REVIEW` line, literals only).
- [x] 1.2 Write `scripts/ci-oracle-review.test.sh` (stub `gh`; mutation + must-pass rows per Guard 2).
- [x] 1.3 `scripts/ci-pr-affected-replay.py`: marker accept=<n> marker field + docstring; base→HEAD accept row-set diff → `accept-unattributed`, `accept-bad-kind` findings; rewrite the "no required review exists" remedy line; `RATCHET_ORACLE` += the two new files; `ALWAYS_RUN_JOBS` += `oracle-review-required`.
- [x] 1.4 `plugins/soleur/test/ci-pr-affected-replay.test.sh`: `rt_marker` grammar, verdict mutation rows (Guard 3), census re-pin + `--rows` arm re-tile.
- [x] 1.5 Registration: `run_suite` in `scripts/test-all.sh`; `scripts/regenerate-shard-manifest.py` for `suite-shard-legs.tsv`; edges + accept rows in `test-affected-paths.sh`/`accept.tsv` (six typed kinds); `scripts/ci-oracle-lane-suites.txt` membership row.

## Phase 2 — enrollment

- [x] 2.1 `.github/workflows/ci.yml`: delete `continue-on-error` on `affected-index-ratchet`; add `oracle-review-required` job; header + extractor comments.
- [x] 2.2 `scripts/required-checks.txt` (2 names + dispositions), canonical JSON (+2 @15368), `infra/github/ruleset-ci-required.tf` (+2 blocks + comments).
- [x] 2.3 `tests/scripts/test-audit-ruleset-bypass.sh` T-rsc-7 10→12 + comment; admin-merge-ready fixtures (rules + runs + README + test header).
- [x] 2.4 `scripts/pr-fanout-ledger.txt` ci.yml row 21→22 dated clause; `UNGATED_PINNED`, `LIGHT_PINNED`; `plugins/soleur/test/required-checks-canonical-parity.test.sh` floor `-ge 10` → `-ge 12`; `scripts/probe-merge-group-coverage.sh` `MIN_CONTEXTS_DEFAULT` 12→14 + comment.
- [x] 2.5 Unreachability assertion test (ALLOWED_PATHS ∩ RATCHET_ORACLE and ∩ audit read surface = ∅).

## Phase 3 — docs + ADR

- [x] 3.1 Runbook `ci-pr-affected-activation.md`: advisory→required, oracle-review section, marker grammar, observation-log line.
- [x] 3.2 ADR-276 dated amendment + Stage-status line (append-only).

## Phase 4 — verification

- [ ] 4.1 Suites: probe-merge-group-coverage, parity, audit-ruleset-bypass, admin-merge-ready, fanout-ledger, push-dedupe, draft-light, aggregator-diagnosis, replay suite, oracle-review suite.
- [ ] 4.2 Cumulative baseline re-check = 0 added lines; first required-run check-list rendering → runbook log; post-merge ruleset verify (bypass_actors/conditions unchanged).
