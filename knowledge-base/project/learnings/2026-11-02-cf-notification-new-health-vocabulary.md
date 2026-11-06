---
title: "Cloudflare load_balancing_health_alert new_health vocabulary is {Unhealthy, Healthy} — never Down/Up"
date: 2026-11-02
category: integration-issues
tags: [cloudflare, notification-policy, terraform, lb, followthrough]
---

# CF `new_health` vocabulary: `{Unhealthy, Healthy}`, not `{Down, Up}`

`cloudflare_notification_policy` with `alert_type = "load_balancing_health_alert"`
rejects `filters.new_health = ["Down"]` at apply time with
`Error 17108: invalid new_health input` (measured: cf-lb-overlay.yml
arm=ga-pool-update, run 41504420340 — pool + LB applied, only the policy CREATE
failed). The documented vocabulary is `["Unhealthy", "Healthy"]`
(CF health-monitor-notifications migration guide). A single-element subset is
legal.

Two consequences worth recording:

1. **The gate cannot see a valid-but-wrong enum.** `"Down"` failed because CF
   rejected it; `["Healthy"]`-only would apply green and never page on
   origin-down. `cf_lb_gate_ga_pool_update` pins `enabled`/`alert_type`, not
   `filters.new_health` — tracked as #11905.
2. **A `-target`ed partial apply leaves a consistent remnant.** A pre-create CF
   validation reject creates no remote object and no state entry; re-dispatch
   emits a `{policy:create}`-only plan, which the gate's `pool_updates==0`
   remnant branch admits by design. No manual CF-side cleanup needed.

Side notes: GitHub's review-pending-deployments API wants
`environment_ids[]` (numeric), not `environment_names[]` (HTTP 422). Corpus
journal comments: a `>-` fold parenthetical describes the field it sits on —
naming a sibling field teaches a wrong shape.
