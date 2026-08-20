---
title: "Sentry legacy issue-alert read API returned 410, transiently wedging the sentry Terraform root"
date: 2026-07-17
incident_pr: "#6637"
incident_window: "2026-07-17 ~18:00–20:00Z"
recovery_at: "2026-07-17 ~20:00Z (Sentry restored the endpoint); durable fix in #6637"
suspected_change: "External: Sentry transiently retired the legacy GET /projects/{org}/{project}/rules/{id}/ issue-alert read endpoint. #6589 (same day) had switched apply-sentry-infra.yml to a full-root plan, converting a latent provider dependency into a CI-fatal one."
brand_survival_threshold: single-user incident
status: resolved-superseded
superseded_by: "#7590 (2026-08-19) — see § Supersession below; the transience finding is RETRACTED"
triggers:
  - external-vendor-api-change
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "n/a"
---

## Actor key

- `agent` — Claude Code did this autonomously (no operator ack required).
- `human` — Operator did this directly.

> **SUPERSEDED 2026-08-19 (#7590) — read [§ Supersession](#supersession-2026-08-19-7590) before
> acting on anything below.** The central finding of this report — that the 410 was **transient** —
> is retracted. The measurements are correct and are preserved verbatim as the dated record they
> are; the *inference* drawn from them is not. Every occurrence of "transient" below, including in
> the title, `recovery_at`, `suspected_change`, the 5-Whys chain, and "What went well", is the
> 2026-07-17 reading and is superseded.

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

## Supersession (2026-08-19, #7590)

This is a **dated record**. Nothing above has been edited away: the probes ran, and they returned
what this report says they returned. What is retracted is the reading of them.

**What was concluded:** the 410 was a transient vendor blip, self-clearing, confirmed by a clean
re-probe on beta2 at fix time.

**What is now measured:** Sentry deprecated the legacy alert-rule API family on **2026-05-14** and
serves it under **scheduled brownouts** — 410 for a window on a recurring schedule, 200 outside it.
Both states were observed in a single session on 2026-08-19 against the same token and the same
host, with nothing changed on our side: 410 at ~20:5x UTC, then 200/200/200 at 21:23 UTC. The
endpoint was never restored, because it was never transiently broken. It is retired, on a schedule.

**Which specific claims this retracts:**

| Location | Retracted claim | Corrected reading |
|---|---|---|
| Title | "transient wedge" | A scheduled brownout of a deprecated API family, not a transient wedge. |
| `recovery_at:` | "Sentry restored the endpoint" | Sentry restored nothing. The probe fell outside the next brownout window. |
| `suspected_change:` | "Sentry **transiently** retired…" | Sentry **permanently** retired it on 2026-05-14 and brownouts it on a schedule. |
| 5-Whys #2 | "transiently retired" | Same. The chain's other four steps stand — the full-root switch (#6589) and the beta2 pin were real amplifiers. |
| MTTR | "~2h to endpoint restoration; self-clearing" | Not self-clearing. The window closed. There is no MTTR for a deprecation. |

**The "What went well" entry is the one to read hardest — it commends the method that produced the
error.** "Phase 0 measure, don't trust caught that the 410 was transient (reproduced clean at fix
time)" credits a probe-and-conclude loop that, against a brownout, *cannot distinguish "restored"
from "outside the next window"*. The measurement discipline was right; the stopping rule was not. A
single clean re-probe is not evidence of recovery when the failure is schedule-shaped — that
requires either the response headers (`x-sentry-deprecation-date`,
`x-sentry-replacement-endpoint`, which name the retirement directly and were present the whole
time) or probing across more than one window. The header-reading tripwire shipped in #7590 exists
because this loop could not have caught it.

**What still stands.** The "no customer impact" assessment stands.

**What does NOT stand, and was not known when this note was first drafted: the bump did not make
the root immune.** The durability rationale carried by every artifact in this set — that v0.15.3
(`jianyuan/terraform-provider-sentry#885`) moved `sentry_issue_alert` reads off the legacy endpoint,
so `0.15.4` no longer depends on it — was **changelog-sourced and never plan-measured**, because
observing it requires being inside a brownout window. CI measured it on 2026-08-20 with `jianyuan/sentry v0.15.4` installed: run
`32362401543` (11:09:07Z) took `410 "This API no longer exists"` on **29 of 29**
`sentry_issue_alert` reads and failed `terraform plan`, while run `32362320701`
**one minute earlier** (11:08:09Z), same branch, same pin, succeeded. The same
alternation appears on 2026-08-19 (17:43 pass / 18:26 fail; 21:21 pass / 21:30 fail). So `0.15.4` still reads the
deprecated path, and the sentry Terraform root is still wedged by every brownout. The bump remains
defensible as stable-over-beta; it is **not** a fix for the 410, and #6636 did not durably close
this. Tracked in #7650. The action-items section
stands — the residual work is tracked under #7590 and #7634, not here.

**Cross-references.** The same retraction is recorded on every artifact that carried the
transience reading, so none of them reads as still-live on its own:

- `apps/web-platform/infra/sentry/versions.tf` — inline block on the provider pin.
- ADR-031 §Amendment 2026-08-19 (#7590) — the per-endpoint replacement table and full brownout
  evidence.
- `knowledge-base/project/plans/2026-07-17-fix-sentry-issue-alert-410-provider-bump-plan.md`
  § Supersession — the Phase 0 gate whose stopping rule produced this reading.
- `knowledge-base/project/learnings/2026-07-17-transient-provider-410-reproduce-before-choosing-a-fix.md`
  § Supersession — the generalised "may be transient" rule, half retracted. Read that one before
  applying its Key Insight to any other vendor-API break.
- `knowledge-base/project/specs/feat-one-shot-6636-sentry-alert-migration/phase0-measurement-evidence.md`
  § Supersession — the raw Phase 0 measurements, which stand; only §0.1's Finding is retracted.
- `knowledge-base/project/learnings/integration-issues/2026-08-19-a-vendor-brownout-is-not-a-flake-and-the-header-said-so-all-along.md`
  — the successor learning.
