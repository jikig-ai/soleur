---
title: "New heavy test suites now get flagged before they silently misprice CI"
type: feature-launch
publish_date: 2026-10-20
channels: x, bluesky
status: scheduled
pr_reference: "#10578"
issue_reference: "#9771"
---

<!-- To publish: set BOTH publish_date AND status: scheduled -->

## X/Twitter Thread

Just shipped: Soleur's test reviewer now warns when a new shell test suite spawns real subprocesses — servers, proxies, background reapers — without an honest weight in the shard durations tables.

2/ The failure it catches: a heavyweight suite lands, gets priced at the ~1.2s default until measured runs accumulate, and CI legs silently mis-balance in the meantime.

3/ Review-time machinery, not more process — a WARN in the review output, a placement convention, and a flaky-test policy that points at the enforcement that already exists.

## Bluesky

Just shipped: Soleur's test reviewer warns when a new shell test suite spawns real subprocesses without an honest shard weight — the gap that let heavyweight suites silently misprice CI legs until measured runs landed.
