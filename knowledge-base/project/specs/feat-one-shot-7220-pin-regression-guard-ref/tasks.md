# Tasks — pin the #7220 regression guard to an immutable SHA

Plan: `knowledge-base/project/plans/2026-08-04-fix-pin-infra-config-apply-regression-guard-plan.md`
Branch: `feat-one-shot-7220-pin-regression-guard-ref`
PR: #7271
Refs: #7220 (stays OPEN — this is the CI repair only)

## Phase 1 — Setup / baseline

- [x] 1.1 Reproduce the failure: `bash apps/web-platform/infra/infra-config-apply.test.sh` →
      confirm `144 passed, 2 failed` and that the two failures are exactly
      `pre-fix handler carried NO fatal_line` and `pre-fix handler reported the hardcoded files_total=0`.
- [x] 1.2 Re-confirm the pin target still satisfies both assertions (guards against a wrong SHA):
      `git show 701e76e6bfce84ceed91096a58d88df7da5b6932:apps/web-platform/infra/infra-config-apply.sh`
      → `fatal_line` count `0`, `"files_total":0` present.

## Phase 2 — Core implementation

- [x] 2.1 Add `readonly PRE_FIX_HANDLER_SHA="701e76e6bfce84ceed91096a58d88df7da5b6932"` with the
      full rationale comment, including the literal line
      `Do not "helpfully" restore the branch name.` (AC4 asserts this string).
- [x] 2.2 Swap the read in `test_fatal_channel_red_against_main` from
      `origin/main:apps/web-platform/infra/infra-config-apply.sh` to
      `${PRE_FIX_HANDLER_SHA}:apps/web-platform/infra/infra-config-apply.sh`.
- [x] 2.3 Swap the skip/fail predicate from `rev-parse --verify origin/main` to
      `cat-file -e "${PRE_FIX_HANDLER_SHA}^{commit}"`. **Preserve both arms** — FAIL when the
      commit is present but unreadable, loud SKIP when it is absent. Update both echo strings to
      the `pinned pre-fix commit` wording the ACs assert.
- [x] 2.4 Sweep stale prose: block header (~1107) and section marker (~1340). Re-read ~1342-1344
      and adjust only what the pin falsifies.
- [x] 2.5 `grep -n 'origin/main' apps/web-platform/infra/infra-config-apply.test.sh` — confirm
      every survivor is deliberate rationale prose, and that no *executable* line matches.

## Phase 3 — Testing / verification

- [x] 3.1 Run the suite; expect `=== Results: 146 passed, 0 failed ===`. Capture the real output
      for the PR body — do not assert green without it.
- [x] 3.2 Non-vacuity control: temporarily repoint `PRE_FIX_HANDLER_SHA` at `c2de2581e` (the
      *fixed* handler) and confirm the two assertions FAIL. **Revert immediately.** This proves
      the pin still discriminates rather than passing by construction.
- [x] 3.3 Walk AC1-AC8 in the plan and record each result.
- [x] 3.4 Confirm scope: `git diff origin/main...HEAD --name-only` lists only the test file plus
      this plan and spec artifacts.

## Phase 4 — Ship

- [ ] 4.1 PR body: use `Ref #7220`, **not** `Closes` — the issue stays open for PR-B's grant work.
- [ ] 4.2 PR body records that `deploy-script-tests` is advisory (does not block merge) so the
      change is not oversold, and pastes the 146/0 run output.
