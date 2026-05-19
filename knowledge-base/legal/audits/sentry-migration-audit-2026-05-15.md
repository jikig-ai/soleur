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

## Correction (2026-05-15)

This report's frontmatter `**API host:** sentry.io` line is **not** evidence
that user-event ingest crosses the EEA. The audit script's region-probe
loop tries `sentry.io` first and returns the first host that 200s the
`/users/me/` endpoint; the IaC tfstate stayed pinned to the US shadow org
(`jikigai-us`) carrying 8 cron monitors, which is the cluster the probe
matched. User-event ingest is DE-bound and intact, anchored by the
production DSN substring `o4511123328466944.ingest.de.sentry.io` (also
the authoritative residency signal per learning
`2026-05-15-sentry-dsn-cluster-substring-authoritative-residency.md`).

No personal data left the EEA. Article 33 (72-hour breach notification)
does not trigger. Article 30 §5(2) accountability evidence regeneration
on the wrong cluster has been stopped in PR #3863:

1. `.github/workflows/reusable-release.yml` `SENTRY_API_HOST` default
   flipped to `de.sentry.io`.
2. Probe loop in `apps/web-platform/scripts/sentry-monitors-audit.sh`
   reversed to try `de.sentry.io` first.
3. A fail-closed residency mismatch detector in the same script refuses
   to emit an audit artifact whenever the probed host region disagrees
   with the DSN cluster substring (exit 2, no `gh release upload`).

**Replacement evidence:** pending — tracked at #3861. Until Phase A2
lands, the production DSN (`o4511123328466944.ingest.de.sentry.io`) and
`apps/web-platform/infra/sentry/*.tf` are the authoritative DE residency
signals. Phase A2 (cluster surgery — `terraform state rm`, US shadow-org
teardown, token rotation, DE re-apply) is operator-prereq-gated and
ships under a separate plan/PR; on its merge a new
`sentry-migration-audit-<post-fix-date>.md` regenerated against the DE
cluster will become the load-bearing §5(2) artifact, and PA8's last-line
pointer in `knowledge-base/legal/article-30-register.md` will be updated
to reference it.
