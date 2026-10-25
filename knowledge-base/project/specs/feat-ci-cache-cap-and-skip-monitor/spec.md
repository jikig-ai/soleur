---
feature: ci-cache-cap-and-skip-monitor
lane: cross-domain
brand_survival_threshold: single-user incident
issues: [10917, 10918, 8856]
brainstorm: knowledge-base/project/brainstorms/2026-10-25-ci-cache-cap-and-skip-monitor-brainstorm.md
---

# Spec: Actions cache cap + rehearsal skip monitor

## Problem Statement

The repo's Actions cache is over its 10 GB cap because each release exports ~1.2 GB of never-reused layers via `type=gha`, evicting every other cache older than about a day. Separately, the rehearsal skip monitor's alert is red on a remedy that was cut (#7535), fails on any single skip although ADR-188 bounds skips at 1 in 20, and will file its probe-broken escalation under the skip title.

## Goals

- G1. `actions/cache/usage` stays under 8 GB across a day with 7 or more releases.
- G2. Release build time does not regress; per-release new cache bytes under ~300 MB.
- G3. The probe's verdict matches ADR-188's stated bound, and its alert text names only work that exists.
- G4. The escalation is distinguishable from a skip in title, body and tests.

## Non-Goals

- Building the pre-baked image (#7535 is closed on measurement).
- A cache-prune workflow (production-state mutation; treats the symptom).
- A dead-man's switch for the monitor (separate issue).
- Making the monitor green by loosening it; the skip cause is investigated, not suppressed.

## Functional Requirements

- FR1 (PR A). `reusable-release.yml` uses `cache-to: type=inline` and `cache-from: type=registry,ref=<image>:latest`; no `type=gha` export remains. The secret-safety comment is kept.
- FR2 (cut at plan, 2026-10-25). `chown -R` to `COPY --chown` buys no listed property (FR1 alone meets the cap) and changes production image ownership.
- FR1b (PR A). `provenance: false` is set explicitly (CTO ruling, 2026-10-25).
- FR3 (PR B). The rehearsal source counts runs with at least one skip, samples until 20 runs are observed (up to 40 listed), and FAILs when `runs_with_skip * 20 > observed`. The guard source (`g1b.`/`g2b.`/`fl.`) keeps any-hit FAIL.
- FR4 (PR B). Alert text, probe comments, workflow text and ADR-188 no longer say the pre-baked image is owed; they point at diagnosing the rc 100/125 declines.
- FR5 (PR B). The consecutive-TRANSIENT escalation exits rc 3, which the workflow already maps to the `broken` title; the `broken` body and exit-code header describe rc 3 truthfully. The shared `soleur-skip-persistence-monitor-alert` marker is kept (CTO ruling). A unit case and a workflow wiring case cover it.

## Technical Requirements

- TR1. Verify G1/G2 on a real release after merge; record before/after cache usage and the export step duration.
- TR2. The plan starts by pulling an actual skip line from an infra-validation run log to confirm the skip cause before changing alert text.
- TR3. Probe changes keep the existing un-run-instrument (TRANSIENT) protections.
- TR4. Record the cache-backend decision as an ADR.
