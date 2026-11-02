# CTO ruling (BINDING), 2026-10-30, for issue 11631: replace the once-a-day dead-man logs alerts with heartbeats

Decision: replace both logs alerts with Better Stack heartbeats fed by a scheduled GitHub workflow that reads the archive. No host change; no logs alert created above query_period 900.

Add `betteruptime_heartbeat.luks_monitor_host_timer` (`soleur-luks-monitor-host-timer-prd`) and `betteruptime_heartbeat.claude_cost_capture` (`soleur-claude-cost-capture-prd`) to `apps/web-platform/infra/uptime-alerts.tf`, copying the shape of `betteruptime_heartbeat.inngest_server_probe` (same file, ~line 531): period 3600; grace 3600 (luks-monitor) and 7200 (cost-capture); born `paused = true` with `ignore_changes = [paused]`; policy gated on `var.betterstack_paid_tier`.

Feeder: runs hourly; beats a heartbeat only if a qualifying row exists inside that alert's OLD window (97200 s for luks-monitor, 86400 s for cost-capture). Predicates = the existing `luks_monitor_host_timer_sql` and `claude_cost_capture_dark_sql`, run as raw SQL (mode 1) through `scripts/betterstack-query.sh` with the `remote()` UNION `s3Cluster` arms (never `--no-archive`). With no qualifying row it withholds the beat so the heartbeat times out; it never beats `/fail`. Model on `scripts/inngest-probe-heartbeat-feeder.sh` (exact-name heartbeat lookup via the read-only API token, stdin-config curl, marker-line discipline); leave that feeder untouched. Workflow `.github/workflows/scheduled-deadman-heartbeat-feeder.yml`: `schedule` + `workflow_dispatch` only, a concurrency group, the `sentry-heartbeat` check-in step.

Rejected: host-side ping (needs a user_data change = host replace; the shared workspaces_luks heartbeat cannot tell the host timer from the verify workflow's second pusher). Rejected: hourly host row with a <=900 s alert (also a host change; cost-capture has no hourly cadence).

The "Better Stack evaluates alerts over the hot window only" claim is still INFERRED; the design does not depend on it because the feeder reads the archive itself.

Files:
1. `uptime-alerts.tf`: the two heartbeats. (A `doppler_secret` per URL is optional; the feeder resolves the URL through the read-only API.)
2. `plugins/soleur/lib/heartbeat-manifest.ts`: two rows, `arming: "external-probe"`, `paused: true`, a cron feeder whose evidence is the workflow file and feeder script line, plus `exempt_reason`. Rewrite the comment near line 135 that names the old alert.
3. Delete from `betterstack-logs-alerts.tf` the two `logtail_exploration` and two `logtail_exploration_alert` resources (luks_monitor_host_timer_dark, claude_cost_capture_dark) and the SQL locals if nothing else reads them (the feeder needs the SQL: move it where the feeder or its test reads it, do not lose the predicate). Never edit them in place.
4. `apply-web-platform-infra.yml` (~lines 665-668) hard-`-target`s those four addresses: keep the destroy reachable and add the two new heartbeats to the target list; confirm with a plan that shows the destroys (unverified).
5. Update stale references: `workspaces-luks.tf` (~229), the runbook anchor `#host-timer-liveness-alert-8706` and `local.luks_monitor_runbook_url` text.

Must NOT appear in the PR: anything under `luks-monitor.*`, `server.tf`, `cloud-init.yml`; any logs alert above 900 s. Owner-gated (do not do): unpausing the heartbeats, resolving the two stuck Better Stack incidents (incident 1023423999 and the cost-capture one), any Better Stack create/delete outside the CI apply, merging the PR. Prepare the exact incident-resolve command and the arm block with read-back as text in the PR body only.

Tests: new `apps/web-platform/test/infra/deadman-heartbeat-feeder.test.sh` with synthesized fixtures (row 26 h old beats; 28 h old withholds; empty withholds; a `soleur-web-2` row withholds; a verify-job row without `_SYSTEMD_UNIT` withholds; SQL contains `s3Cluster` and never `--no-archive`; withhold path never beats `/fail`) plus mutation cases in the style of `luks-monitor-install.test.sh`. Rewrite the `luks-monitor-install.test.sh` guards (~326-380) and mutants (~1169-1194) to assert the heartbeat's period/grace/paused/ignore_changes and that the old alert is absent. In `inngest-step-524-alert.test.sh` drop the `claude_cost_capture_dark` expectations (~136-425), keep `claude_cost_daily_burn`. Add a sentinel that no `logtail_exploration_alert` is created with `query_period` above 900, allowlisting only the live legacy ones (`claude_cost_daily_burn`, `inngest_luks_wrong_volume`). Run `heartbeat-reprovision-parity.test.ts`, `heartbeat-live-reconcile.test.ts`, `sentry-monitor-iac-parity.test.ts`.

Risks: detection latency = old window + ~1-2 h (fine for a nightly dead-man). Unmeasured: archive ingestion lag; measure lag between a row's `dt` and its appearance in the `s3Cluster` arm (pattern: `scripts/followthroughs/luks-monitor-host-timer-8706.sh`); if lag exceeds the grace, widen the grace. The key-continuity dead-man (probe bundle tracker) should later reuse this feeder pattern (follow-up, not this PR).

Runbook note to add: after a host replace plus `op=resume`, the inngest server-probe heartbeat stays down up to ~1 h because the probe timer fires at boot+90s then hourly (OnUnitActiveSec=1h); the 60 s `soleur-inngest-server-prd` heartbeat is the real serving signal.

Also include in the same PR: the unsigned A6 draft `knowledge-base/legal/audits/2026-10-30-inngest-a6-no-known-access-record.md` (already present in the worktree `.worktrees/fix-observable-deadman-11631`; keep `status: draft-unsigned`, do not sign or attest).
