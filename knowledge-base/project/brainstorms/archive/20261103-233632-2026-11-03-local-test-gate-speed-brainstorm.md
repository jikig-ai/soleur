---
date: 2026-11-03
issue: 12013
branch: feat-local-test-gate-speed
lane: cross-domain
brand_survival_threshold: single-user incident
---

# Local affected-test gate: make it fast and observable (#12013)

## What We're Building

Make the `soleur:ship` Phase 4 local gate (`scripts/test-all.sh --affected`, via `plugins/soleur/scripts/affected-tests.sh`) finish in minutes instead of 30+, and report a red when it happens. Scope chosen by the operator: **enable the existing parallel pool in ship, add live red reporting, then re-price the slow edge-selected suites.** Points 2 (result cache), 6 (push before local battery) and 7 (unconditional CI-only skip) of the issue are dropped from this scope.

## Premise audit: most of the issue is already on main

| # | Issue point | State on main (verified) |
|---|---|---|
| 1 | Parallel pool | **Shipped, never enabled.** `--jobs=N|auto` / `SOLEUR_TEST_JOBS` (PR #11282, `scripts/test-all.sh` ~2148, lane-token scheduler in `scripts/lib/test-suite-lanes.sh`). Unset = serial. No reference in ship or `affected-tests.sh`, so the issue's run was serial. Env passes through `affected_bound bash "$RUNNER"`. Per-suite `TMPDIR` is not done. |
| 2 | Hash-keyed result cache | Open, but `test-affected-derive-cache.sh` header records a suite-result memo as rejected twice. Dropped. |
| 3 | Heaviest batteries CI-only | Partly shipped (ADR-262 pr-gates five; PR #11779 demoted 8). Of the 9 slow suites only `lint-shell-trace-credential-refusal` and `image-cve-verdict` are always-on; the other seven are edge-selected, pulled in by the diff. Open work is re-pricing edges. |
| 4 | Admission control | Shipped: FIFO ticket queue in front of the flock (`scripts/lib/test-contention.sh`, ADR-133, #8579). `tc_acquire "test-all"` is unconditional, so the issue's "affected runs are not queued" is false. |
| 5 | Fail fast / timings / logs | Timings shipped (`TEST_TIMING_LOG`, durable by default locally, #9814). Open: live `[FAIL]` line (verdicts print in registration order after the drain), pass-log retention, real-git quarantine. |
| 6 | Push before local battery | **Rejected by existing ADRs, see below.** |
| 7 | Skip local when CI covers it | Partly shipped: ADR-196 addendum P4d, `battery-refusal-wait.sh` exit 42, under contention only. Unconditional version conflicts with ADR-196 and ADR-183. |

## Why point 6 was rejected (operator asked)

ADR-276 does not forbid the reorder in one sentence; three of its decisions combine against it:

1. **It chose the opposite order on purpose.** Decision 3 (S3) names "the cheaper policy: no draft push before a local `--affected` run passes" and gates draft-PR light checks on a post-policy mean of at least 2.75 pushes per draft PR (break-even 2.2 on first-pass inputs, measured pre-policy mean 2.6). Local-first is the lever that lowers pushes.
2. **A draft `test` is red by design (Option R).** `battery-owed.sh` reads a context as satisfied only on a newest `success`, so a draft head returns OWED however early it is pushed. Pushing first gains nothing on a draft.
3. **Pushing a ready head starts a full required CI run** (about 95-137 job-minutes, 14-38 min wall, median about 28) on a head the local gate has not cleared. The skip only pays on the re-run after a review fix or main sync, which the skill already does on a pushed commit (measured on PR #8233: ~70 min of duplicate batteries).

ADR-183 also already rejected pinning the SHA at Phase 4, and the first-pass OWED is documented in `ship/SKILL.md` ("returns OWED by design").

**Ruling (CTO): do not revisit now.** With the pool the local gate drops to roughly 8 min against a roughly 28 min CI wall, so local-first gets stronger, not weaker. Revisit only if, after the pool lands, a typical single-feature gate still exceeds 10 min, or ADR-276's S3 post-policy push mean falls below 2.75. Record that trigger on the issue.

## Key Decisions

- Enable `SOLEUR_TEST_JOBS=4` for affected runs only, in the ship Phase 4 dispatch. Keep the runner default serial; flipping it is a separate decision tied to the #7376 interference diagnosis (closed 2026-10-20; soak follow-up #7432 open).
- "Fail fast" means **report at reap, not abort.** ADR-177's taxonomy separates a red from an unresolved run, and a real-git suite can fail only under load; aborting converts a false RED into lost coverage.
- Order: pool, then live report-at-reap, then edge re-pricing. No cache.
- Productize candidate: none. This is internal machinery (CPO: keep p3, fold under epic #11556 as a local-gate sibling; the user-facing contract belongs to #11556 Lever F, #11563).

## User-Brand Impact

- **Artifact:** the local affected-test gate (`scripts/test-all.sh --affected`) and its `soleur:ship` Phase 4 dispatch.
- **Vector:** a faster or parallel gate that silently drops or mis-reports a failing suite lets a regression reach `main` and then users.
- **Threshold:** `single-user incident`. Mitigations: CI's required `test` context stays the merge gate; caching is out of scope; legal-register lints stay in `run_suite` registrations (CLO).

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Engineering
**Summary:** CTO ruled pool first, report-not-abort, no cache, and rejected point 6 as conflicting with ADR-276. An unconditional point 7 conflicts with ADR-196 and ADR-183. The pool and live report need an addendum to the ADR-242 amendment.

### Product
**Summary:** CPO: keep p3, off the roadmap frontier, fold under epic #11556. Items 6 and 7 change ship behaviour users receive, so design their contract once with Lever F.

### Legal
**Summary:** CLO: no legal implications. Keep `lint-legal-registers.sh` and `check-pa-22.sh` registrations visible to the `run_suite` grep in the breach register, and never skip them from any cache or selection change.

## Open Questions

- Why three sibling worktrees were not serialized in the issue's run (unverified; queue is unconditional on paper).
- Does the pool stay green under load: `git-data-replication` F21 (real `git push`) failed once under load; needs a parallel-mode soak before it is relied on.
- Per-suite `TMPDIR` under the pool: unverified whether the lane tokens already isolate it.
- `destroy-ask-mutation` has no row in `scripts/suite-durations.tsv`; `image-cve-verdict` is a 1223 ms floor row. Scheduler weights for both are guesses.
- The stale "hedged always-on" comment at `scripts/test-all.sh` (kb-consumers) should be corrected when edges are re-priced.
