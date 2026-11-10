# Tasks — feat-one-shot-12593-ci-repair

Plan: `knowledge-base/project/plans/2026-11-10-fix-ci-main-red-baseline-literals-apt-repair-plan.md`
Issue: #12593 | PR: #12594 | Branch: `feat-one-shot-12593-ci-repair`

## Phase 1 — Deterministic main-red repairs

- [x] 1.1 Regenerate `plugins/soleur/test/fixture-relative-assert.baseline.txt` via `bash plugins/soleur/test/fixture-relative-assert.test.sh --write-baseline`; diff-verify delta is only the expected rows/totals (ci-oracle-review.sh 12→13, SITES 2522→2523); re-run suite → green. (AC1)
- [x] 1.2 In `plugins/soleur/test/required-checks-merge-group-coverage.test.sh`, replace the eight `contexts=14 producers=13` literals (lines 297, 300, 326, 375, 377, 379, 381, 383) with `contexts=13 producers=12`; leave the synthetic `contexts=12 producers=11` control at line 641; re-run battery → 73/73 green. (AC2)
- [x] 1.3 Regenerate `scripts/test-affected-kb-consumers.baseline.txt` via `bash scripts/test-affected-kb-consumers.test.sh --write-baseline`; diff-verify exactly +5 `scripts/ci-oracle-review<TAB>knowledge-base*` rows; re-run ratchet → green. (AC3)
- [x] 1.4 Insert one blank line before `- 2026-11-09 S4 retired` in `knowledge-base/engineering/architecture/decisions/ADR-276-demand-first-hosted-runner-budget-merge-group-is-the-full-battery-authority.md` (~line 694); `npx markdownlint` → exit 0. (AC4)

## Phase 2 — Apt retry repair

- [x] 2.1 In `apps/web-platform/infra/lib/apt-bounded.sh::_gd_apt_install_bounded_cycle`, pass `try` into the bounded `bash -c`; on `try > 1` run `echo GD_APT_STAGE=repair; dpkg --configure -a || true` before the update stage; update header note ~:80-81. (AC5, AC6)
- [x] 2.2 In `apps/web-platform/infra/apt-bounded.test.sh`: add `$STUB/dpkg` (own calls file, never `GD_STUB_CALLS`), a `dpkg-poisoned` apt mode (first call → rc 100 `dpkg was interrupted`, then ok), and a regression row asserting repair-then-success (rc 0, dpkg called once, 3 apt calls). Run suite → green. (AC5)

## Phase 3 — Verify + commit

- [x] 3.1 Re-run all five suites; confirm `git diff` shows only expected deltas; `git-data-rung2-boot-evidence.env` NOT touched (noted as remaining in PR body). Commit. (AC7)

## Collision watch

- [ ] CW1: PR #12560 (#12559) touches `scripts/test-affected-kb-consumers.baseline.txt` + ADR-276 — re-check its merge state at ship time; same-content merge expected for the baseline.
