# Tasks: ci-head-verdict.sh stall clock (umbrella #9757 item 3, P3 only)

Plan: `knowledge-base/project/plans/2026-10-22-fix-ci-head-verdict-stall-clock-plan.md`. PR body `Ref #9757` only; merge via queue; no `--admin`.

## Phase 1: Failing tests first

- [ ] 1.1 Stub a `check-suites` route in `plugins/soleur/test/ci-head-verdict.test.sh` (exact argv from the plan; built-in default of one suite at T-3600; `suites.fail` / `suites.raw`)
- [ ] 1.2 Add `setsuites <dir> <offset...>` helper that REPLACES the default (no offsets writes an empty list)
- [ ] 1.3 Shift the V5 boundary rows (run anchor at T+2: 7202 pending, 7203 stalled) and keep V9, V17, V23 at 7800
- [ ] 1.4 Add rows V24 (run anchor), V25 (suite anchor, earliest-of-many), V26 (read failures, empty list, head_sha mismatch), V27 (laziness at T+7800)
- [ ] 1.5 Add the in-suite assertion that `st=stalled` appears exactly once in the script
- [ ] 1.6 Add mutants M37-M43 (named kill rows in the plan); raise `MIN_ASSERTIONS` and `MIN_MUTANTS` to the measured counts and note they are lower bounds
- [ ] 1.7 Run the suite red against the unmodified script (V24, V25, shifted V5 rows must fail); record the output for the PR body

## Phase 2: Core implementation (`plugins/soleur/scripts/ci-head-verdict.sh`)

- [ ] 2.1 `read_newest_run`: also set `RUN_TS` from the chosen run's `created_at`
- [ ] 2.2 Add `read_head_anchor` (shape check including `head_sha` equality, explicit empty-list error `no-check-suites`, `ANCHOR_REASON` reset on entry)
- [ ] 2.3 Replace the final stall `elif` with the two-step decision; keep the dirty/conflicting branch first; keep `>` strict; keep `st=stalled` single
- [ ] 2.4 Rewrite the header (single source of the rule), name the residuals, comment the call site; do not write the literal `STALL_MINUTES=120`
- [ ] 2.5 Suite green, `shellcheck` clean

## Phase 3: Prose and ADR

- [ ] 3.1 `monitor-pr-checks.sh` and `admin-merge-ready.sh`: replace "the stall window counts from the ready event" with "see ci-head-verdict.sh for the stall clock"
- [ ] 3.2 `plugins/soleur/skills/ship/references/ready-run-wait.md`: one clause pointing at the verdict script header
- [ ] 3.3 ADR-276: two-sentence dated addendum after the Supersession bullet

## Phase 4: Verify and ship

- [ ] 4.1 Run the consumer suites (admin-merge-ready, monitor-pr-checks, admin-merge-ready-wiring, drain-prs, ship-phase-7-poll-fixtures, ci-draft-light-soak-9728) and `c4-count-parity`, each detached with an rc file
- [ ] 4.2 Confirm the diff touches no `.github/workflows/**` or `apps/**` path (three-dot diff against `origin/main`)
- [ ] 4.3 File the tracking issues: one for P2, one checklist issue for P4a-P4d (`Ref #9757`, milestone `Post-MVP / Later`)
- [ ] 4.4 Ship; if the merge is held, ask ONE delegation question; merge through the queue
- [ ] 4.5 Post-merge: read-only `ci-head-verdict.sh verdict <open ready PR>` prints one marker

## Follow-up PRs (not in this PR, one each)

- [ ] P2 `merge-effect-class.sh` classifier (needs an ADR; own PR)
- [ ] P4a gitleaks per-commit pre-push check in ship Phase 6.4
- [ ] P4b `affected-tests.sh` selects the kb-consumers suite when a new fixture contains `knowledge-base/`
- [ ] P4c per-PR monitor lock (one monitor per purpose)
- [ ] P4d bounded wait then "CI is the gate" on a local battery refusal (rc=4)
