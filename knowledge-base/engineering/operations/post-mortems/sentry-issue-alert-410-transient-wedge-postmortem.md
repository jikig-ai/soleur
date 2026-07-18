---
title: "Sentry legacy issue-alert read API returned 410, transiently wedging the sentry Terraform root"
date: 2026-07-17
incident_pr: "#6637"
incident_window: "2026-07-17 ~18:00–20:00Z"
recovery_at: "2026-07-17 ~20:00Z (Sentry restored the endpoint); durable fix in #6637"
suspected_change: "External: Sentry transiently retired the legacy GET /projects/{org}/{project}/rules/{id}/ issue-alert read endpoint. #6589 (same day) had switched apply-sentry-infra.yml to a full-root plan, converting a latent provider dependency into a CI-fatal one."
brand_survival_threshold: single-user incident
status: resolved
triggers:
  - external-vendor-api-change
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "n/a"
---

## Actor key

- `agent` — Claude Code did this autonomously (no operator ack required).
- `human` — Operator did this directly.

# Incident Overview

On 2026-07-17 (~18:00–20:00Z) Sentry briefly returned `410 "This API no longer exists"` on the legacy issue-alert **read** endpoint (`GET /projects/{org}/{project}/rules/{id}/`) that the pinned `jianyuan/sentry 0.15.0-beta2` provider's `sentry_issue_alert` resource used. Because #6589 (same day) had switched `apply-sentry-infra.yml` to a **full-root** plan, all 23 `sentry_issue_alert` resources refreshed on every PR and on the main apply — so the transient 410 wedged the required `sentry-destroy-required` gate and the main apply. **No production impact:** the paging rules exist server-side in Sentry and kept firing throughout; only Terraform *management* of them was blocked (an IaC-management-plane degradation, not a customer-facing outage or a data exposure).

## Status

resolved

## Symptom

`terraform plan` on `apps/web-platform/infra/sentry/` aborted with `Client error … status 410: {"message":"This API no longer exists."}` on every `sentry_issue_alert` read → the required `sentry-destroy-required` PR gate failed closed on PR #6622, and `apply-sentry-infra.yml` on `main` would have failed on its next run (last green 2026-07-17T17:55Z).

## Incident Timeline

- **Start time (detected):** 2026-07-17 ~18:00–20:00Z (410 first observed, filed as #6636)
- **End time (recovered):** 2026-07-17 ~20:00Z (endpoint restored server-side); durable fix merged in #6637
- **Duration (MTTR):** ~2h to endpoint restoration; the wedge was self-clearing once Sentry restored the read API

| Actor | Time (UTC) | Action |
|---|---|---|
| human | 2026-07-17 ~18:00–20:00Z | 410 observed on PR #6622; issue #6636 filed. |
| agent | 2026-07-17 later | Phase 0 measured live Sentry state — 410 no longer reproduced on beta2 (transient). |
| agent | 2026-07-17 later | Durable fix: bumped provider beta2 → 0.15.4 (reads off the legacy endpoint per v0.15.3 #885). |

## Detection (+ MTTD)

- **How detected:** the required `sentry-destroy-required` CI gate turned red on PR #6622 (external/CI report, not a dedicated monitor).
- **MTTD:** immediate (surfaced as a red required check on the next PR touching the sentry surface).

## Root Cause(s) — 5-Whys

1. Why did the sentry root fail to plan? → Every `sentry_issue_alert` read returned 410.
2. Why 410? → Sentry transiently retired the legacy `GET …/rules/{id}/` read endpoint the beta2 provider used.
3. Why was it CI-fatal (not latent)? → #6589 switched the apply to a full-root plan, so all 23 issue-alert reads now refresh on every PR + apply (previously outside the `-target=` allow-list).
4. Why was the provider on the legacy read path? → It was pinned at `0.15.0-beta2`, which predates v0.15.3's read-endpoint rework (#885).
5. Root cause: a **beta provider pinned to a soon-deprecated vendor read endpoint**, exposed by a same-day CI change (full-root plan) that removed the latency between "endpoint deprecated" and "CI red".

## Impact details

### Services Impacted

Terraform management of the Sentry paging plane (23 issue alerts + 49 cron + 4 uptime monitors). **Not** the runtime paging itself — rules kept firing server-side.

### Customer Impact (by role)

None. No customer-facing surface degraded; no personal data exposed. The exposure vector would only have materialized if a paging rule had been *changed/dropped* while management was blocked — which did not occur.

## Lessons Learned

### What went wrong

- A beta provider pinned to a vendor read endpoint that carried a standing deprecation warning was a latent single point of failure; the #6589 full-root switch removed its safety margin the same day.

### What went well

- Phase 0 "measure, don't trust" caught that the 410 was **transient** (reproduced clean on beta2 at fix time), preventing an over-fix (the 23-resource `sentry_alert` state-surgery migration the issue proposed).
- The durable fix (bump to 0.15.4, which reads off the legacy endpoint per v0.15.3 #885) future-proofs against a *permanent* retirement with zero state change.

## Action Items & Follow-ups

_No action items — incident fully resolved in the source PR with no residual work._
