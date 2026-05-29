---
date: 2026-05-29
category: best-practices
tags: [observability, sentry, uptime-monitor, alert-fatigue, terraform, deploy]
component: apps/web-platform/infra/sentry/uptime-monitors.tf
---

# Uptime-monitor fuses must tolerate self-inflicted deploy windows

## Problem

`soleur_www` (a Sentry uptime monitor asserting `equals 301` — www must redirect
to apex) paged "monitored domain is down" at 2026-05-29 12:30 CEST, ~12 min after
#4578 tightened its assertion to `equals 301` and #4573/#4578 triggered a GitHub
Pages rebuild. During the Pages rebuild + custom-domain redirect re-propagation,
`https://www.soleur.ai/` transiently served its own `200` instead of the `301`.
The monitor's `downtime_threshold = 3` (≈15 min) was shorter than the deploy
window, so the project paged itself on its own deploy. It self-recovered.

## Root cause

Two independent changes stacked: (a) the assertion was newly **tightened** from a
`2xx` check to an exact `equals 301`, and (b) the same deploy rebuilt the static
host whose redirect the assertion guards. A freshly-strict assertion + a fuse
shorter than the deploy's own propagation window = guaranteed false page.

## Fix / principle

- An uptime monitor that guards a **statically-hosted redirect/page** must have a
  `downtime_threshold` longer than that host's deploy/propagation window, or it
  pages on every deploy. Here: `soleur_www` 3 → 5 (≈25 min).
- Tier the fuse by **severity, not uniformity**: `soleur_apex` (the user-facing
  outage signal) stays at threshold 3 / 15 min; `soleur_www` (a redirect-HEALTH
  guard whose failure is lower-severity) gets the longer fuse. Lengthening the
  low-severity monitor does NOT weaken real-outage detection because a different
  monitor carries the user-facing signal.
- When you **tighten an assertion** (`2xx` → `equals N`), re-check the fuse in the
  same change — a stricter success condition is more likely to trip during the
  normal deploy window.
- The precise alternative (no MTTD cost) is **deploy-window suppression**: pause
  the monitor in the deploy workflow during the rebuild and resume after a
  confirming probe. Higher plumbing cost (Sentry API in CI); filed as a follow-up.

## Don't be fooled by the alert-email footer

The Sentry "domain down" email carried "triggered by auth-callback-no-code-burst".
That footer is a **documented red-herring** — a coincidental issue-alert routed to
the same operator email, unrelated to the uptime monitor that actually fired. See
`knowledge-base/project/learnings/bug-fixes/2026-05-27-sentry-cron-community-monitor-missed-checkin.md`.
Identify the firing monitor from the alert *body* (URL + assertion), not the footer.
