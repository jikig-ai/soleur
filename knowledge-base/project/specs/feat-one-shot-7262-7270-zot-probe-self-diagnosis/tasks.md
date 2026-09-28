---
lane: single-domain
plan: knowledge-base/project/plans/2026-09-28-fix-zot-probe-self-diagnosis-plan.md
---

# Tasks: zot probe self-diagnosis (#7262, #7270)

## 1. Consumer probe (#7262)

- [ ] 1.1 RED: dead-port behavioural row in `web-zot-consumer-probe.test.sh` (fails on `main`).
- [ ] 1.2 GREEN: `000000) CODE=000` normalization in the probe's live arm; row (c) unchanged.

## 2. Liveness feeder counters (#7270)

- [ ] 2.1 RED: feeder rows in `zot-liveness-heartbeat.test.sh` (state seam, ping-fail stub,
  slow-`mv` row, first-OK row, corrupt and unwritable state, raw-template escaping assert).
- [ ] 2.2 GREEN: feeder state step (fail-open subshell after the ping) and
  `TimeoutStartSec=45s` on the service.
- [ ] 2.3 RED: liveness phase in `zot-disk-heartbeat-redaction.test.sh` (absent, valid,
  hostile, vocabulary, ordering, seam-landed, own counter and floor).
- [ ] 2.4 GREEN: reporter reads the state and emits five `liveness_*` fields before
  `store_mount_src=`.
- [ ] 2.5 Measure `registry-userdata-budget.sh --json` before and after (render exits 0).

## 3. Docs and ratchet

- [ ] 3.1 Runbook section in `betterstack-log-query.md`.
- [ ] 3.2 `model.c4` edge: the stale "unbuilt" claim, plus the liveness counters sentence.
- [ ] 3.3 Bump `BASELINE_DECLARED_PROBES` (+1, with a comment).

## 4. Ship

- [ ] 4.1 Targeted suites green; review; compound; ship with `Closes #7262` and `Closes #7270`.
- [ ] 4.2 Merge only after #9147's registry replace settles; then verify the new boot's
  `liveness_*` fields and web-1's probe.
