# Tasks: path-gate the self-test mutation batteries on PRs (#9323)

Plan: `knowledge-base/project/plans/2026-09-30-ci-path-gate-self-test-mutation-batteries-on-prs-plan.md`

## Phase 0: Spikes (record answers in the PR)

- [x] 0.1 Confirm `bash scripts/test-all.sh --print-affected-set` emits derived edges for one label outside `--affected` mode; else choose the literal-operand fallback for Guard 2 — spike answer: `--print-affected-set` emits only a class per label (no edge sets) and takes ~2.5 min, so Guard 2 uses the literal `$REPO_ROOT/<path>` operand fallback; directory/corpus operands go through a written-reason allowlist
- [x] 0.2 Write `scripts/ci-battery-gate-replay.sh` first (<= 30 lines, one `git log --name-only`) and record per-battery run-rates over 300 commits — replay over 300 first-parent commits: registry 23%, cf-tunnel 26%, lint-orphan 38%, tag-authorship 26%, test-all-affected 21% (arrays now carry the machinery set)
- [x] 0.3 Re-verify ADR-262 is free across every `origin/*` ref — ADR-262 free on every origin/* ref (checked 2026-09-30)
- [x] 0.4 Enumerate-consumer audit: `CI=1 GITHUB_EVENT_NAME=pull_request --enumerate-commands` on a docs-only fixture, byte-identical before/after; run shard-totality, linter census, fanout-suite-scope, battery-tag-authorship under that env — enumerate stream byte-identical under CI=1 + pull_request (guard suite section 2)
- [x] 0.5 Declare test-all-affected's subject set by dependency (runner, three libs, linter, itself); keep the measured `scripts/` prefix (54%) as fallback — declared by dependency (runner, libs, linter, itself)

## Phase 1: RED tests first

- [x] 1.1 Author `scripts/test-all-pr-battery-gate.test.sh` from Guard 1 matrix rows 1-12 plus harness rows H1-H2: mutate COPIES in `$TMP` with count==1 block-scoped substitutions, `bash -n`, env isolation (`env -u CI -u GITHUB_EVENT_NAME ...`), neutered `tc_acquire`, `RECORDED_SUITE:<label>` positive assertions, instrument control first, 60 s budget
- [x] 1.2 Confirm it is RED against the unmodified runner

## Phase 2: Core implementation

- [x] 2.1 `scripts/test-all.sh`: add the `--pr-gated` arm to `_diff_touches` (force arms first; inert under `_ENUMERATE==1`; skip the `CI` short-circuit only when `GITHUB_EVENT_NAME == pull_request`); add the ~8-line canary (`PR_GATE_CANARY_FAILED` forces run-all); increment `_relevance_declined` in every new else-arm; rewrite the `_diff_touches` header and `_suite_affected` FAIL-SAFE "CI runs everything" comments
- [x] 2.2 `scripts/lib/test-relevance-paths.sh`: add `LINT_ORPHAN_BATTERY_PATHS`, `TAG_AUTHORSHIP_BATTERY_PATHS`, `TEST_ALL_AFFECTED_BATTERY_PATHS` (self-including battery file + predicate file + gate-machinery paths); update the six-site header
  - [x] 2.2.1 Verify each declared path resolves (`git ls-files`) and lives under a `TEST_RELEVANCE_PREFIXES` entry
- [x] 2.3 `scripts/test-all.sh`: wrap lint `-a`/`-b` in ONE `if _diff_touches --pr-gated "${LINT_ORPHAN_BATTERY_PATHS[@]}"` with two `skip_suite` calls; wrap tag-authorship-mutations and test-all-affected likewise; add `--pr-gated` to the registry and cf-tunnel sites
- [x] 2.4 `scripts/test-all.sh`: add the four labels to `_suite_affected` EXEMPT LABELS and fix the stale count comment
- [x] 2.5 `scripts/lib/test-affected-paths.sh`: withdraw the four labels from `ALWAYS_ON_SUITES`; add four consumed edges to `AFFECTED_CONSUMED_EDGES`
- [x] 2.6 `scripts/lint-orphan-test-suites.sh`: three `RELEVANCE_ARRAYS` rows; widen `ref_re` to accept `( --pr-gated)?`; add the Guard 2 closure check over explicit file operands with a declared allowlist (reason per entry) for whole-directory/corpus operands
- [x] 2.7 `scripts/test-all-infra-coverage-notice.test.sh`: four `GATED` rows and widen the `RUNNER_ARRAYS` regex with `( +--pr-gated)?`
- [x] 2.8 Run the orphan linter and the coverage-notice harness; both must exit 0

## Phase 3: Measurement tooling and registration

- [x] 3.1 `scripts/followthroughs/pr-battery-gate-saving-9323.sh` per followthrough-convention: xtrace-refusal prologue (78), no `: "${VAR:?}"`, exit 2 on < 20 qualifying runs, window pinned to the merge SHA, exclude bot/cancelled/machinery-touching PRs, escape-rate check (push run red where PR green), queue wait informational; pinned 76 runner-min baseline with its producing command in the header
- [x] 3.1b `scripts/ci-battery-gate-replay.sh` falls back to `HEAD` when `origin/main` is absent and prints `run_rate` unconditionally
- [x] 3.2 Register the guard suite LAST in its block in `scripts/test-all.sh`; classify `ALWAYS_ON`; add to `scripts/suite-shard-legs.tsv` via `regenerate-shard-manifest.py` dry-run then regen
- [x] 3.3 Confirm `test-all-affected` s1/s2 report `ran>0` and `scripts-shard-totality` is green

## Phase 4: ADR and amendments

- [x] 4.1 Create ADR-262 via `soleur:architecture create` (about one page; amends ADR-181 property 4 and ADR-242 decision 1; cite the ruleset read for "no merge queue"; name residuals R1 escape/recovery + force-full lever, R2 trust root, R3 corpus blind spots, R4 bot PRs)
- [x] 4.2 Add `amended_by` and a one-paragraph amendment to ADR-181 and ADR-242 covering every statement that becomes false (ADR-181 property 4, Scope, Consequences; ADR-242 decision 1, merge-gate line, serial-battery line, accepted-residual bound; ADR-183 wording; ALWAYS_ON rationale for the four labels)
- [x] 4.3 Run `bash plugins/soleur/test/c4-count-parity.test.sh`; cite the result in the PR

## Phase 5: Verification and follow-through

- [ ] 5.1 `bash scripts/test-all.sh --full` once; confirm `git diff origin/main...HEAD --stat` shows no `ci.yml` / `main-health-monitor.yml` change
- [ ] 5.2 On this PR's CI run confirm all five batteries RAN (machinery-degrade self-proof)
- [x] 5.3 File deferral issues (reaper battery; non-mutation next-tier suites; c4/github-scripts/webplat arms; workflows-prefix narrowing; merge queue) with roadmap milestones — consolidated into ONE tracker, #9340
- [ ] 5.4 Enroll the soak: `follow-through` label and `soleur:followthrough` directive on #9323; PR body uses `Ref #9323`
