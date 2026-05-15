# Sentry Monitors/Alerts Migration Audit

- **Date (UTC):** 2026-05-15
- **Sentry org:** jikigai
- **API host:** sentry.io
- **Project filter:** soleur-web-platform

## Monitors

| slug | name | type | schedule |
|---|---|---|---|
| scheduled-terraform-drift | scheduled-terraform-drift | 0 6,18 * * * |  |
| scheduled-oauth-probe | scheduled-oauth-probe | */15 * * * * |  |
| scheduled-github-app-drift-guard | scheduled-github-app-drift-guard | 0 * * * * |  |
| scheduled-skill-freshness | scheduled-skill-freshness | 0 2 1 * * |  |
| scheduled-community-monitor | scheduled-community-monitor | 0 8 * * * |  |
| scheduled-daily-triage | scheduled-daily-triage | 0 4 * * * |  |
| scheduled-realtime-probe | scheduled-realtime-probe | 0 7 * * * |  |
| scheduled-content-vendor-drift | scheduled-content-vendor-drift | 17 11 * * MON |  |

## Alert Rules

| id | name |
|---|---|
| 484097 | Send a notification for high priority issues |

## Orphans

_Class A (monitor without paired routing alert):_

- `scheduled-terraform-drift` — orphan: not referenced by any alert rule.
- `scheduled-oauth-probe` — orphan: not referenced by any alert rule.
- `scheduled-github-app-drift-guard` — orphan: not referenced by any alert rule.
- `scheduled-skill-freshness` — orphan: not referenced by any alert rule.
- `scheduled-community-monitor` — orphan: not referenced by any alert rule.
- `scheduled-daily-triage` — orphan: not referenced by any alert rule.
- `scheduled-realtime-probe` — orphan: not referenced by any alert rule.
- `scheduled-content-vendor-drift` — orphan: not referenced by any alert rule.

**Remediation runbook:** plan §2.1.5 — delete monitor or pair with new alert.

## DPA evidence

Vendor DPA: https://sentry.io/legal/dpa/
Article 30 register entry: knowledge-base/legal/article-30-register.md (PA8).

<!-- ids: ["484097"] -->
