# Tasks: drift threshold honest CI term + PR fan-out ledger (no merge queue)

Plan: `knowledge-base/project/plans/2026-09-14-chore-drift-threshold-ci-term-and-pr-fanout-ledger-plan.md`

## Phase 0: Preconditions (read-only)

- [ ] 0.1 `DRIFT_TEST_PARTS=AB bash scripts/prod-version-drift-check.test.sh 2>&1 | grep -E "B9|B8e"` shows `B9 ... (207m) >= ... (195m)` and `B9c ... (70m)`
- [ ] 0.2 `gh api repos/github/codeql-action/issues/1537 --jq .state` → `open` (if `closed`: STOP and re-plan Item 2 against ADR-032's re-adoption recipe)
- [ ] 0.3 Confirm `fix-constraints-stage-a.yml` has a per-head-SHA group and `rls-authz-fuzz.yml` a per-ref group, both `cancel-in-progress: true` (decides their ledger `cancel` values)

## Phase 1: Item 1 — honest B9 (RED first; the coupled sites land in ONE commit)

- [ ] 1.1 Part C: add `mutate_and_assert_green` (same sandbox + landing check; asserts child exit 0); add value-agnostic RED axes `axis13-raise-ci-test-scripts-ceiling` (→130), `axis14-raise-resolve-target-ceiling` (→70), `axis15-raise-release-ceiling` (reusable-release `jobs.release` →130), expected label `B9 threshold`; add `green1-lower-resolve-target` (→10) and `green2-test-scripts-at-boundary` (→65); `MIN_C` 13 → 18, `MIN_ASSERTIONS` 151 → 156
  - [ ] 1.1.1 `DRIFT_TEST_PARTS=C bash scripts/prod-version-drift-check.test.sh` → axis13 and axis14 report `SURVIVED` (record for the PR body); axis15 caught; greens pass
- [ ] 1.2 `plugins/soleur/test/workflow-run-deploy-invariants.test.sh`: G5-21 loop gains `resolve-target`; G5-18 regex tightened to `CI_BUDGET_MIN=\$\(\(\s*THRESHOLD - RT - M - V - D`
  - [ ] 1.2.1 Run it → G5-18 and the `resolve-target` call-form row FAIL (record)
- [ ] 1.3 ONE commit (run every suite against the STAGED tree before committing):
  - [ ] 1.3.1 `scripts/prod-version-drift-check.sh`: `DRIFT_SUSTAINED_THRESHOLD_MIN=225`; header formula `max(ci, release) + resolve-target + migrate + verify-migrations + deploy`; dated `207 -> 225 (2026-09-14)` paragraph (same-commit reason; 5 m slack = rounding only, queue wait empirical; 18 m cost inside the 61–243 m delivery interval). The only numeric literals live here and in the ADR addenda
  - [ ] 1.3.2 `scripts/prod-version-drift-check.test.sh`: `crit = max(ci_declared_path, release_ceiling) + job_timeout("resolve-target") + migrate + verify + deploy`; dated decision comment replaces `ci_declared_path is NOT in this sum`; B9 labels keep the `B9 threshold` prefix, object renamed "declared merge-to-deploy critical path"; FAIL text carries the one-line remedy (raise the constant in the SAME commit + dated header line; the workflow re-derives); one axis greps its own expected label from the live test; comment above B9 updated; no apostrophes in interpolated blocks
  - [ ] 1.3.3 `.github/workflows/web-platform-release.yml`: `resolve-target` `timeout-minutes: 15` + rewritten ceiling comment (measured max 14 s over nine `workflow_run`-arm runs ending 2026-09-14; #8020 floor convention; additive term; fails closed loud if the poll ever goes live; cites constant/B9 by name, no derived number); budget step reads `RT=$(job_ceiling "$REL" resolve-target)`, emptiness loop, `CI_BUDGET_MIN=$(( THRESHOLD - RT - M - V - D ))`, comment names terms with no numeric reading, `::error::`/`::warning::` texts name `resolve-target`, note that release is deliberately not read here; `deploy` job comment → term names + "computed by B9", no numbers
  - [ ] 1.3.4 `.github/workflows/reusable-release.yml`: "COUPLED (#7160)" comment → "reads as the GitHub 360 default and reds B9 by name", no figure
  - [ ] 1.3.5 `.github/workflows/scheduled-prod-version-drift.yml`: "threshold 195m" comment → the constant by name
  - [ ] 1.3.6 `DRIFT_TEST_PARTS=ABC bash scripts/prod-version-drift-check.test.sh` → green; `B9 threshold (225m) >= declared merge-to-deploy critical path (220m)`; axes 13/14/15 caught; green1/green2 pass
  - [ ] 1.3.7 `bash plugins/soleur/test/workflow-run-deploy-invariants.test.sh` (67 rows) and `bash plugins/soleur/test/resolve-target-decision.test.sh` → green
  - [ ] 1.3.8 `actionlint` on `web-platform-release.yml` + `reusable-release.yml`; `bash -n` over the extracted budget `run:` body
- [ ] 1.4 One-time verifications, outputs pasted into the PR body: delete `deploy`'s ceiling → B9 RED; drop ci.yml from `make_sandbox` → B9c RED / C0 red; B9 `-ge`→`-le` → RED
- [ ] 1.5 ADR-217 Decision 4 `> **Addendum (2026-09-14).**` + strike-through note on the `= 72` bullet ("see the addendum below" — never the heading literal); ADR-212 one dated pointer line

## Phase 2: Item 2 — fan-out reduction + ledger (RED first)

- [ ] 2.1 Create `scripts/pr-fanout-ledger.txt` from the CURRENT tree (21 rows; `ci.yml` 25; `cancel=no` on the five target workflows and on `fix-constraints-stage-a.yml`; `cancel=yes` on `rls-authz-fuzz.yml` and `pr-auto-close-scanner.yml`; header per plan: cancel = form AND group shape, TAB columns, ceiling-not-floor sentence, ci.yml row cites `required-checks.txt`)
- [ ] 2.2 Create `plugins/soleur/test/pr-fanout-ledger.test.sh` Part A (A0 direct-exit floor ≥ 15; A-parse; A1–A5 with the messages in the plan; A4c; A7 inline `if [[ "$CASES" -lt N ]]` counter floor); `source plugins/soleur/test/test-helpers.sh`; enumerator handles `on` list/string/True-key, `pull_request: null`, string `types`, string `concurrency`, job-level cancel, `pull_request_target`; run → green on the live tree (a red = the header rule and the tree disagree; fix the rule)
- [ ] 2.3 Add Part B (Guard 2 rows 1–10 incl. 6b/6c/6d over a temp copy via `PR_FANOUT_WORKFLOWS_DIR`/`PR_FANOUT_LEDGER`); run → every mutant caught, must-PASS rows green
  - [ ] 2.3.1 `scripts/guard-vacuity-floor.test.sh`: `MIN_FIRING_SUITES` 38 → 39; run it → green with the new suite counted
- [ ] 2.4 Fold `readme-counts`, `encryption-posture`, `lint-conversations-update-callsites`, `rule-metrics-shape` into `lint-bot-statuses` as four steps BEFORE `Install actionlint`, each with `if: ${{ !cancelled() }}`, verbatim `env:` (incl. `METRICS_FILE: knowledge-base/project/rule-metrics.json`) and `run:`, old job name leading the step name; delete the four jobs; ceiling comment (11 → 15 steps); dispatch-note parenthetical "(19 after the 2026-09-14 fold)"
  - [ ] 2.4.1 ledger row `ci.yml` 25 → 21; `actionlint .github/workflows/ci.yml`; `bash plugins/soleur/test/ci-concurrency-key.test.sh` → green
- [ ] 2.5 Add ci.yml's workflow-level `concurrency` block verbatim (group + cancel ternary) to `pr-quality-guards.yml`, `secret-scan.yml`, `dependency-review.yml`, `legal-doc-cross-document-gate.yml`, `skill-security-scan-pr-trailer.yml`
  - [ ] 2.5.1 ledger suite → A4b reds on all five (record); flip rows to `cancel=yes` → green; `actionlint` the five files
- [ ] 2.6 `DRIFT_TEST_PARTS=B bash scripts/prod-version-drift-check.test.sh` → B9b `0 <= 0`, B9c `70m`
- [ ] 2.7 ADR-032: `> **Addendum (2026-09-14).**` under the 2026-06-30 amendment (capacity factor, `check_response_timeout` vs 28-min spread, reopener (iii), producer/`merge_group` enumeration, pointer to ADR-216 addendum); ADR-216: `### Addendum 2026-09-14 — the second instance: the per-PR workflow generator` (row, fold, cancel set + 3 exclusions, ledger + test, the two things not done). No new ADR file; no INDEX regeneration
- [ ] 2.8 One-time verification (Guard 2 row 11: A1 against the ledger's own set → row 1 goes green) recorded in the PR body
- [ ] 2.9 `bash plugins/soleur/test/c4-count-parity.test.sh`; `bash plugins/soleur/skills/constraint-scaffold/test/parity.test.sh` → green

## Phase 3: Whole battery and evidence

- [ ] 3.1 `bash scripts/test-all.sh` → exit 0
- [ ] 3.2 `python3 scripts/lint-guard-contract.py <plan>` → 0 failures; `python3 scripts/lint-infra-no-human-steps.py <plan>` → OK
- [ ] 3.3 Walk AC1–AC18 in the plan; every command's output pasted into the PR body
- [ ] 3.4 PR body: RED-first evidence (axis13/axis14 SURVIVED → caught; G5-18 red → green; ledger A4b flip), one-time rows, declared-job count 56 → 52 (19 cancellable on a superseded push), `resolve-target` measurement; no `Closes` (no work-target issue); `ship` renders `decision-challenges.md` (UC-1)
