---
title: "Tasks — parallelize independent local test-all suites safely (#8231)"
branch: feat-one-shot-8231-parallel-test-all
issue: 8231
plan: knowledge-base/project/plans/2026-09-17-feat-parallel-local-test-all-suites-plan.md
lane: cross-domain
---

# Tasks

Derived from the plan after review. **Phase 0 can cancel this work** — two of its steps are go/no-go
gates, and reaching a stop verdict is a successful outcome, not a failure.

## Phase 0 — Measure and decide

- [x] 0.1.1 Guard `actual=$(bun --version)` at `scripts/test-all.sh:318-325` (`|| actual=""`, skip on
      empty) so `--enumerate` is toolchain-free as its own header claims.
- [x] 0.1.2 Record `--enumerate all` and the four per-group counts; confirm the four sum to `all`.
- [x] 0.1.3 Confirm every planned consumer fails closed on **rc and count**, copying the shape at
      `scripts/lint-orphan-test-suites.sh:229-232`.
- [x] 0.2.1 Record `$BASH_VERSION` and the `wait -n -p` probes, including the SIGTERM → 143 case.
- [x] 0.3.1 Measure the constrained view (`nproc` **inside** the scope), not the exit code. Record
      which mechanism this host provides and, if no memory constraint is available, record that H2
      will terminate UNKNOWN by construction.
- [x] 0.4.1 Run the serial baseline with `TEST_TIMING_LOG` set, a per-suite peak-RSS sampler, and a
      temporary log of every `tc_acquire` caller's pid and cmdline.
- [x] 0.4.2 Capture `sort -k2 -n -r "$TEST_TIMING_LOG" | head -20` verbatim.
- [x] **0.4a GATE** — compute `total_suite_ms ÷ longest_suite_ms` over the post-decline population.
      **Below 2× stops the work** and routes to #8045.
- [ ] 0.5.1 Derive the blocking subset from the caller log, measured **under an inherited
      `SOLEUR_ALLOW_FULL_GATE=1`** — a plain invocation takes ADR-196's refusing path and would
      measure the wrong condition.
- [ ] **0.5.2 GATE** — a majority wall-clock share for that subset is a no-go. Record the number and
      adopt `lock:test-all` unconditionally; re-entrancy is prohibited by ADR-196 D1/D7.

## SCOPE — this branch ships Phase 0 only (decided 2026-09-17)

Phase 0 completed and **0.4a PASSED at 6.28x**, so the prize is real. Phases 1-5 are **BLOCKED**,
not abandoned, on a precondition the plan did not anticipate and that is outside #8231's scope to
establish:

> Phase 1 attributes interference by repetition; Phase 4 gates correctness by fault injection.
> Both require a baseline in which a RED suite is a signal. The serial baseline measured **21
> failing suites**, only 8 of them toolchain-adjacent — 13 are red for unrelated reasons. A verdict
> table built on that tree is UNKNOWN by construction.

#8231 therefore stays OPEN and this branch carries no `Closes`. Evidence and the exact blocker are
in `acceptance-evidence.md`.

## Phase 1 — Diagnose #7376 (its own commit, ahead of any fix)

- [ ] 1.1.1 Record the K ≥ 7 reproduction loop in `diagnosis.md` as a command, not a script.
- [ ] 1.2.1 Add `peak_rss_kb` (from the **child's** `VmHWM`), `fd_used_max` and `avail_mem_mb_min` to
      the existing per-suite record, parent-side only.
- [ ] 1.2.2 Derive `concurrent=<labels>` by interval intersection over the offsets already in
      `.meta`; add no new plumbing and note that the inputs remain child-written.
- [ ] 1.3.1 Implement `wrote_outside_sandbox` as an mtime sweep over a declared root set including
      gitignored build outputs. No `git status`; any surviving `git` call carries
      `--no-optional-locks`.
- [ ] 1.3.2 Emit `attributed_to=<set in flight>` beside it, and write its retirement trigger.
- [ ] 1.4.1 Run the loop; record the raw table in `acceptance-evidence.md`.
- [ ] 1.5.1 Write `diagnosis.md`'s verdict table. UNKNOWN is a permitted terminal state and must be
      written as UNKNOWN rather than argued away.

## Phase 2 — Fix what Phase 1 attributed

- [ ] 2.1 Apply only the remedies the verdicts attribute; each with a **deterministic** mutation row
      in `run-registered-suites.test.sh`.
- [ ] 2.2 Record the #7432 disposition explicitly: the `JOBS: 1` pins and check (12) are **not**
      removed here.

## Phase 3 — The scheduler (RED first)

- [ ] 3.1.1 Write `scripts/lib/test-suite-lanes.sh`: the classifier over registered suite source,
      plus the override table, each override carrying a hand-written `reason`.
- [ ] 3.1.2 Seed the overrides from the collision inventory, keyed on the **label `--enumerate`
      emits** — `blog-link-validation`, `scripts/orphan-process-reaper-mutations`, not file paths.
- [ ] 3.1.3 Recompute the Amdahl ratio over the derived-parallel set; feed it back to 0.4a.
- [ ] 3.2.1 Write the guard first: `scripts/test-all-parallel-scheduler.test.sh`, every parallel arm
      under `env -u CI`, with the H4 arm-mode harness row.
- [ ] 3.2.2 Add the census to `scripts/lint-orphan-test-suites.sh` and its rows to that linter's
      mutation battery.
- [ ] 3.3.1 Implement dispatch: `( exec "$@" ) >"$CAP/$idx.out" 2>"$CAP/$idx.err" &` behind a
      semaphore. The `exec` is load-bearing — without it every worker reads as a sibling run.
- [ ] 3.3.2 Implement the collector with `wait -n -p pid -- "${live_pids[@]}"`, with branches for a
      map miss, rc 127 with an empty pid var, and `128+N` with an unset pid var.
- [ ] 3.3.3 Render drain-then-print in registration order through the **existing** classification
      block; replay `.out` to stdout and `.err` to stderr.
- [ ] 3.3.4 Emit the `[run] … started` / `[run] … done` liveness pair on stderr.
- [ ] 3.4.1 Suppress `tmp_delta` for any suite whose window intersected another's; widen
      `_repo_last_suite` to a set and update `repo-write-boundary.sh` and its content-anchored suite.
- [ ] 3.4.2 Implement `SOLEUR_TEST_JOBS` resolution, validation (`exit 2`), clamping, and budget
      propagation to `cpu:pool` suites.
- [ ] 3.5.1 Implement the six-condition fallback with its stated precedence, including the
      lock-was-not-taken condition.
- [ ] 3.6.1 Implement the ceiling drain, the INT/TERM trap, and the no-exit-while-live invariant.
- [ ] 3.7.1 Register the new suite with an explicit `run_suite` line; confirm
      `lint-orphan-test-suites.sh` reports no orphans.

## Phase 4 — Correctness gate, benchmark, default

- [ ] 4.1.1 Build the two-arm benchmark; pin `TC_RUNTIME_CEILING_S` beyond reach and assert
      `_ceiling_declined == 0` on both arms.
- [ ] 4.2.1 Run the fault-injection triple at width 1 and `P_measured`.
- [ ] 4.2.2 Record `total_suite_ms`, `longest_suite_ms` and the implied ceiling.
- [ ] 4.2.3 Record three repeat runs **as an observation**, with the power calculation beside them.
- [ ] 4.3.1 Evaluate conditions (a)-(e); ship the mode they license and record every measured value.

## Phase 5 — Record

- [ ] 5.1.1 Re-derive the ADR ordinal across all `origin/*` refs immediately before merge; sweep the
      feature's artifacts on any renumber.
- [ ] 5.1.2 Write ADR-225 with `amends: [ADR-133, ADR-177, ADR-181]`; land the ADR-133 half as a
      dated addendum in that file per its own append-only convention.
- [ ] 5.1.3 Give UNACCOUNTED a rendered marker and a place in the breakdown line and the ladder.
- [ ] 5.2.1 Write the runbook: local parallel vs CI shards, the serial fallback, reading the banner,
      what the tokens mean.
- [ ] 5.2.2 Record the `ci.yml:961-965` K-shard coupling in that workflow's comment.
- [ ] 5.3.1 Comment the diagnosis link on #7376 and #7432; note on #7454 Item 1 that its bytes-probe
      re-evaluation trigger is unsatisfiable as written and what replaced it. Close **only** #8231.
