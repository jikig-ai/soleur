# Tasks: skip the duplicate push-to-main CI run (S2 of ADR-276, #9512)

Plan: `knowledge-base/project/plans/2026-10-09-ci-skip-duplicate-push-main-run-s2-plan.md`

## Phase 0: Tests first

- [ ] 0.1 `scripts/ci-push-dedupe.test.sh` (extract-and-execute proof body, parity, truth table, Guard 1 matrix rows 1-12), RED on the unmodified `ci.yml`; register it in `scripts/test-all.sh` in the same commit
- [ ] 0.2 Extend `plugins/soleur/test/ci-test-aggregator-diagnosis.test.sh` (W2 counts the non-leg `push-dedupe` need; aggregator body, `env:` and loop byte-identical)

## Phase 1: Measurements and ADR amendments (before any `.github/` edit)

- [ ] 1.1 Commit `measurements/keying-2026-10-09.tsv` (push runs, matching `merge_group` runs, `test` job conclusion) and `measurements/push-cost-baseline.tsv` (census `ci.yml` push rows for 2026-10-07T13:04Z-19:04Z)
- [ ] 1.2 Classify the 8 push-only reds (does the next push run fail the same job)
- [ ] 1.3 Append the ADR-276 S2 amendment (Edit tool, unique anchor; `git diff origin/main` shows 0 deletions; status stays `proposed`)
- [ ] 1.4 Append the ADR-217 amendment and `amended_by: [ADR-276]` (1 changed frontmatter line only)
- [ ] 1.5 `bash scripts/check-adr-ordinals.sh`; commit

## Phase 2: Workflow change

- [ ] 2.1 Compute the release workflow's CI budget slack (`run_declared_path`, B9) on the unedited tree; set the `push-dedupe` `timeout-minutes` to fit
- [ ] 2.2 Add the `push-dedupe` job and the eight `needs`/`if` edits in `.github/workflows/ci.yml`; comment above the job
- [ ] 2.3 `scripts/pr-fanout-ledger.txt` `ci.yml` row 24 to 25 from `yaml.safe_load(...)['jobs']`, with consequence text
- [ ] 2.4 Suites GREEN: proof suite, aggregator diagnosis, fan-out ledger, concurrency key, deploy invariants, `prod-version-drift-check.test.sh`

## Phase 3: Probe and registrations

- [ ] 3.1 `scripts/followthroughs/ci-push-dedupe-soak-9512.sh` and `.test.sh` (Guard 2 rows 1-6)
- [ ] 3.2 File the follow-through tracker issue (directive, labels, milestone, `User-Impact:` and `Fix-Size:` lines)
- [ ] 3.3 Registrations: `scripts/test-all.sh`, `regenerate-shard-manifest.py --incremental --write`, `scripts/lib/test-affected-paths.sh` edges, kb-consumers baseline rows if needed
- [ ] 3.4 Read the three followthrough probes and two skill references for a "test job ran" or "full push run" assumption

## Phase 4: Direct pre-push verification (detached, output to a file, Monitor to wait)

- [ ] 4.1 Proof suite, aggregator diagnosis, fan-out ledger, concurrency key, deploy invariants, drift check, probe suite
- [ ] 4.2 `scripts/test-affected-kb-consumers.test.sh`, `.claude/hooks/grep-q-pipe-guard.test.sh`, `scripts/guard-vacuity-floor.test.sh`
- [ ] 4.3 `lint-guard-contract.py`, `check-adr-ordinals.sh`, `c4-count-parity.test.sh`
- [ ] 4.4 Loaded-machine loop (50 runs) for any suite using `timeout`, `sleep`, `date` arithmetic, signals or process groups

## Phase 5: Ship and post-merge

- [ ] 5.1 PR body: Status question first, `Closes #9512`, closing Claude Code line; canary on the PR's own runs (gated jobs run, `push-dedupe` skipped; secret-scan false arm)
- [ ] 5.2 PM-1 S1 evidence census, attached to #9727 and #9512
- [ ] 5.3 PM-2 shadow gate and activation on the operator's explicit go (ADR reads `adopting`)
- [ ] 5.4 PM-3 first-run canary; PM-4 7-day soak and exit census; PM-5 docs-only status PR
