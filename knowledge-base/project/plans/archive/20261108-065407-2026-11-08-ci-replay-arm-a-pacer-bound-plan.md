---
title: "ci: ci-pr-affected-replay-a pace-setter — measured stale premise; evidence PR, no re-split"
date: 2026-11-08
slug: ci-replay-arm-a-pacer-bound
branch: feat-one-shot-12015-replay-a-pacer
issue: 12015
lane: procedural
type: chore
closes: 12015
---

## Overview

Issue #12015 asks for a 4th `--rows` leg of `plugins/soleur/test/ci-pr-affected-replay.test.sh`, or a bound on the fixture corpus the `-a` rows build, because `ci-pr-affected-replay-a` was the merge_group battery's pace-setter at a 1280.4s median (report `knowledge-base/engineering/audits/2026-11-03-suite-time-top-15-report.md`). Measured evidence shows that premise is **stale**: the observation-window retirement (#12296, merged 2026-11-07T13:45Z, after the report's five runs were sampled) removed the 129 `row_ow_*` gated sites — ordinals 1-129 of the then-602-site file, ~993s of arm `-a`'s gated work — and post-retirement `merge_group` suite-timings put `-a` at ~156-161s, the **fastest** of the three arms (`-b` ~197-229s, `-c` ~144-183s). No code change is warranted; the deliverable is the evidence record, an audit-report postscript, and closing the issue.

## Research Insights

**Premise validation (plan Phase 0.6).** Cited report holds: the 1280.4s median was real — but its five sampled runs (41693754894, 41685524714, 41678029255, 41677528300, 41668436219) all ran **pre-retirement**, when arm `-a` owned ordinals 1-129 = the 129 `row_ow_*` observation-window sites (~993.4s of gated time per the committed measurement at `knowledge-base/project/specs/archive/20261107-204952-feat-one-shot-12013-site-cost-measurement/measurements/summary.txt` — "the long replay-a pole of the brief was the retired rows"). Ref #11562's split already landed (three arms). Ref #12013's site-cost harness was re-used for this plan's own measurement.

**Fresh measurement (this plan, evidence for the ruling).**
- Local slice runs on tree `f0c3bb8656`: `--rows 1-1` = 76s wall (unconditional head dominates a single site); slices 2-20/35-50/120-158/159-200/400-476 ≈ 0.4-1s/site.
- Guarded three-arm reading (archived `site_cost_run.sh`, rep r1, verdict CLEAN, tree f0c3bb8656): walls a=173.0s b=261.9s c=210.2s; gated site seconds a=98.8 b=188.6 c=136.5; unconditional ≈ 74s/arm. Heaviest sites live in arm `-b` (`row_scan_ops` 47.3s, `row_sym` 30.2s) and `-c` (`row_rt_big_baseline` 31.2s) — arm `-a` is the cheapest arm locally.
- Post-retirement CI `merge_group` suite-timings (green runs 42447940669, 42442159415, 42439386564, all 2026-11-08, artifact `suite-timings-scripts-*`): `-a` = 160004/160670/156007 ms; `-b` = 196624/229025/225993 ms; `-c` = 183223/143796/165824 ms. Medians ≈ a 160s / b 226s / c 166s.

**Conclusion of evidence:** arm `-a` is retired as pace-setter; `-b` is the mildest of pacesetters at ~226s, far under the 600s corpus cap, and all three arms are within ~1.4x of each other. A 4th leg buys ~40s of parallelism at the cost of a 4th ~74s unconditional head — a net loss. A corpus bound has no target: `-a`'s gated work is 98.8s total.

**Property list.** (1) The battery's test-scripts pace-setter is reduced below the sibling suites' level. (2) The `--rows` ranges tile 1..DECLARED_TOTAL (shard-totality). (3) Committed manifests keep producer/consumer parity.

**Cut list.** 4th `--rows` leg → property 1 → already delivered by #12296's ow retirement; a 4th arm also adds a ~74s duplicated unconditional head. Fixture-corpus bound → property 1 → arm `-a`'s per-call corpus costs ~99 gated-s in total; nothing material to bound. Full `--runs 5` manifest re-price → owned by sibling issue #12016 (stale prices) — the `-a` row at 1033094ms is now over-priced post-retirement but stays consistent with its `suite-weight-exemptions.tsv` cap (1343022 ≤ 1.3×1033094); touching it without the re-price would only satisfy the ledger in this PR and collide with #12016's scope.

**Related issues/PRs.** #12016 (stale suite-durations prices — owner of the `-a` re-price), #12296 (the retirement that fixed this), #12310 / #12013 (site-cost measurement harness + NO-REBALANCE verdict on the 602-tree), #12228 (start-first registration), ADR-240/242.

## Scope Check

Ask → item mapping: "decide with evidence" → measurement artifacts (this section + specs measurements record); "implement" → none required (premise stale); "ship" → evidence PR closing #12015. No inferred items.

## User-Brand Impact

- **If this lands broken, the user experiences:** no user-facing artifact — internal CI documentation.
- **If this leaks, the user's [data / workflow / money] is exposed via:** none — docs-only change.
- **Brand-survival threshold:** none — internal CI/test documentation only.

## Implementation Phases

### Phase 1 — Evidence record

- Write `knowledge-base/project/specs/feat-one-shot-12015-replay-a-pacer/measurements.md` capturing: the CI medians pre/post retirement with run IDs, the local site-cost table headline numbers, the mechanism (ow retirement ordinals 1-129 ≈ 993s), and the verdict that neither remedy is warranted.
- Add a dated postscript to `knowledge-base/engineering/audits/2026-11-03-suite-time-top-15-report.md` finding 1 noting the `-a` pace-setter is retired by #12296 with the post-retirement medians, so the report is not read as current truth.

### Phase 2 — Ship

- PR body carries `Closes #12015` + `## Changelog`; arm merge queue.

## Files to Edit

- `knowledge-base/engineering/audits/2026-11-03-suite-time-top-15-report.md` (postscript)

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-12015-replay-a-pacer/measurements.md`

## Non-Goals / Deferred

- `suite-durations.tsv` `-a` re-price (1033094 → ~160000ms) and the `suite-weight-exemptions.tsv` row drop: deferred to #12016 (stale-price slice owner). They are internally consistent today and red nothing.
- A 4th leg or corpus bound: not deferred, **eliminated** by evidence.

## Acceptance Criteria

- [ ] Post-retirement CI medians for all three replay arms are recorded in `measurements.md` with the three run IDs and the artifact name.
- [ ] The audit report carries a dated postscript on the `-a` finding naming #12296, the ow-site mechanism, and the new medians.
- [ ] No changes to `scripts/ci-oracle-lane-suites.txt`, `scripts/test-all.sh` registrations, `scripts/suite-*.tsv`, or the test file — shard-totality and corpus-weight stay green trivially (no registration diff).
- [ ] PR body contains `Closes #12015` and a `## Changelog` section.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — CI/test documentation change.
