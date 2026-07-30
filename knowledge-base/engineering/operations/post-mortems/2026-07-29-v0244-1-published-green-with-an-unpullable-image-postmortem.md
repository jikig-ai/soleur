---
title: "Postmortem: v0.244.1 published GREEN with an image production could not pull — prod undeployable ~5h"
date: 2026-07-29
incident_pr: 7071
incident_window: "2026-07-29 ~16:01 UTC (release v0.244.1 published green; deploy died image_pull_failed) → ~21:00 UTC (operator remediated the CF Access service token out-of-band). The underlying GHCR-read death predates the window and was undetected."
recovery_at: "2026-07-29 ~21:00 UTC — the stale REGISTRY_PUSH_ACCESS_TOKEN_* value was replaced on the Doppler `prd` ROOT config, restoring the CF-tunnel bridge to zot."
suspected_change: "No single change. A CF Access service-token rotation did not propagate to Doppler (the doppler_secret resources carry lifecycle.ignore_changes = [value], so terraform apply reports 'No changes' while the stale value keeps being served). The bridge failed, the zot mirror step was warn-only by design, and the release published anyway — a design that was correct ONLY while GHCR was a working break-glass read path. GHCR's read PAT had been revoked out-of-band, so that premise was already false."
brand_survival_threshold: single-user incident
status: resolved
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
| ~21:00 | Operator sets the live Access service-token value on the Doppler `prd` ROOT config. Bridge recovers. |

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

## Resolution

Remediation was the token value. The durable fix is PR #7071:

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
| #7077 | Extend the fail-closed mirror invariant to the inngest image, and fix the live #6416 skip. `cloud-init-inngest.yml` hard-pins GHCR with no zot path, so its dedicated host is un-bootable now. | `agent` |
| #7078 | Verify the new gate on the first real release. Genuinely un-automatable pre-merge — the faithful test is a production release. Enrolled as a follow-through. | `agent` |
| #7079 | Residual items: the two sibling false `/v2/` gates in `cloud-init.yml` (`curl -s -o /dev/null` with no `-w '%{http_code}'`, so a 500 or empty 200 passes), `zot-entry-gate.sh` wire-or-delete, and the orphan-draft / stale-release-notes leak. | `agent` |
| #6122 | The open architectural debt this incident exposes: **production has one registry and no fallback.** Restoration is a zero-touch-mintable GHCR pull credential or a second mirror. Neither is enumerated as a deliverable anywhere — ADR-096 clause (g) previously claimed two trackers, both of which were closed NOT_PLANNED. | `operator` |
