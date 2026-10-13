# Decision Challenges — feat-one-shot-8516-dead-probe-heartbeat

## 2026-10-07 — Scope: heartbeat born paused + unfed (feeder deferred to a tracking issue)

- **decisionClass:** taste (operator's prescribed mechanism is followed; the judgment call is
  delivery staging, not mechanism).
- **The operator's stated direction** (issue #8516): "mirror `betteruptime_heartbeat.workspaces_luks`
  (DP-10) for the `SOLEUR_INNGEST_SERVER_PROBE` emission cadence". DP-10's own delivery was staged:
  resource + URL secret born `paused = true` + `ignore_changes`, feeder/arming later (#6808 wired
  it). This plan mirrors that — the heartbeat and its Doppler URL ship via the per-merge
  push-apply (`-target=` allow-list, #8754 precedent), declared honestly in
  `heartbeat-manifest.ts` as `feeder.kind = "none"` + `tracking_issue` + `arming_pending`.
- **The alternative not taken:** build the feeder in the same PR — a warehouse-verifying external
  pusher (only shape that covers all three named failure modes: dead emitter, Vector allowlist
  regression, sink outage) on a reliable trigger (watchdog-dispatch-table per ADR-248). That adds
  a new scheduled workflow, a pusher script, a `github_actions_secret`, a `sentry_cron_monitor`
  in the SECOND terraform root (apps/web-platform/infra/sentry — two-PR rule), and dispatch-table
  wiring — ~3x the file surface of the issue's surgical two-file ask.
- **Why recorded:** the monitor is inert until the feeder lands + unpause happens. The tracking
  issue carries the 2026-10-22 re-evaluation date from #8516; `arming_pending` keeps
  live-reconcile honest in the window.
