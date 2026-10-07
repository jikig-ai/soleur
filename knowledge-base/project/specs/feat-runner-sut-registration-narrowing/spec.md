---
feature: runner-sut-registration-narrowing
lane: cross-domain
brand_survival_threshold: single-user incident
refs: [9564, 9307, 9552]
brainstorm: knowledge-base/project/brainstorms/2026-10-06-runner-sut-registration-narrowing-brainstorm.md
status: deferred
created: 2026-10-06
---

# Spec — registration-only second-stage narrowing (#9564)

## Problem Statement

A registration-only runner edit takes the bounded selection (ADR-242 decision 20): ~58.6 min at manifest weights against 91.4 min for the full battery. 13.6 min of its 43 edge suites are four heavy mutation batteries. The brainstorm found the issue's "reach the runner only through self-inclusion" premise does not hold as stated: two of the four are deliberately armed by ADR-262, one genuinely reads the runner, and one carries a stale declared entry.

## Goals

- None scheduled. The work stays deferred until a measured trigger fires.

## Non-Goals

- A per-suite declared runner-SUT set: a second hand-declared set in an index that is hand-declared by design, whose guard contract and mutation rows would likely cost more than the saving.
- Any change to the plugin-generic gate for users' repos (epic #9307 PR 2).

## Re-evaluation trigger (restates the issue's as a measurement)

Reopen when at least 3 registration-only runs have been observed after #9552 with recorded wall time AND the two PR-gated batteries (~10.9 min) exceed 20% of the median observed wait, OR the gate is again the slowest step of a suite-adding PR. The 20% and 3-run numbers are proposed; revise them with the first measurement. The best case FR1 + FR2 can save is ~11.8 min (49 s + ~10.9 min), not the full 13.6, because `orphan-process-reaper-mutations` must stay.

Watched mechanically (part (a) only): `scripts/watch-registration-narrowing-9564.sh`, run weekly by `.github/workflows/registration-narrowing-watch.yml`, counts qualifying runner commits and posts one notice on #9564 at 3. Its threshold and the part (b) arithmetic are literals in that script, so revising the numbers above means editing it too.

## Functional Requirements (if built)

- FR1: remove the stale `"scripts/test-all.sh"` entry from the registry-delivery declared array in `scripts/lib/test-affected-paths.sh` (the declared arrays are hand-committed; there is no generator). Verify with a dry-run enumeration that exactly that label drops out of a registration-only selection.
- FR2: under `registration-only`, skip the runner arm only for exactly the `REGISTRY_BATTERY_PATHS` and `CF_TUNNEL_BATTERY_PATHS` arrays (a two-array opt-in), at BOTH layers (selection via `AFFECTED_CONSUMED_EDGES`, and the in-run `_diff_touches --pr-gated` predicate), with a closed grammar for additions to `scripts/suite-shard-legs.tsv` / `scripts/suite-shard-legs-heavy.tsv` (those TSVs are separate arms of `PR_GATE_MACHINERY_PATHS`, and registration PRs routinely edit them), rows in `scripts/test-all-affected.test.sh`, and amendments to ADR-242 decision 20 and ADR-262. State the CI `pull_request` behaviour explicitly.

## Technical Requirements (if built)

- TR1: every path fails toward coverage. Must-stay selected: `orphan-process-reaper-mutations`, `lint-orphan-test-suites-mutations-a/-b`, `test-all-affected`, `battery-tag-authorship-mutations`, shard-leg parity checks. Add a negative-read guard row asserting the two opted-in suites never name the runner (`scripts/audit-suite-reads.sh` is operator-run, so a later read would otherwise go uncaught).
- TR2: wording stays "affected-suite gate passed"; CI's full battery runs at `merge_group`/`push`, and `pull_request` CI declines the five PR-gated batteries when the diff touches none of their paths (ADR-262).
