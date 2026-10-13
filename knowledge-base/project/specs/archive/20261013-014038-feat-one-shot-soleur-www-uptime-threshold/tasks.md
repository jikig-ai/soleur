<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
<!--
  Phase 2.8 reviewed in the linked plan: single-attribute mutation on an existing
  Terraform-managed resource; the operator-apply step is pre-existing architecture
  tracked by #4585. No new resource, no server, no SSH.
-->
---
title: "Tasks — harden soleur_www uptime monitor against deploy-window false pages"
plan: "../../plans/2026-05-29-fix-soleur-www-uptime-deploy-window-false-page-plan.md"
branch: feat-one-shot-soleur-www-uptime-threshold
lane: engineering
---

# Tasks — soleur_www deploy-window false-page hardening

## Phase 1 — Implement
- [x] 1.1 Raise `sentry_uptime_monitor.soleur_www.downtime_threshold` 3 → 5 in `apps/web-platform/infra/sentry/uptime-monitors.tf`, with a justifying comment (redirect-health guard, apex carries user-facing signal, deploy-window rationale, +10min MTTD trade-off).
- [x] 1.2 Confirm `soleur_apex`, `soleur_changelog_deep`, `soleur_acme_probe` thresholds UNCHANGED.

## Phase 2 — Validate
- [x] 2.1 `terraform fmt -check` clean in the sentry root.
- [x] 2.2 `terraform validate` Success (pre-existing issue-alert deprecation warnings only).
- [x] 2.3 Confirm in-place attribute mutation (no resource replacement).

## Phase 3 — Ship
- [x] 3.1 PR body front-loads incident evidence + apply-path note (#4585) + Option A follow-up.
- [x] 3.2 File follow-up issue for Option A (deploy-window suppression in deploy-docs.yml) — #4596.
- [ ] 3.3 Merge; CI green.

## Acceptance gates
- [x] Diff touches only `uptime-monitors.tf` (+ KB artifacts).
- [x] Apply path explicit (operator `terraform apply` in sentry root OR #4585), not buried.
