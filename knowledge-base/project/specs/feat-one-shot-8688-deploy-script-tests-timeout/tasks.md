# Tasks — fix-deploy-script-tests-timeout-headroom (#8688)

Derived from `knowledge-base/project/plans/2026-09-24-fix-deploy-script-tests-timeout-headroom-plan.md`.
Single file edited: `.github/workflows/infra-validation.yml`.

## Phase 1 — Setup

- [x] 1.1 Confirm the worktree is on `feat-one-shot-8688-deploy-script-tests-timeout` and
      the plan's measured basis still holds: spot-check the latest `Infra Validation`
      main-push runs (`gh api 'repos/jikig-ai/soleur/actions/workflows/248570873/runs?branch=main&per_page=10'`).
      If the green max moved above 1462 s, re-derive per the same formula before editing.
- [x] 1.2 Read the ceiling comment block end-to-end
      (`.github/workflows/infra-validation.yml`, the `deploy-script-tests` job header
      comments ending at `timeout-minutes: 27`) so the new entry matches the file's own
      dated RE-DERIVED form.

## Phase 2 — Core Implementation

- [x] 2.1 Append the `RE-DERIVED 2026-09-24 (#8688)` paragraph at the end of the ceiling
      comment block: the 19-run successful set, observed max 1462 s, the arithmetic
      `1462 x 1.4 = 2047 s = 34.1 min -> 35`, the four cancelled-run IDs (35963237265,
      35976102327, 35991817044, 36001457260) excluded per the successful-only rule, the
      ~16 trailing steps / ~1700–1850 s projected-completion note, and a note that the
      same PR adds three step bounds below.
- [x] 2.2 Change the job key `timeout-minutes: 27` → `timeout-minutes: 35`.
- [x] 2.3 Add `timeout-minutes: 10` to `Rehearse the git-data runcmd chain (abort
      ordering + rc guard)` (sibling key of `name:`/`run:`), preceded by a short comment
      in the file's attribution idiom: the convention (ci-deploy at 3, plugin-seed at 1),
      measured green range 184–267 s, cancelled-in-flight 285–455 s ×4, the stated
      flake-over-anonymity trade-off.
- [x] 2.4 Add `timeout-minutes: 8` to `Run git-data cutover access-path tests (ADR-220)`
      with its comment (sized above the suite's own `timeout -k 10 480` container bound
      plus the apt fixture, so the inner bound fires first).
- [x] 2.5 Add `timeout-minutes: 5` to `Run git-data ownership tests (authorization map +
      hook dir, Guard 3)` with its comment.
- [x] 2.6 Verify the diff touches only `timeout-minutes` keys and comment lines: no
      `- name:`/`run:` line changed, no step reordered, `27` → `35` the only value
      change.

## Phase 3 — Testing / Verification

- [x] 3.1 `actionlint .github/workflows/infra-validation.yml` → rc 0 (clean baseline
      today; any new finding is a regression).
- [x] 3.2 `bash .github/scripts/test/test-infra-suite-registration.sh` → green.
- [x] 3.3 `python3 scripts/lint-workflow-run-body-syntax.py` → green;
      `python3 scripts/lint-workflow-local-action-checkout.py` → green.
- [x] 3.4 Bound count: flag-based awk extract of the `deploy-script-tests` block yields
      8 `timeout-minutes:` keys (was 5).
- [x] 3.5 `git diff` review against the plan's AC: only the prescribed additions and the
      `27` → `35` change.

## Phase 4 — Post-merge (automated by the pipeline)

- [ ] 4.1 On `origin/main`, verify the job block carries `timeout-minutes: 35` and the
      three step bounds (`git show origin/main:.github/workflows/infra-validation.yml`).
- [ ] 4.2 Pull the first completed main-push `Infra Validation` run's
      `deploy-script-tests` conclusion + per-step durations via
      `gh api repos/jikig-ai/soleur/actions/runs/<id>/jobs`; record the new green
      baseline for the next re-derivation. A cancel is a runner-variance observation,
      not a verdict on the diff — unless the in-flight step is one the diff left
      unbounded.
