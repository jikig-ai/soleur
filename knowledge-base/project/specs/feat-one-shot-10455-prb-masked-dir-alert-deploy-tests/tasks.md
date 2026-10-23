# Tasks: sandbox masked-dir alert, synthetic mask coverage, apt fixture (PR-B of #10455)

Plan: `knowledge-base/project/plans/2026-10-23-fix-sandbox-masked-dir-alert-synthetic-coverage-and-apt-fixture-plan.md`
Branch: `feat-one-shot-10455-prb-masked-dir-alert-deploy-tests` | Draft PR: #10892 | Refs: #10455, #10548, #10781 (never Closes)

## Phase 0: RED tests and re-verification

- 0.1 Re-read GuardA state on a fresh `origin/main`; record the run id and pin `v1.1.58` (no file change).
- 0.2 Write the failing tests named in Phases 1 to 3; run each and confirm RED for the right reason.
- 0.3 Pick an unused `frequency_minutes` (`grep -h frequency_minutes apps/web-platform/infra/sentry/*.tf | sort -n`; 38 free at plan time).

## Phase 1: routed alert (P1)

- 1.1 `agent-runner-sandbox-config.ts`: iterate the three named lists with local kind labels; add `tags: { dir_kind }`; fix the stale "no dedicated alert" comment. No new export.
- 1.2 `infra/sentry/issue-alerts.tf`: `sentry_alert.masked_dir_precreate_failed` (copy `seccomp_remediation_failed`, add the `feature` filter as in `sandbox_startup_failure`, `monitor_ids`, unused frequency, `ignore_changes = [environment]`).
- 1.3 Derive `alert-reference.json` locally via `terraform show -json` + the projection jq (mandatory); update README counts (46 / 44 / 43, T25).
- 1.4 Create `test/sentry-masked-dir-precreate-alert-op-contract.test.ts` (Guard 1).
- 1.5 Extend `test/agent-sandbox-precreate-failure.test.ts`: feature + `dir_kind` per kind; entry stays in `denyRead`.
- 1.6 Create `scripts/masked-dir-alert-discoverability.sh` (about 20 lines, grep/awk, prints `MASKED_DIR_ALERT_PATH_OK`); run it once.

## Phase 2: probe creates the masked set (P2)

- 2.1 `infra/lib/sdk-bash-probe.mjs`: `SESSION_TMP_ROOT`, `precreateDirs`, `ensureMaskedDirs` (uid guard, HOME guard, create-only-when-absent, lstat/owner failure rule), remove `runtimeMaskedDirs`, keep `planSmoke` pure, pass all `denyRead` entries.
- 2.2 `infra/web-bash-synthetic.sh`: parse and journal `masks_created`, `masks_note` (closed charsets); old-probe output parses to `-`; ping unchanged.
- 2.3 Tests: `sdk-bash-probe-runtime.test.ts` (rewrite rows near 120-124 and 146-150), `sdk-bash-probe-parity.test.ts` (set equality, Guard 2), `agent-sandbox-precreate-failure.test.ts` (builder-versus-reality), `web-bash-synthetic.test.sh` rows.
- 2.4 Runbook `canary-probe-set.md`: decode rows, alert-response section, proof limits, soak note.

## Phase 3: apt fixture (P3)

- 3.1 `infra/lib/apt-bounded.sh`: shared `Dir::State::lists` / `Dir::Cache::archives` on both calls, `partial/` dirs at arm, trailing `chmod -R a+rwX`, fix the stale header sentence; no timeout option.
- 3.2 Surface the scrubbed apt tail in the consumers that drop it (measure first).
- 3.3 `infra/apt-bounded.test.sh`: Guard 4 rows with a cache-simulating stub; run every consumer suite (6), A10 census and S1 ceilings unchanged.
- 3.4 Comment on #10781 (signature a addressed, b instrumented); close later after three consecutive green runs.

## Phase 4: records

- 4.1 ADR-079: edit the "creates nothing" sentence in place; add the 2026-10-23 addendum (about 10 lines).
- 4.2 ADR-188: short 2026-10-23 amendment (about 10 lines).
- 4.3 C4: grep the Sentry and Better Stack descriptions; run `c4-count-parity.test.sh` and the C4 vitest pair.

## Phase 5: quality gates and ship

- 5.1 Run directly: `c4-count-parity.test.sh`, `sentry-monitors-audit.test.sh` (T25), `web-bash-synthetic.test.sh`, `ci-deploy.test.sh`, `apt-bounded.test.sh`, the vitest files above, `lint-guard-contract.py` on the plan.
- 5.2 Simulate the rollback in a scratch worktree (`git revert --no-commit`) and write the recipe into the runbook.
- 5.3 File the Slack-wake-path verification issue (verify labels with `gh label list`; milestone `Post-MVP / Later`).
- 5.4 PR body: first line answers "does merging this alone mutate production"; `Ref #10455`, `Ref #10548`, `Ref #10781`; GuardA note; the operator hand-off line with the two typed commands for #10548; no "paged" claim.
- 5.5 `soleur:engineering:review:user-impact-reviewer` and `observability-coverage-reviewer` at review.
