# Decision challenges raised at plan-review (headless; operator direction is the default and was kept)

User-Impact: none directly; both challenges concern how much monitoring machinery ships with a dispatcher that emails nobody until a second PR.
Fix-Size: 0 lines (decisions only)

## 1. Drop the new Sentry monitor and its parity fan-out (User-Challenge)

- Brief said: follow the precedent end to end including `infra/sentry/cron-monitors.tf`.
- Challenge (DHH reviewer, code-simplicity reviewer): the precedent has no dispatcher-side heartbeat (its monitor is fed by the workflow, which here has none). A new monitor ships unrouted, so it emails nobody; it costs about $0.78 per month and forces 6 parity edits (README, audit script, model.c4, model.likec4.json, cron-monitor-alerts.tf, cron-monitors.tf) plus a tracking issue. Without it the PR is about 10 files.
- Counter (CTO reviewer): `hr-observability-as-plan-quality-gate` wants a liveness signal; the monitor catches an unregistered or lost cron trigger that nothing else watches.
- Default kept: the monitor ships (operator-listed scope). To cut it: remove Phase 3 items 9 to 12, the heartbeat steps and tests, the Phase 0 issue, and restore `71 -> 72` as the only count edit.

## 2. Dispatch cadence `*/5` instead of `*/10` (Taste)

- CTO reviewer: `*/5` widens the worst-case margin from about 5 to about 10 minutes at no cost (public repo, same monitor cost). Needs only the function cron literal and the monitor crontab; the workflow's `on:` is untouched.
- Default kept: `*/10`, equal to the workflow fallback and the brief's stated cadence. The plan drops the cron-equality test row so a later tuning is a two-line change; the post-merge `startedAt - createdAt` measurement is the trigger to revisit.
