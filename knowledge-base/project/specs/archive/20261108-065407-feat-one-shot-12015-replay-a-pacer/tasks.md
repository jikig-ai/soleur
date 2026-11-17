# Tasks — feat-one-shot-12015-replay-a-pacer (issue #12015)

Plan: `knowledge-base/project/plans/2026-11-08-ci-replay-arm-a-pacer-bound-plan.md`
Verdict: premise stale — arm `-a` pace-setter retired by #12296; evidence docs only, no re-split.

## Phase 1 — Evidence record

- [x] 1.1 Measure leg timings locally (slices + guarded 3-arm site-cost reading, verdict CLEAN)
- [x] 1.2 Pull post-retirement CI merge_group suite-timings for all three arms (runs 42447940669, 42442159415, 42439386564)
- [ ] 1.3 Write `measurements.md` in this spec dir with medians, run IDs, mechanism, verdict
- [ ] 1.4 Add dated postscript to `knowledge-base/engineering/audits/2026-11-03-suite-time-top-15-report.md` finding 1

## Phase 2 — Ship

- [ ] 2.1 Commit docs artifacts
- [ ] 2.2 Update PR #12376 body (`Closes #12015` + `## Changelog`), mark ready, arm merge queue
- [ ] 2.3 Postmerge verification; report
