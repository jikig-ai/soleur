---
title: "Postmortem: v0.244.1 published GREEN with an image production could not pull — prod STILL undeployable"
date: 2026-07-29
incident_pr: 7071
incident_window: "2026-07-29 ~16:01 UTC (release v0.244.1 published green; deploy died image_pull_failed) → ONGOING at time of writing. The operator's ~21:00 token fix restored the PUSH/bridge leg only; the HOST-pull leg is still failing, and every release since has failed image_pull_failed (v0.244.3, v0.245.0, v0.246.0, v0.246.1). The underlying GHCR-read death predates the window and was undetected."
recovery_at: "n/a — NOT recovered. The ~21:00 token fix restored only the push-side bridge. Production is serving stale code and no release has deployed since 2026-07-29."
suspected_change: "No single change. A CF Access service-token rotation did not propagate to Doppler (the doppler_secret resources carry lifecycle.ignore_changes = [value], so terraform apply reports 'No changes' while the stale value keeps being served). The bridge failed, the zot mirror step was warn-only by design, and the release published anyway — a design that was correct ONLY while GHCR was a working break-glass read path. GHCR's read PAT had been revoked out-of-band, so that premise was already false."
brand_survival_threshold: single-user incident
status: ongoing
triggers:
  - image_pull_failed
  - release published green with no pullable image
  - websocket bad handshake on the registry bridge
  - GHCR read PAT revoked (401) / minter disabled (403 DENIED)
  - web-1 boot-baked Doppler service token revoked (2026-07-30T11:19:30.614Z) — empty ZOT_REGISTRY_URL sends the zot gate down its "dark, pre-provisioning" branch
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "n/a — availability incident. No personal data was accessed, exfiltrated, altered or lost: the failure is a container image that could not be pulled. No database, storage bucket, or user-facing data path was involved."
---

## Summary

The web-platform release for **v0.244.1** built, pushed to GHCR, and **published green**. The
deploy then died `image_pull_failed` and production sat undeployable for roughly five hours.

Every layer reported success. The release workflow was green because the zot-mirror step is
warn-only *by design* — a correct decision **while GHCR was a working break-glass fallback**.
That premise was no longer true, and nothing in the pipeline knew.

## Timeline

| Time (UTC) | Event |
|---|---|
| (before) | The GHCR read credential is revoked out-of-band. `GHCR_MINTER_DISABLED=true`. Nothing detects this, because nothing reads from GHCR while zot is healthy. |
| (before) | A Cloudflare Access service-token rotation does not propagate to Doppler. `terraform apply` reports "No changes" — every `doppler_secret` carrying a token declares `lifecycle.ignore_changes = [value]`. |
| 2026-07-29 ~16:01 | Release run 30468080168: the CF-tunnel bridge fails — `failed to connect to origin error="websocket: bad handshake"`. CF Access refused the upgrade. |
| ~16:01 | The zot mirror step degrades, emits `mirror_status=degraded`, `exit 0`, and is `continue-on-error: true`. The release publishes **green**. |
| ~16:0x | Job 90634334826: `ci-deploy.sh exited 1 (reason=image_pull_failed, tag=v0.244.1)`. zot has no image; the GHCR fall-through hits a revoked PAT. |
| ~16:0x → ~21:00 | Production undeployable. The annotation, the step summary, the Slack message and two ADRs all state that GHCR covers this. None of that is true. |
| ~21:00 | Operator sets the live Access service-token value on the Doppler `prd` ROOT config. **The bridge recovers — the PUSH leg only.** |
| 2026-07-29 21:54 → 2026-07-30 16:30 | **Eight consecutive `Web Platform Release` runs fail**, every one at `image_pull_failed`: v0.244.3, v0.245.0, v0.246.0, v0.246.1. Production keeps serving stale code. No alert names this; the release run goes red and the failure is read each time as "the known incident". |
| 2026-07-30 16:43 | PR #7071 merges. Its new gate reports `mirror_verified=true` — the image **is** in zot at this build's digest — and the deploy **still** fails `image_pull_failed`. This is the first run that isolates the fault: push-side proven good, host-side broken. |

## Root cause

**Three independent failures composed, and each was individually survivable:**

1. **A credential rotation that Terraform structurally cannot propagate.** `ignore_changes =
   [value]` is deliberate (removing it trades silent staleness for churn), so a stale token is
   invisible to `terraform plan` forever.
2. **A detector that could not detect the case it was written for.** The token-drift script's
   enumeration regex was `CF_API_TOKEN[A-Z0-9_]*`, which **cannot match**
   `REGISTRY_PUSH_ACCESS_TOKEN_*` — the first case its own header cites. And nothing invoked the
   script at all: `grep -rln check-cloudflare-token-drift` matched only the script itself.
3. **A warn-only gate resting on a retracted premise.** The mirror was allowed to fail the release
   open because GHCR was a working fallback. GHCR was dead. Receiving is not serving — GHCR was
   still dual-pushed, so every dashboard showed images arriving.

The deepest cause is (3), and it is not a coding error: it is a **premise that decayed without
anything noticing**. A fallback is by definition only exercised when the primary fails, which is
exactly when you discover it was dead.

## What made it worse

- **The pipeline asserted the false premise back to the operator.** The `::warning::` said "release
  UNAFFECTED (GHCR primary/break-glass)"; the step summary said "release OK (GHCR primary)"; the
  runbook said the fallback registry "is always warm and current". An operator reading any of these
  during the incident was being told the wrong thing by the system itself.
- **The first diagnosis was wrong.** `HTTP 200` + empty body from `https://registry.soleur.ai/v2/`
  was read as a broken origin. It is **correct behaviour** — the ingress is `tcp://`, consumable
  only via `cloudflared access tcp`, and a plain HTTPS GET is not a WebSocket upgrade for that
  stream. The repo already documented this in the bridge action's own header.

## NOT resolved — corrected 2026-07-30

**This report originally said `status: resolved` with `recovery_at: 2026-07-29 ~21:00`. That was
wrong, and it was wrong in the direction that matters: it recorded an ongoing production outage as
closed.** The error was made while shipping the PR whose entire subject is removing false claims
from this pipeline, which is the sharpest possible demonstration of the failure class — an incident
report is a claim like any other, and "the operator fixed the token" was inferred from the
remediation rather than measured against the deploy.

What the measurement shows: **eight consecutive release runs have failed at `image_pull_failed`
since 2026-07-29**, spanning v0.244.3 → v0.246.1. Production is serving stale code right now.

The token fix restored **one of two legs**. The evidence that separates them arrived with #7071's
own instrumentation:

| Leg | Credential / transport | Status |
|---|---|---|
| CI **push** → zot | `REGISTRY_PUSH_ACCESS_TOKEN_*` over the CF Tunnel + CF Access | **healthy** — `mirror_verified=true`, image confirmed at the build's digest |
| Host **pull** ← zot | `ZOT_PULL_*` over the private NIC, no tunnel, no CF Access | **BROKEN** — `image_pull_failed` |

This is exactly the residual ADR-096 clause (f) names and #7071 deliberately did **not** close:
"It asserts the manifest is in zot AND readable by the PUSH credential over the CF Tunnel. It does
NOT prove the host can pull."

One thing #7071 did buy, and it is the reason this was diagnosable at all: before it, a failed
mirror and a failed host-pull produced the same undifferentiated red. `mirror_verified=true`
alongside `image_pull_failed` is a *new* signal, and it collapses the search space from "the whole
registry path" to one leg.

## The host-pull suspect list was wrong — measured 2026-07-30 (#7095)

The three candidates clause (f) enumerates — the private `10.0.1.10 → 10.0.1.30:5000` NIC path
being down, `ZOT_PULL_*` gone stale, and zot `accessControl` granting push-read but not pull-read —
were treated above as "the live suspect list". **All three were measured and all three are
healthy.** Recording them here as suspects, unqualified, sent the next reader at a dead end.

The actual fault is **one credential level up, and it is a second, distinct incident**: web-1's
boot-baked full-`prd` Doppler **service token** in `/etc/default/webhook-deploy` was revoked at
**2026-07-30T11:19:30.614Z**. With it dead, `doppler secrets get` returns empty, `ZOT_REGISTRY_URL`
is empty, and the zot gate takes its `"dark, pre-provisioning"` branch — so it never contacts zot
at all and falls through to an unauthenticated GHCR pull of a private package → `auth_denied` →
`image_pull_failed`.

The two incidents share only that reason string. That is the whole reason eight red releases read
as one known incident: **`image_pull_failed` is emitted by both a dead mirror and a dead
credential**, and nothing downstream distinguished them.

The evidence that separates them:

| # | Measurement | Result |
|---|---|---|
| E1 | Unit-failure onset is +18.17s / +26.14s after the revocation mint, with zero failures in the preceding 53h | the revocation is the trigger, not a coincidence |
| E2 | `inngest-heartbeat.service` carries a **non-optional** `EnvironmentFile` for `/etc/default/inngest-server` and ran healthy until 11:19:56 | the file exists; the `web-probe-read-token.tf` parenthetical claiming otherwise is stale |
| E3 | `ExecStart` branches on `[ -n "$DOPPLER_TOKEN" ]`, so an *always*-empty token would make behaviour invariant across the revocation — it flipped | the token was live, then was not |
| E4 | Terraform's own copy of the token is **alive (HTTP 200)**, and its rendered env line carries no CR / `#` / space / newline | the remediation has a working credential to deliver |
| E5 | Push leg healthy (`mirror_verified=true`) throughout | confirms the fault is host-side, not registry-side |

E4 is the precondition the entire remediation rests on: the fix delivers Terraform's live token to
the host over the existing no-SSH config channel, rather than minting a new one.

**Generalizable:** a suspect list published in an incident report is a *claim*, and an unmeasured
claim in a post-mortem is worse than no claim — it is read as diagnosis. Suspects belong in a
report only with their measurement state attached.

## Partial remediation (the push leg)

Remediation of the push leg was the token value. The durable fix for that half is PR #7071:

- The mirror is **release-blocking**: `continue-on-error` removed, `degraded()` exits non-zero, and
  a positive post-copy `crane digest` assertion proves the manifest is in zot **at the expected
  digest** before `mirror_status=ok`.
- `migrate` and `deploy` now gate on `needs.release.result == 'success'`. Both `if:` conditions led
  with `always() &&`, which discards skip-on-failed-`needs` — so the gate could have protected
  nothing while leaving prod on new schema + old code.
- The token-drift detector covers Access service tokens and is actually invoked (twice daily), with
  three verdict-specific operator emails so an UNVERIFIABLE or could-not-run outcome is never
  reported as a stale credential.
- The false GHCR-fallback claims are retracted wherever they were written down: `reusable-release.yml`,
  `zot-registry-revert.md`, ADR-096, ADR-088, the principles register, and `model.c4`.

## Why the remediation never arrived — measured 2026-08-01 (#7095, PR #7133)

The root cause above is correct and unchanged: web-1's boot-baked Doppler token is revoked, the zot
gate goes dark, and the pull falls through to an unauthenticated GHCR fetch. **What it did not
explain is why a merged fix did not land.** PR #7097 shipped the correct infra code on 2026-07-31.
Production stayed down. Every release since has failed identically.

There is a **second dead credential, one layer up**, and it is the one that blocks delivery:

- On 2026-07-28 the `ci_ssh` **Cloudflare Access service token** was rotated out-of-band during
  incident response. Cloudflare returns a service token's `client_secret` **only at create**, so
  Terraform state and Doppler both went stale invisibly and `terraform plan` stayed clean — there is
  nothing in the plan graph that can observe a credential the provider will not read back. Same
  write-once-invisible shape as the `REGISTRY_PUSH_ACCESS_TOKEN_*` rotation in the original window,
  one route over (`ssh.` instead of `registry.`).
- #7097's SSH-free `local-exec` delivery leg (`terraform_data.deploy_pipeline_fix`) carries
  `depends_on` `terraform_data.infra_config_handler_bootstrap`, which is **root-SSH-provisioned**.
  Run `30650564509` destroyed both resources, then failed on
  `ssh: handshake failed: connection reset by peer`. State was left emptier than reality and the
  payload never shipped.
- Its precondition was *"confirm the last green run of `apply-deploy-pipeline-fix.yml`"* — a citation
  of a past state, not a probe of the present one. The last green run was 2026-07-30T16:30Z; the
  channel died the following day.

**The detector was not the gap, and this is the sharpest lesson in the incident.**
`check-cloudflare-token-drift.sh` runs twice daily and reported `verdict: dead` on runs
`30608371251`, `30653453432` and `30686984837` — naming the credential, the symptom
(`HTTP 403 from ssh.soleur.ai`) and the remedy, three times, with `notify-ops-email` firing every
time. Production stayed down regardless. The verdict **blocked nothing** and **reached a channel
nobody acts on**. `operator-digest` harvests `action-required` *issues*; it cannot see an email.

Two corrections to earlier framing, both re-derived rather than restated:

- The consecutive-failure count is **every release since `30465249534`** (2026-07-29T15:18Z) — 15 at
  the time of writing and still climbing. The "eight" in the #7103 row above was a point-in-time
  count that rots while the channel is dark.
- The `cx33` host **cannot be replaced**: `available=false` AND `available_for_migration=false` in
  all six Hetzner datacenters, verified live. `-replace` destroys before it creates, so
  `hr-prod-host-config-change-immutable-redeploy`'s own precondition fails and the remedy is
  unavailable, not merely inadvisable. A fresh host would also need 16 SSH installers over the same
  dead channel. Recorded as ADR-154.

**Still ONGOING at the time of this update.** PR #7133 ships the mechanism (a liveness gate on the
shared SSH bridge, an in-band `ci-ssh-token-replace` arm, and `action-required` escalation), not the
recovery. Production is `v0.244.0`; the recovery dispatches run post-merge under per-command
operator authorization.

## Prevention

The generalizable lesson is **not** "make the mirror blocking". It is that a *fallback's health is a
premise, and premises need detectors too*. Concretely:

- A gate whose safety argument names a fallback must fail closed when that fallback's health is
  unknown — not merely when it is known-bad.
- A credential the pipeline depends on needs a detector that enumerates from the source of truth
  (Doppler), never a hardcoded or hand-written key pattern. The regex that missed
  `REGISTRY_PUSH_ACCESS_TOKEN_*` was written by someone looking at the incident it was meant to catch.
- "Receiving is not serving." Dual-push dashboards showed green throughout. Verify the READ path.

## Action Items & Follow-ups

| Issue | Item | Owner |
|---|---|---|
| #7095 | **THE LIVE ONE — production has not deployed since 2026-07-29.** Root cause measured 2026-07-30 (see the section above): web-1's boot-baked full-`prd` Doppler **service token** was revoked at 11:19:30.614Z, so the zot gate goes dark and the pull falls through to an unauthenticated GHCR fetch. NOT `ZOT_PULL_*` — all three clause (f) suspects measured healthy. Remediation delivers Terraform's live token over the no-SSH config channel. **UPDATED 2026-08-01 (PR #7133):** that diagnosis is correct and was not sufficient — the merged #7097 fix never ARRIVED, because the `ci_ssh` **Cloudflare Access** token that the delivery channel authenticates with is also dead (rotated out-of-band 2026-07-28). See §"Why the remediation never arrived". PR #7133 ships the repair mechanism; the recovery dispatches run post-merge. **P1.** Stays open until `/health` serves ≥ v0.247.0 with a reset uptime. | `agent` |
| #7103 | Nothing alerts on "N consecutive release-deploy failures". Eight went red over a day and each was read as "the known incident" rather than a distinct live fault. The release run failing is not itself a monitored condition. Also carries: credential-liveness telemetry off the box, and the fleet-wide 19-of-19 web-1 installer pinning. | `agent` |
| #7104 | `apply-deploy-pipeline-fix`'s verify step re-polls but never re-POSTs, so it cannot recover from the documented nonce-1 webhook-restart race. Deliberately NOT fixed under outage pressure: the fix puts `continue-on-error` on a fail-closed gate, and that gate's latched false-green (#6594) is what let this outage class hide. | `agent` |
| #7077 | Extend the fail-closed mirror invariant to the inngest image, and fix the live #6416 skip. `cloud-init-inngest.yml` hard-pins GHCR with no zot path, so its dedicated host is un-bootable now. | `agent` |
| #7078 | Verify the new gate on the first real release. Genuinely un-automatable pre-merge — the faithful test is a production release. Enrolled as a follow-through. | `agent` |
| #7079 | Residual items: the two sibling false `/v2/` gates in `cloud-init.yml` (`curl -s -o /dev/null` with no `-w '%{http_code}'`, so a 500 or empty 200 passes), `zot-entry-gate.sh` wire-or-delete, and the orphan-draft / stale-release-notes leak. | `agent` |
| #6122 | The open architectural debt this incident exposes: **production has one registry and no fallback.** Restoration is a zero-touch-mintable GHCR pull credential or a second mirror. Neither is enumerated as a deliverable anywhere — ADR-096 clause (g) previously claimed two trackers, both of which were closed NOT_PLANNED. | `operator` |
