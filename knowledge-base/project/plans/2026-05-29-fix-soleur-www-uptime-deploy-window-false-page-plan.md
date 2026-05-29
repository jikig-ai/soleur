<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
<!--
  Phase 2.8 reviewed: this change adds NO infrastructure resource and provisions
  NO server. It mutates ONE attribute (downtime_threshold) on an EXISTING
  Terraform-managed resource (sentry_uptime_monitor.soleur_www). The "operator
  runs terraform apply" step is PRE-EXISTING architecture — uptime-monitors.tf is
  operator-applied per its own file header (apply-sentry-infra.yml auto-applies
  sentry_cron_monitor.* only). Extending auto-apply to uptime monitors is the
  separately-tracked, intentionally-out-of-scope #4585. No SSH, no manual install,
  no new .tf root. The apply path is surfaced explicitly in the PR body, not buried.
-->
---
title: "Harden soleur_www uptime monitor against deploy-window false pages"
date: 2026-05-29
branch: feat-one-shot-soleur-www-uptime-threshold
status: complete
labels: [app:web-platform, semver:patch, domain/engineering]
---

# Harden `soleur_www` uptime monitor against deploy-window false pages

## Overview

The `soleur_www` Sentry uptime monitor (`apps/web-platform/infra/sentry/uptime-monitors.tf`)
asserts `equals 301` — www must redirect to apex. Its `downtime_threshold` was `3`
(3 × 5-min checks ≈ 15 min). A docs deploy (`deploy-docs.yml`) rebuilds GitHub
Pages and re-propagates the custom-domain apex-canonical redirect; during that
window `https://www.soleur.ai/` transiently serves its own `200` instead of the
`301`. That window empirically exceeds 15 min, so the monitor false-pages on the
project's **own** deploys.

This change raises `soleur_www.downtime_threshold` to `5` (≈ 25 min) so the deploy
window is absorbed. `soleur_apex` (threshold `3`) is **unchanged** and remains the
user-facing-outage signal, so this does NOT weaken real-outage detection.

## Incident that motivated this

On 2026-05-29 ~12:30 CEST a Sentry uptime alert "monitored domain is down" fired
for `https://www.soleur.ai/` (Status `200`, "Assertion failed"). Root cause: #4578
(merged 12:18) flipped the `soleur_www` assertion to `equals 301`; #4573 (11:45) +
#4578 triggered a GitHub Pages rebuild. During Pages rebuild/propagation, www
served `200` for ≥3 consecutive checks, tripping the freshly-tightened assertion.
It self-recovered (live probe: www → 301 → apex, apex → 200). The
`auth-callback-no-code-burst` footer in the alert email is a documented red-herring
(coincidental issue-alert on the same email), not the cause.

## Decision: Option B (threshold) over Option A (deploy-window suppression)

- **Option B (this PR):** raise `soleur_www.downtime_threshold` 3→5. Two-line change;
  defensible because `soleur_apex` carries the user-facing signal at threshold 3.
  Cost: +10 min MTTD on a www-ONLY redirect regression (lower severity).
- **Option A (deferred follow-up):** pause the monitor in `deploy-docs.yml` during a
  Pages rebuild. Zero MTTD cost, but more CI plumbing + Sentry API access. Filed as a
  follow-up issue.

## Scope

- IN: `soleur_www.downtime_threshold` 3 → 5, with a justifying comment.
- OUT: `soleur_apex`, `soleur_changelog_deep`, `soleur_acme_probe` thresholds (unchanged).
- OUT: the #4584 drift-guard work (dns.tf / PR #4592, separate parallel session) —
  different file, different concern; #4584 does NOT cover this runtime failure mode.

## Apply path (no silent operator step)

`uptime-monitors.tf` is **operator-applied**, not auto-applied (see file header):
`apply-sentry-infra.yml` auto-applies `sentry_cron_monitor.*` only. So this change
takes effect when the operator runs `terraform apply` in `apps/web-platform/infra/sentry/`,
OR once **#4585** (extend auto-apply to `sentry_uptime_monitor.*`) lands. This is
stated explicitly in the PR body — not buried — per `hr-never-label-any-step-as-manual-without`.

## Acceptance criteria

- [x] `soleur_www.downtime_threshold == 5`; justifying comment present.
- [x] Other three monitors' thresholds unchanged.
- [x] `terraform fmt -check` clean; `terraform validate` Success in the sentry root.
- [x] Change is an in-place attribute mutation (no resource replacement/destroy).
- [x] PR body front-loads incident evidence + the apply-path note + #4585 reference.
- [ ] Follow-up issue filed for Option A (deploy-window suppression).

## Test scenarios

None (browser/API QA N/A — this is a Terraform monitor-config attribute change;
validation is `terraform fmt`/`validate`, already run).
