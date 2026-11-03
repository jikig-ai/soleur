---
feature: feat-local-test-gate-speed
issue: 12013
lane: cross-domain
brand_survival_threshold: single-user incident
status: draft
---

# Spec: local affected-test gate speed and observability

## Problem Statement

`soleur:ship` Phase 4 runs `scripts/test-all.sh --affected` serially. On 2026-11-03 a single-feature PR took more than 30 minutes (166 of 725 suites), and the one red appeared about 8 minutes in with no signal until the run ended. The parallel pool already exists (`--jobs`, PR #11282) but ship never enables it.

## Goals

- A typical single-feature PR finishes the local gate in under 10 minutes on a loaded machine.
- A red is printed when its suite finishes, with suite name and wall time.
- Slow edge-selected suites are re-priced so diffs that do not need them stop selecting them.

## Non-Goals

- Result cache (rejected twice; see `scripts/lib/test-affected-derive-cache.sh`).
- Pushing before the local battery (conflicts with ADR-276 and ADR-183; revisit trigger recorded in the brainstorm).
- Unconditional CI-only skip (conflicts with ADR-196/ADR-183).
- Changing the runner's serial default.

## Functional Requirements

- FR1: ship Phase 4 launches affected runs with `SOLEUR_TEST_JOBS=4`; `--full` and the default runner invocation are unchanged.
- FR2: under the pool, each suite verdict line (`[FAIL]`/pass with wall time) is printed at reap, not after the drain. No abort on first red.
- FR3: re-price edge selection for the seven slow edge-selected suites and give `destroy-ask-mutation` and `image-cve-verdict` measured weights in `scripts/suite-durations.tsv`.
- FR4: record the dispositions of all seven issue points, and the point-6 revisit trigger, on #12013.

## Technical Requirements

- TR1: the pool must stay serial when the advisory lock is not held (existing fallback) and must announce a serial fallback.
- TR2: legal-register lint registrations (`lint-legal-registers.sh`, `check-pa-22.sh`) stay in `run_suite` lines and are never skipped.
- TR3: soak the pool on a loaded host, including `git-data-replication`, before relying on it; ADR-242 amendment gets an addendum for the opt-in pool in ship.
- TR4: verify per-suite `TMPDIR` isolation under the pool; add it if the lane tokens do not give it.
