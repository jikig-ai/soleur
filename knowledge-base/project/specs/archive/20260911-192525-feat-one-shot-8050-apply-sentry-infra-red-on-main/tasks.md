# Tasks: fix(ci) apply-sentry-infra red on main — Terraform-derived fidelity reference

Plan: `knowledge-base/project/plans/2026-09-11-fix-apply-sentry-infra-red-on-main-plan.md`. Issue #8050 (closes); #8057 / #8058 closed by the drift workflow's own close steps on the Phase 7.2 dispatch.

## Phase 0: Preconditions and probes (read-only, no product edits)

- [x] 0.1 Local read-only plan from `apps/web-platform/infra/sentry/` with the README §Local invocation triplet; `terraform show -json` → `/tmp/sentry-local-plan.json`; expect 0/0/0. STOP only if a `sentry_alert` row is not a no-op; file unrelated monitor drift as its own issue and proceed.
- [x] 0.2 Parity measurement with the shipped module: `side tf`(plan) vs `side live`(phase34 capture) → 28 common, 0 mismatches, plan-only `["ops-email-delivery-failure"]`. Record in the PR body.
- [x] 0.3 Pin literals: Doppler `prd` `SENTRY_API_HOST == jikigai-eu.sentry.io` (boolean compare, not printed); `variables.tf` default `jikigai-eu`.
- [x] 0.4 Lint baseline: `lint-shell-trace-credential-refusal.py scripts/sentry-alert-live-fidelity.sh` → 3 violations; baseline line 71 present.
- [x] 0.5 Known-at-plan-time measurement with a throwaway block (read-only plan, then `git checkout -- issue-alerts.tf`); record the create row's `after_unknown` keys; delete the scratch plan.
- [x] 0.6 Re-verify the provider constant at the pinned tag (`OrganizationWorkflowTriggerLogicTypeAnyShort` in create + update builders).

## Phase 1: Projection module and committed reference

- [x] 1.1 Create `tests/scripts/lib/sentry-alert-projection.jq` (`--arg side tf|live|reference`): shared `canon`/`normalise`/`excluded`/`lifecycle`/`trigger_logic_type`/`shape_ok`; `tf` side floors (planned_values/values, no child_modules, enabled boolean, arrays, one non-null key, excluded-trigger error, lifecycle → `true`, email action mapping with an explicit action-kind allowlist `["email"]`, `sensitive_values` true-leaf refusal, single-trigger constant, duplicate-name error, canon before sort; `shape_ok` is shape not cardinality); `live` side = the probe's `PROJECT` + single-trigger constant + `normalise`; `reference` side = `shape_ok` then `normalise`. Header cites the measurement and provider lines 803/835.
- [x] 1.2 Generate and commit `apps/web-platform/infra/sentry/alert-reference.json` (29 keys incl. `ops-email-delivery-failure`, `byok-art-33-breach`).

## Phase 2: Probe reads a projected reference; #7997 fidelity rows

- [x] 2.1 `scripts/sentry-alert-live-fidelity.sh`: `SENTRY_REFERENCE_FILE` default to the committed copy; live + reference projections via the module with rc on its own line; header + finding text rewrite (UNMANAGED = undeclared; LOGICTYPE FLIP = live state an apply will not touch); verdict literals unchanged; pins (`SENTRY_API_HOST`, `SENTRY_ORG`) inside the live branch after the fixture return; `curl --disable --noproxy '*' -fsS --max-time 15 --header @- …` with the bearer header on stdin (model: `scripts/supabase-logs-query.sh`).
- [x] 2.2 Lint → 0 violations; remove the probe's line from `scripts/lint-shell-trace-credential-refusal-d.baseline.txt`; `git grep -nw SENTRY_CAPTURE_FILE` consumers updated; comment on #7997 (fidelity rows closed here; audit rows remain) — posted.

## Phase 3: Reference gate (PR time) and the apply job's own reference

- [x] 3.1 Create `scripts/sentry-alert-reference-gate.sh <plan.json> <reference.json>` (house style: `set -uo pipefail`, rc per jq, floors, leaf diff, detectorIds hint, ack-destroy note, regeneration command, expected doc to `$GITHUB_STEP_SUMMARY` + `${RUNNER_TEMP}/sentry-alert-reference.expected.json`).
- [x] 3.2 `apply-sentry-infra.yml` `plan_pr`: call the gate after `sentry-adoption-plan-assert.sh`; add SHA-pinned `upload-artifact` `if: failure()` + `if-no-files-found: warn` for the expected document, after the existing secret-shape sentinel sweep over that file.
- [x] 3.3 `apply-sentry-infra.yml` `apply`: project `/tmp/sentry-apply-plan.json` → `${RUNNER_TEMP}/sentry-alert-reference.json` in the plan step with `|| { echo "::error::… BEFORE apply — nothing written"; exit 1; }` (the step is under re-armed `set -e`; a post-command `rc=$?` is dead code); `id: plan` / `id: apply` / `id: fidelity`; probe step `if: always() && steps.plan.outcome == 'success'` + `SENTRY_REFERENCE_FILE` env; rewrite the probe step's comment; filer body gains the Plan/Apply/Probe outcome line and the "plan-step failure = nothing written; follow-up PR, not re-run" bullet; do-not-repoint comments on both `sentry-adoption-plan-assert.sh` arguments. No gate copy in this job.
- [x] 3.4 Add the gate script and the module to `on.push.paths` and the `detect-changes` regex with `#4419` comments.

## Phase 4: Daily drift workflow (own early commit)

- [x] 4.1 `scheduled-sentry-alert-drift.yml`: `id: file_unavailable`; `if: always() && !cancelled() && (verdict == 'unavailable' || verdict == '' || (verdict == 'drift' && steps.file_drift.outputs.filed != 'true'))`; body `Verdict reached:` arm text; comment cites run 34573504979 / #8058.
- [x] 4.2 Hoist both TITLE literals to job-level `env:` (strings unchanged) and reference them from filer, dedupe and close steps.
- [x] 4.3 Body text: reference path; remove all three "28 adopted"; regeneration remedy; UNMANAGED wording.
- [x] 4.4 Closer "Close the probe-unavailable issue": `if: always() && (verdict == 'clean' || (verdict == 'drift' && steps.file_drift.outputs.filed == 'true'))` so it cannot undo the filer's drift-not-filed arm in the same run; record the read-after-write miss in its comment; no retry.
- [x] 4.5 Unavailable filer: add the no-`--milestone` fallback (closed-milestone hard-fail); titles reach `run:` as `"$DRIFT_TITLE"`/`"$UNAVAILABLE_TITLE"` env, never `${{ env.… }}` interpolation.

## Phase 5: Tests (RED first)

- [x] 5.1 `tests/scripts/test-sentry-alert-live-fidelity.sh`: derive the reference from the frozen phase34 capture at suite start; identity literal with FIXTURE token and computed N (labelled a wiring test); rows (a)–(l) each with a DISTINCT literal, incl. (i) tf/live shape parity over `common >= 20` names against the committed reference, (g) `all → any-short` mutation, (k) `comparison.value` swap negative control, (l) `_mutant` NOOP landing row; `EXPECTED_TESTS` 13 → 25.
- [x] 5.2 New `tests/scripts/test-sentry-alert-reference-gate.sh`: synthetic two-rule plan (one rule with two trigger conditions and two actions); G0 positive control; Guard 1 M1–M12 with distinct literals; must-PASS rows (arrays AND comparison keys reversed; show-state input; whitespace) and the `comparison.value` swap negative twin; H2.
- [x] 5.3 `tests/scripts/test-sentry-alert-drift-workflow.sh`: `WF="${SENTRY_DRIFT_WF:-…}"`; W8 by `id` (whitespace-collapsed), asserting `!cancelled()`, both verdict arms, `filed != 'true'`, no `failure()`; W8-a..e + W9-a in-suite on PyYAML-mutated copies (landing assert re-loads the target field); W9 title parity; `EXPECTED_TESTS` 5 → 8.
- [x] 5.4 Register the new suite in `scripts/test-all.sh`; run the sentry group; `lint-shell-trace-credential-refusal.py --changed --base origin/main` → 0.

## Phase 6: Documentation and architecture record

- [x] 6.1 README §Drift detection: apply job derives its own reference; committed copy exists for the daily job only; regeneration recipe; captures are history; keep `29 + 2`.
- [x] 6.2 ADR-031 dated note `[2026-09-11 — #8050]` (text in the plan).
- [x] 6.3 `model.c4` `sentry -> founder` edge: 29 + 2 split, "plan-derived reference (#8050)"; `bash scripts/regenerate-c4-model.sh`; commit `model.likec4.json`; run `c4-model-freshness.test.sh` + `c4-code-syntax` + `c4-render` vitest suites.
- [x] 6.4 Confirm no `.tf` file is edited in this PR (`git diff --name-only origin/main -- '*.tf'` is empty).

## Phase 7: Verification and roll-forward

- [x] 7.1 Local live probe → `PASS (all 29 …)`, no FIXTURE token, no refusal line (never under `bash -x`).
- [ ] 7.2 Immediately before merge: `gh workflow run scheduled-sentry-alert-drift.yml --ref <branch>` → `clean`, `file_unavailable` skipped, #8057/#8058 closed by the mechanism. Defined outcomes for a refusal line (`gh secret set SENTRY_API_HOST --body jikigai-eu.sentry.io`, re-dispatch) and for a real unrelated drift (leave #8057 open; triage issue).
- [ ] 7.3 PR-time: `plan_pr` `0 to destroy`, reference gate PASS, `sentry-destroy-required` green.
- [ ] 7.4 PR body: `Closes #8050`, `Ref #8057`, `Ref #8058`; none in the title.
- [ ] 7.5 Post-merge: newest `apply-sentry-infra.yml` run on `main` is `success` (push, merge SHA), step 15 `PASS (all 29 …)`; #8050 CLOSED; next 07:15 drift run `clean`, no open `ci/sentry-alert-drift` issue.
