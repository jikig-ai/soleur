# Phase 0 Measurement Evidence — #6636 Sentry 410 / provider bump

> **The measurements below stand; one INFERENCE in §0.1 is superseded (2026-08-19, #7590).** The
> `0/0/0` plan and the zero 410s were really observed. They do **not** show the retirement was
> transient or that Sentry "had restored it": the endpoint was permanently deprecated 2026-05-14
> and is served under scheduled brownouts, so a plan run between windows returns clean either way.
> See § Supersession at the foot of this file.

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

## Supersession (2026-08-19, #7590)

Scope: **§0.1's Finding paragraph only.** Every measurement in this file — the `0/0/0` plan, the
refresh counts (23/49/4), the version enumeration, the lockfile hashes — is unchanged and still
correct.

**Retracted:** "the `410 …` the issue observed at ~18:00–20:00Z was a **transient** Sentry-side
retirement … by fix time Sentry had restored it".

**Corrected:** Sentry deprecated the legacy alert-rule API family on 2026-05-14 and serves it under
**scheduled brownouts** — 410 inside a recurring window, 200 outside it. Both states measured on
2026-08-19 in one session against the same token and host: 410 at ~20:5x UTC, 200/200/200 at 21:23
UTC. The 18:00–20:00Z observation was a brownout window; the Phase 0 plan ran outside one. Nothing
was restored.

**Unaffected:** §0.2's durability datum and the `0.15.4` conclusion. The bump is still right, for a
reason §0.1 could not supply — `0.15.4`'s read path is not in the deprecated family at all, so it
is immune to the brownout rather than merely lucky about its timing.

**What §0.1 should have recorded.** The response headers, which name the retirement directly and
were present throughout: `x-sentry-deprecation-date`, and per-endpoint
`x-sentry-replacement-endpoint` (`rules/` → `workflows/`, `alert-rules/` → `detectors/`). A single
clean plan cannot distinguish "restored" from "outside the next window"; a header can. #7590 ships
that check as a tripwire in `sentry-monitors-audit.sh`'s `curl_retry`.
