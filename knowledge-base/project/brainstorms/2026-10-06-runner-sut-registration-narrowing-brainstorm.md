---
topic: runner-sut-registration-narrowing
issue: 9564
lane: cross-domain
brand_survival_threshold: single-user incident
date: 2026-10-06
outcome: keep-deferred
---

# Brainstorm — drop non-runner-SUT heavy batteries from the registration-only bounded selection (#9564)

## What We're Building

Nothing yet. #9564 asks for a "declared runner-SUT set per suite" so that four heavy mutation batteries (13.6 min of the ~58.6 min bounded selection a registration-only runner edit now pays, ADR-242 decision 20) stop running when they are selected only because the runner is in their edge set. The brainstorm tested the issue's premise and its trigger against `origin/main` and concluded: **keep deferred, correct the issue's premise, sharpen the trigger.**

## User-Brand Impact

- **Artifact:** the affected-suite selection in `scripts/test-all.sh` / `scripts/lib/test-affected-paths.sh` (Soleur's own local pre-ship gate).
- **Vector:** a wrong runner-SUT declaration would silently narrow a safety gate, so a regression in a registry / cf-tunnel / reaper battery could reach the local green verdict. CI's full sharded battery stays the authoritative merge gate.
- **Threshold:** single-user incident (always-on default, #5175). CPO's read: no end user is touched; the exposure is contributor/agent trust in a gate verdict.

## Why This Approach (keep deferred)

- **Trigger not met.** #9552 merged 2026-10-06; one registration-only runner PR since; #9564 has 0 comments; nobody has measured a contributor's wait. Saving is 13.6 of 58.6 min (23% of the bounded selection, 15% of the full battery) against a 21.7 min always-on floor.
- **The issue's premise is only half right** (CTO, re-verified on `origin/main`):
  - `scripts/test-all.sh` is a closure leaf (decision 18), so the edge is *declared*, never derived.
  - `registry-gate-mutation-battery` and `cf-tunnel-liveness-gate-mutations` reach the runner through `PR_GATE_MACHINERY_PATHS` (`scripts/lib/test-relevance-paths.sh`, ADR-262): editing the predicate must arm every PR-gated battery. That is deliberate arming, not an accidental self-inclusion.
  - `orphan-process-reaper-mutations` **does** read the runner: its sandbox symlinks `scripts/test-all.sh` (`scripts/orphan-process-reaper-mutation.test.sh:79`). It is runner-SUT and must stay selected.
  - `registry-delivery-change-mutation-battery` lists `scripts/test-all.sh` in its declared array, but the only mention of `test-all` in the suite is a comment (`tests/scripts/test-registry-delivery-change-mutation-battery.sh:10`). That edge is a generator artifact.
- **A per-suite runner-SUT marker is the wrong mechanism.** It is a hand-list; ADR-193 §5 says populations are derived, never listed. It would also need its own guard contract and mutation tests, likely costing more than the minutes saved (CPO + CTO).
- **Concept is Soleur-repo-only.** Users' repos use native affected selection (epic #9307 PR 2); a test runner is not an input to its own suites there. Keep "runner-SUT" out of the PR 2 spec and user docs.

## Key Decisions

| Decision | Choice |
|---|---|
| Build now? | No — keep deferred (operator confirmed 2026-10-06) |
| Mechanism if ever built | Not a per-suite marker. Cheaper path below. |
| Trigger | Replace "13.6 min dominates a wait" with a measured wait after #9552 (registration-only runs observed at bounded cost), or the gate again being the slowest PR step |
| Productize candidate | none |

**Cheaper alternative recorded for the day the trigger fires (CTO):** (1) make the declaration generator ignore comment-only path mentions (drops the registry-delivery edge, ~49 s, for free); (2) under `registration-only`, skip the `PR_GATE_MACHINERY_PATHS` runner arm for the two PR-gated batteries (~11 min), because decision 20's closed grammar (G1: no removed lines) proves a registration-only diff cannot change the predicate or shard-leg set. Add rows to `scripts/test-all-affected.test.sh`.

**Fail-toward-coverage hazards for that day:** a blanket "drop edge-selected suites under registration-only" would wrongly drop suites that read the registration corpus (the `lint-orphan-test-suites-mutations-*` pair, shard-leg parity checks); `orphan-process-reaper-mutations` must stay; the read recorder `scripts/audit-suite-reads.sh` is operator-run, so a read added later would not be caught automatically.

## Open Questions

- `registry-gate-mutation-battery`'s 491 s is the issue's figure; `scripts/suite-durations.tsv` has no row for that label (the other three match: 162 + 113 + 49 s). Unverified here; re-check against manifest weights before any build.
- The CTO's claim that exactly one registration-only runner PR has merged since #9552 is a `git log` reading, not independently re-counted.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Product

**Summary:** Stay deferred. Only contributors/agents pay the wait; no end user is touched. Risk is correctness of a narrowed safety gate. Concept is Soleur-repo-only and must not leak into PR 2.

### Engineering

**Summary:** Keep deferred. Edges are declared (decision 18, ADR-262), two of four batteries are legitimately runner-armed, one genuinely reads the runner, one is a comment artifact. Prefer the two small classifier/generator changes over a per-suite concept.

### Legal

**Summary:** No legal relevance. No legal record or ADR-242 treats the local gate as a compliance control; CI's full battery is the merge gate. Wording: "affected-suite gate passed, CI full battery authoritative", never "tests verified". The CLO did not open `knowledge-base/legal/audits/2026-09-counsel-review-7226.md` (audit record, low risk).
