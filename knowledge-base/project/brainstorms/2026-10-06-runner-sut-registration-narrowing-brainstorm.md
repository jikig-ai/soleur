---
topic: runner-sut-registration-narrowing
issue: 9564
lane: cross-domain
brand_survival_threshold: single-user incident
date: 2026-10-06
status: deferred
outcome: keep-deferred
---

# Brainstorm — drop non-runner-SUT heavy batteries from the registration-only bounded selection (#9564)

## What We're Building

Nothing yet. #9564 asks for a "declared runner-SUT set per suite" (an issue-coined term, not in `knowledge-base/project/glossary.md`) so that four heavy mutation batteries (13.6 min of the ~58.6 min bounded selection a registration-only runner edit now pays, ADR-242 decision 20) stop running when they are selected only because the runner is in their edge set. The brainstorm tested the issue's premise and its trigger against `origin/main` and concluded: **keep deferred, correct the issue's premise, restate the trigger as a measurement.**

## User-Brand Impact

- **Artifact:** the affected-suite selection in `scripts/test-all.sh` / `scripts/lib/test-affected-paths.sh` (Soleur's own local pre-ship gate).
- **Vector:** a wrong narrowing would silently shrink a safety gate, so a regression in a registry / cf-tunnel / reaper battery could reach the local green verdict. The merge-time backstop is CI's `merge_group`/`push` runs, which execute every battery (ADR-262); `pull_request` CI declines the five PR-gated batteries when the diff touches none of their paths.
- **Threshold:** single-user incident (always-on default, #5175). CPO's read: no end user is touched; the exposure is contributor/agent trust in a gate verdict.

## Why This Approach (keep deferred)

- **Trigger not met.** #9552 merged 2026-10-06; `git log 2cfef66506..origin/main -- scripts/test-all.sh scripts/lib/test-affected-paths.sh` is empty, so **no** runner PR has been observed at the bounded cost since; #9564 had 0 comments at brainstorm time; nobody has measured a contributor's wait. Saving is 13.6 of 58.6 min (23% of the bounded selection, 15% of the full battery; all four durations are in the manifests: `scripts/suite-durations.tsv` for three, `scripts/suite-durations-heavy.tsv:9` for `registry-gate-mutation-battery` at 491 s) against a 21.7 min always-on floor.
- **The issue's premise is only half right** (re-verified on `origin/main`):
  - `scripts/test-all.sh` is a closure leaf (decision 18), so a text mention cannot derive the edge; for these four suites it is *declared*.
  - `registry-gate-mutation-battery` and `cf-tunnel-liveness-gate-mutations` reach the runner through `PR_GATE_MACHINERY_PATHS` (`scripts/lib/test-relevance-paths.sh:103`, ADR-262): editing the predicate must arm every PR-gated battery. That is deliberate arming, not accidental self-inclusion.
  - `orphan-process-reaper-mutations` **does** read the runner. Its sandbox symlinks `scripts/test-all.sh` (`scripts/orphan-process-reaper-mutation.test.sh:79`), and the driven suite reads it directly (`scripts/orphan-process-reaper.test.sh:1394`, AC33/AC34 grep the runner's registration lines). It is runner-SUT and registration-sensitive, so it must stay selected.
  - `registry-delivery-change-mutation-battery` lists `scripts/test-all.sh` in its hand-committed declared array, but the only mention of `test-all` in the suite is a comment (`tests/scripts/test-registry-delivery-change-mutation-battery.sh:10`). That edge is a stale declared entry with no read behind it. There is no generator behind these arrays; they are committed text.
- **A per-suite runner-SUT marker is the wrong mechanism, on cost.** It adds a second hand-declared set to an index that is hand-declared by design (so ADR-193 §5, which governs the vacuity-floor guard's own population, is not the objection), and it needs its own guard contract and mutation tests, likely costing more than the minutes saved (CPO + CTO).
- **Concept is Soleur-repo-only.** Users' repos use native affected selection (epic #9307 PR 2); a test runner is not an input to its own suites there. Keep "runner-SUT" out of the PR 2 spec and user docs.

## Key Decisions

| Decision | Choice |
|---|---|
| Build now? | No — keep deferred (operator confirmed 2026-10-06) |
| Mechanism if ever built | Not a per-suite marker. FR1 is the only cheap piece; FR2 is a new concept of comparable cost (see below). |
| Trigger | A measurement, with a threshold: ≥3 registration-only runs observed after #9552 with recorded wall time, and the two PR-gated batteries (~10.9 min) exceed 20% of the median observed wait; or the gate is again the slowest step of a suite-adding PR. (Proposed numbers; the point is that the trigger names an instrument.) |
| Productize candidate | none |

**Alternatives recorded for the day the trigger fires.**

1. **FR1 (cheap, ~49 s):** hand-remove the stale `"scripts/test-all.sh"` entry from the registry-delivery declared array (`scripts/lib/test-affected-paths.sh`). It is a removal edit, which the index header calls the dangerous edit, so verify with `--enumerate-commands`/`--print-selection` that the label drops out of a registration-only selection and nothing else does.
2. **FR2 (up to ~11 min for two suites, NOT cheap):** do not drop the `PR_GATE_MACHINERY_PATHS` runner arm wholesale. It is spread into **five** arrays (registry, cf-tunnel, lint-orphan, tag-authorship, test-all-affected = six suites, ~20.8 min), and only the first two are non-runner-SUT. It must be a per-array opt-in for exactly the registry and cf-tunnel arrays, which is itself a two-label allowlist. It also sits at two layers (selection via `AFFECTED_CONSUMED_EDGES`; the in-run predicate `_diff_touches --pr-gated ...`), behaves differently on CI `pull_request` runs (ADR-262), and does not save the minutes on its own: registration PRs also edit the shard-leg manifests (`scripts/suite-shard-legs.tsv` / `-heavy.tsv`; 4 of the 6 most recent runner-touching commits did), and those two TSVs are further arms of `PR_GATE_MACHINERY_PATHS` (as are `ci.yml` and the index file). Decision 20's G1 (no removed lines) bounds the runner and index files only. FR2 therefore needs a closed grammar for TSV edits and an amendment to ADR-242 decision 20 ("the `PR_GATE_MACHINERY_PATHS` arming of ADR-262 is unchanged") and ADR-262.

**Fail-toward-coverage hazards for that day:** a blanket "drop edge-selected suites under registration-only" would wrongly drop suites that read the registration corpus (`lint-orphan-test-suites-mutations-a/-b`, `test-all-affected`, `battery-tag-authorship-mutations`, shard-leg parity checks); `orphan-process-reaper-mutations` must stay; registration-only G2 admits added `#` comment lines and `run_suite` argv strings, either of which can flip a text-grep oracle such as reaper AC34; the read recorder `scripts/audit-suite-reads.sh` is operator-run, so a read added later would not be caught automatically.

## Open Questions

- None open. (The 491 s figure was first recorded here as unverified because only the light manifest was searched; `scripts/suite-durations-heavy.tsv:9` carries it as `measured`.)

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Product

**Summary:** Stay deferred. Only contributors/agents pay the wait; no end user is touched. Risk is correctness of a narrowed safety gate. Concept is Soleur-repo-only and must not leak into PR 2.

### Engineering

**Summary:** Keep deferred. Edges are declared (decision 18, ADR-262): two of four batteries are legitimately runner-armed, one genuinely reads the runner, one carries a stale declared entry. FR1 is the only cheap piece; FR2 is a new concept across selection, predicate and shard-manifest arms.

### Legal

**Summary:** No legal relevance. No legal record or ADR-242 treats the local gate as a compliance control. Wording: "affected-suite gate passed; CI's full battery runs at merge_group/push", never "tests verified". The CLO did not open `knowledge-base/legal/audits/2026-09-counsel-review-7226.md` (audit record, low risk).
