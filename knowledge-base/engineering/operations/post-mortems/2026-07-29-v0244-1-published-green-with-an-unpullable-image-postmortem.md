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
NOT prove the host can pull." The three candidate causes it enumerates are the live suspect list:
the private-net `10.0.1.10 → 10.0.1.30:5000` path being down; `ZOT_PULL_*` gone stale (the *same*
rotation-staleness class as the original trigger, one credential over); or zot `accessControl`
granting push-read but not pull-read. `web-zot-consumer-probe.sh` is the built-for-this probe.

One thing #7071 did buy, and it is the reason this was diagnosable at all: before it, a failed
mirror and a failed host-pull produced the same undifferentiated red. `mirror_verified=true`
alongside `image_pull_failed` is a *new* signal, and it collapses the search space from "the whole
registry path" to one leg.

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
| #7095 | **THE LIVE ONE — production has not deployed since 2026-07-29.** The host-pull leg (`ZOT_PULL_*` over the private NIC) is broken while the push leg is proven healthy. Highest-prior suspect is `ZOT_PULL_*` staleness: the *same* rotation-invisibility class as the original trigger, one credential over. Run `web-zot-consumer-probe.sh` first. **P1.** | `agent` |
| #7095 | Nothing alerts on "N consecutive release-deploy failures". Eight went red over a day and each was read as "the known incident" rather than a distinct live fault. The release run failing is not itself a monitored condition. | `agent` |
| #7077 | Extend the fail-closed mirror invariant to the inngest image, and fix the live #6416 skip. `cloud-init-inngest.yml` hard-pins GHCR with no zot path, so its dedicated host is un-bootable now. | `agent` |
| #7078 | Verify the new gate on the first real release. Genuinely un-automatable pre-merge — the faithful test is a production release. Enrolled as a follow-through. | `agent` |
| #7079 | Residual items: the two sibling false `/v2/` gates in `cloud-init.yml` (`curl -s -o /dev/null` with no `-w '%{http_code}'`, so a 500 or empty 200 passes), `zot-entry-gate.sh` wire-or-delete, and the orphan-draft / stale-release-notes leak. | `agent` |
| #6122 | The open architectural debt this incident exposes: **production has one registry and no fallback.** Restoration is a zero-touch-mintable GHCR pull credential or a second mirror. Neither is enumerated as a deliverable anywhere — ADR-096 clause (g) previously claimed two trackers, both of which were closed NOT_PLANNED. | `operator` |
