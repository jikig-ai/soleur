# Tasks: path-gate the self-test mutation batteries on PRs (#9323)

Plan: `knowledge-base/project/plans/2026-09-30-ci-path-gate-self-test-mutation-batteries-on-prs-plan.md`

## Phase 0: Spikes (record answers in the PR)

- [ ] 0.1 Confirm `bash scripts/test-all.sh --print-affected-set` emits derived edges for one label outside `--affected` mode; else choose the literal-operand fallback for Guard 2
- [ ] 0.2 Write `scripts/ci-battery-gate-replay.sh` first (<= 30 lines, one `git log --name-only`) and record per-battery run-rates over 300 commits
- [ ] 0.3 Re-verify ADR-262 is free across every `origin/*` ref

## Phase 1: RED tests first

- [ ] 1.1 Author `scripts/test-all-pr-battery-gate.test.sh` from Guard 1 matrix rows 1-12 plus harness rows H1-H2 (sandbox git repo, `CI=1 GITHUB_EVENT_NAME=pull_request`)
- [ ] 1.2 Confirm it is RED against the unmodified runner

## Phase 2: Core implementation

- [ ] 2.1 `scripts/test-all.sh`: add the `--pr-gated` arm to `_diff_touches` (force arms first; skip the `CI` short-circuit only when `GITHUB_EVENT_NAME == pull_request`)
- [ ] 2.2 `scripts/lib/test-relevance-paths.sh`: add `LINT_ORPHAN_BATTERY_PATHS`, `TAG_AUTHORSHIP_BATTERY_PATHS`, `TEST_ALL_AFFECTED_BATTERY_PATHS` (self-including battery file + predicate file + gate-machinery paths); update the six-site header
  - [ ] 2.2.1 Verify each declared path resolves (`git ls-files`) and lives under a `TEST_RELEVANCE_PREFIXES` entry
- [ ] 2.3 `scripts/test-all.sh`: wrap lint `-a`/`-b` in ONE `if _diff_touches --pr-gated "${LINT_ORPHAN_BATTERY_PATHS[@]}"` with two `skip_suite` calls; wrap tag-authorship-mutations and test-all-affected likewise; add `--pr-gated` to the registry and cf-tunnel sites
- [ ] 2.4 `scripts/test-all.sh`: add the four labels to `_suite_affected` EXEMPT LABELS and fix the stale count comment
- [ ] 2.5 `scripts/lib/test-affected-paths.sh`: withdraw the four labels from `ALWAYS_ON_SUITES`; add four consumed edges to `AFFECTED_CONSUMED_EDGES`
- [ ] 2.6 `scripts/lint-orphan-test-suites.sh`: three `RELEVANCE_ARRAYS` rows; widen `ref_re` to accept `( --pr-gated)?`; add the Guard 2 closure check
- [ ] 2.7 `scripts/test-all-infra-coverage-notice.test.sh`: four `GATED` rows and widen the `RUNNER_ARRAYS` regex with `( +--pr-gated)?`
- [ ] 2.8 Run the orphan linter and the coverage-notice harness; both must exit 0

## Phase 3: Measurement tooling and registration

- [ ] 3.1 `scripts/followthroughs/pr-battery-gate-saving-9323.sh` (pinned 76 runner-min baseline with its producing command in the header)
- [ ] 3.2 Register the guard suite LAST in its block in `scripts/test-all.sh`; classify `ALWAYS_ON`; add to `scripts/suite-shard-legs.tsv` via `regenerate-shard-manifest.py` dry-run then regen
- [ ] 3.3 Confirm `test-all-affected` s1/s2 report `ran>0` and `scripts-shard-totality` is green

## Phase 4: ADR and amendments

- [ ] 4.1 Create ADR-262 via `soleur:architecture create` (about one page; amends ADR-181 property 4 and ADR-242 decision 1; cite the ruleset read for "no merge queue")
- [ ] 4.2 Add `amended_by` and a one-paragraph amendment to ADR-181 and ADR-242 (including the ALWAYS_ON rationale for the four labels)
- [ ] 4.3 Run `bash plugins/soleur/test/c4-count-parity.test.sh`; cite the result in the PR

## Phase 5: Verification and follow-through

- [ ] 5.1 `bash scripts/test-all.sh --full` once; confirm `git diff origin/main...HEAD --stat` shows no `ci.yml` / `main-health-monitor.yml` change
- [ ] 5.2 On this PR's CI run confirm all five batteries RAN (machinery-degrade self-proof)
- [ ] 5.3 File deferral issues (reaper battery; non-mutation next-tier suites; c4/github-scripts/webplat arms; workflows-prefix narrowing; merge queue) with roadmap milestones
- [ ] 5.4 Enroll the soak: `follow-through` label and `soleur:followthrough` directive on #9323; PR body uses `Ref #9323`
