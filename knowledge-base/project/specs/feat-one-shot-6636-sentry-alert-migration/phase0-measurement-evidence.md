# Phase 0 Measurement Evidence — #6636 Sentry 410 / provider bump

Measured 2026-07-17 against **live** Sentry state (org `jikigai-eu` project, R2 backend,
`SENTRY_IAC_AUTH_TOKEN` from Doppler `prd_terraform`). Terraform v1.10.5, linux_amd64.

## 0.1 — Reproduce the break on the pinned `0.15.0-beta2`

`terraform init -input=false` → exit 0.
`terraform plan -no-color` → **exit 0**, `No changes. Your infrastructure matches the configuration.`

- **410 count: 0.** The break did NOT reproduce.
- All resources refreshed: `sentry_issue_alert` ×23, `sentry_cron_monitor` ×49, `sentry_uptime_monitor` ×4.
- Only output: `sentry_issue_alert` deprecation warnings ("migrate to `sentry_alert`").

**Finding:** the `410 "This API no longer exists"` the issue observed at ~18:00–20:00Z was a
**transient** Sentry-side retirement of the legacy issue-alert read endpoint; by fix time Sentry
had restored it, so even the un-bumped beta2 provider plans clean. The bump is therefore NOT
required to clear the *current* 410 — but see 0.4 for why it is still the right durable fix.

## 0.2 — Version enumeration

`curl -s https://registry.terraform.io/v1/providers/jianyuan/sentry/versions | jq -r '.versions[].version'`
Stable line: `0.15.0, 0.15.1, 0.15.2, 0.15.3, 0.15.4`. Latest stable = **0.15.4**. Current pin = `0.15.0-beta2`.

**Durability datum (changelog):** provider **v0.15.3** (`jianyuan/terraform-provider-sentry#885`,
"fix: Update reads from GET endpoint") switched `sentry_issue_alert` reads OFF the legacy
`/rules/{id}/` endpoint. So `0.15.4` (> 0.15.3) does not depend on the endpoint that returned 410
— the bump future-proofs the root against the legacy endpoint's eventual *permanent* retirement.

## 0.3 — Bump + upgrade

`versions.tf`: `0.15.0-beta2` → `0.15.4`. `terraform init -upgrade` → installed `v0.15.4`.
`terraform providers lock -platform=linux_amd64 -platform=darwin_arm64 -platform=darwin_amd64` →
regenerated `.terraform.lock.hcl`: `version = "0.15.4"`, 3 `h1:` + 14 `zh:` hashes (all CI+dev platforms; `linux_amd64` present for CI `init -lockfile=readonly`).

## 0.4 — MEASURE (decision datum) on `0.15.4`

- `terraform validate` → **exit 0** (Success; deprecation warning present, now naming the
  `sentry_project_error_monitor` / `sentry_project_issue_stream_monitor` migration data sources).
- `terraform plan -no-color` → **exit 0**, `No changes. Your infrastructure matches the configuration.`
  - **410 count: 0.**
  - Full-root refresh: `sentry_issue_alert` ×23, `sentry_cron_monitor` ×49, `sentry_uptime_monitor` ×4 — **no drift, 0/0/0.**
- `terraform fmt -check versions.tf` → clean (exit 0).

## 0.5 — Decision fork

**410 cleared AND full-root plan no-op → Option A (provider bump).** Shipped as a
provider-version-only change (`versions.tf` + `.terraform.lock.hcl`), no state surgery.
Option B (`sentry_alert` migration) NOT reached — the `monitor_ids` blocker persists at 0.15.4;
deferral re-affirmed in ADR-031 (Amendment 2026-07-17, #6636).
