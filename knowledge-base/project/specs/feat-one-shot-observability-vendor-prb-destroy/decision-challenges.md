---
title: Decision challenges — feat-one-shot-observability-vendor-prb-destroy
date: 2026-10-29
branch: feat-one-shot-observability-vendor-prb-destroy
---

# Decision challenges

## Decision Classes

| Item | Class | Ruling |
|---|---|---|
| Pruned-monitor guard posture: shared `PRUNED_MONITOR_SLUGS` exemption set in the three strict parity guards vs stripping the 43 emitters (SENTRY_MONITOR_SLUG consts + workflow `sentry-heartbeat` steps) | technical | pending - assumed: exemption over stripping — archived spec NG4 explicitly non-goals "re-pointing or rewriting any emit path (`reportSilentFallback`, `postSentryHeartbeat`, the sentry-heartbeat composite action, host scripts)", and the three guards have no existing exemption mechanism for the deliberate void-post state. (No subagent spawn available in this context to route a formal CTO consult; recorded for review-panel confirmation.) |
| `c4-count-parity.test.sh` `derive_github_slugs` semantic shift: raw `monitor-slug:` literal count → live-backed intersection (workflow slugs ∩ declared tf names) | technical | pending - assumed: intersection — with emitters retained per NG4 the raw count (22) makes the gated C5/C6/C9 prose false (14/10 live-backed); the emitter-cohort property stays pinned by sentry-monitor-iac-parity + the PRUNED set. |
| #10972 (route scheduled-orphan-sweeps monitor, due 2026-10-27) disposition after destroy | operator (scope) | pending - assumed: close as OBE at ship time — the monitor is destroyed by the #6590 prune verdict rather than routed; cover reverts to the aggregator's `notify-ops-email` step the issue itself cites. |
| `alert-reference.json` regeneration in PR-B | technical | pending - assumed: skip — the projection covers `sentry_alert` rules only and `cron-monitor-failure` already binds the 22 kept-routed detector ids (verified via `jq`); artifact-route fallback documented in plan §Sharp Edges. |
