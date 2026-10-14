---
title: "Deploy-time cosign verification silently did not run for seven weeks (verifier-image pull presented a revoked GHCR PAT)"
date: 2026-09-21
incident_pr: 8456
incident_window: "credential revoked by 2026-07-29 (measured in #7071) → fix merged via PR #8456 (verification graded by the #8037 probe)"
recovery_at: "TBD — the first post-apply deploy that logs IMAGE_VERIFY: ok, graded per host by scripts/followthroughs/cosign-verify-live-8037.sh"
suspected_change: "GHCR read PAT revoked (Phase-5 GHCR retirement, #7071); the cosign verifier-image pull kept presenting it from the deploy docker config"
brand_survival_threshold: aggregate pattern
status: ongoing
triggers:
  - deploy-time image signature verification (IMAGE_VERIFY_FAIL result=cosign_absent on every deploy)
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "n/a — no personal data involved; a supply-chain integrity control was not running, and no data was exposed"
---

## Actor key

- `agent` — Claude Code did this autonomously (no operator ack required).
- `agent-with-ack` — Claude Code did this AFTER operator confirmed via menu option per `hr-menu-option-ack-not-prod-write-auth`.
- `human` — Operator did this directly.

# Incident Overview

Every web-platform deploy runs `verify_image_signature()` in `ci-deploy.sh`: a pinned cosign
container verifies the pulled app image's signature before the image runs. The docker CLI pulls
that cosign container image (`ghcr.io/sigstore/cosign/cosign@sha256:57c0e93a…`, a PUBLIC image)
using credentials from its own `DOCKER_CONFIG`, which was the deploy config. That config carried
an inline `ghcr.io` auth: `GHCR_READ_TOKEN`, a classic PAT that #7071 measured as revoked on
2026-07-29. GHCR answers a revoked credential with DENIED where it serves the same public image
anonymously. So the verifier could never start, and every deploy logged
`IMAGE_VERIFY_FAIL: result=cosign_absent`.

In WARN mode, a verify failure does not block the deploy. It runs the resolved digest and sends a
Sentry `cosign_verify_event`. So for about seven weeks, every deploy ran its image with
**signature verification not performed**, and the failure read as a noisy but expected event.

## Status

ongoing — one of `resolved` / `unresolved but ended` / `ongoing`. Mirrors the `status:` frontmatter above; do not introduce a second source of truth.

## Symptom

`IMAGE_VERIFY_FAIL: result=cosign_absent` once per deploy, on every deploy, on `SYSLOG_IDENTIFIER=ci-deploy`. It came paired with a `stage=relogin_failed` GHCR re-login failure per deploy: 53 of each in the 7 days to 2026-09-10, and 89 in the 7 days to 2026-09-20 (#8036 diagnosis).

## Incident Timeline

- **Start time (detected):** 2026-09-10 (symptom filed as #8037 while diagnosing #8016)
- **End time (recovered):** TBD — see `recovery_at`
- **Duration (MTTR):** TBD (status not resolved)

Order of events (load-bearing: the redaction sentinel scans this table; the Actor key feeds the Actor column):

| Actor | Time (UTC) | Action |
|---|---|---|
| agent | 2026-07-29 | #7071 measures the host GHCR read PAT as revoked (GET /user 401) and retires GHCR as a host pull fallback. The verifier-image pull is not identified as a second consumer of that credential. |
| agent | 2026-09-10 | While diagnosing #8016, #8037 (`cosign_absent` 53/53) and #8036 (`relogin_failed` 53×) are filed as siblings. |
| agent | 2026-09-20T14:43 | #8036 diagnosis: the PAT is revoked, not expired; the cosign image is public (anonymous manifest HEAD 200). |
| agent | 2026-09-21T07:49 | Re-probed: token `GET /user` → 401; anonymous manifest HEAD → 200. |
| agent | 2026-09-21 | PR #8456: the verifier-image pull runs under an isolated anonymous docker config; the #8037 follow-through probe is added to grade per-host `IMAGE_VERIFY: ok`. |

## Participants and Systems Involved

Operator (single founder); Claude Code. Systems: `ci-deploy.sh` (web hosts), GHCR, the pinned cosign verifier image, Better Stack (journald via Vector), Sentry.

## Detection (+ MTTD)

- **How detected:** manual — surfaced while diagnosing an unrelated issue (#8016), not by an alert.
- **MTTD (mean time to detect):** about 6 weeks (2026-07-29 → 2026-09-10). No alert distinguished "verification failed" from "verification could not start".

## Triggered by

system — a credential retirement (#7071) whose second consumer was not inventoried.

## Root-cause hypothesis (triage)

Triage-time competing hypotheses; the post-resolution final root cause lives in the 5-Whys section below.

| Hypothesis | Supporting evidence | Disconfirming evidence | Status |
|---|---|---|---|
| The verifier-image pull presents the revoked deploy-config GHCR auth | Token 401 on `GET /user`; the same image HEADs 200 anonymously; one `cosign_absent` per deploy, no drift | none found | confirmed |
| The cosign image or digest was removed upstream | — | Anonymous manifest HEAD on the pinned digest returns 200 | rejected |

## Resolution

PR #8456 (#8036 1a): the verify `docker run` executes under `env -u DOCKER_AUTH_CONFIG` with
`DOCKER_CONFIG` pointed at a fresh directory holding
`{"auths":{},"credHelpers":{"ghcr.io":""}}`. The implicit verifier-image pull is therefore
anonymous, and it cannot fall back to an auto-detected credential store. The deploy config stays
mounted read-only into the container, so the `.sig` referrer fetch still authenticates. If the
isolated config cannot be prepared, `IMAGE_VERIFY_PREP: anon_config=unavailable` is logged, and
the #8037 probe grades that deploy as action-required.

> **Corrected 2026-09-22 (#8037):** the sentence "the `.sig` referrer fetch still authenticates"
> above was false when written. The pinned cosign image runs as uid 65532 and never read the
> `/root/.docker/config.json` mount; the 0600 deploy config was unreadable to that uid anyway. The
> first post-#8456 deploy therefore logged `result=verify_failed` (zot `401` on the `.sig` fetch).
> The fix, passing `--user` as the config owner plus `-e DOCKER_CONFIG` at the mount, and the
> measurements are in ADR-087's 2026-09-22 amendment.

## Recovery verification

Not yet recovered. Recovery is the #8037 follow-through probe exiting 0: every host that emitted
an `IMAGE_VERIFY` line after the `deploy_pipeline_fix` apply has a latest verdict of
`IMAGE_VERIFY: ok`. The probe was run read-only before merge and exits 1 (FAIL), as expected.

---

# Incident Post-Mortem Analysis

## Root Cause(s) — 5-Whys

1. **Why did verification not run?** The cosign verifier container never started: its image pull was DENIED.
2. **Why was a public image's pull denied?** The docker CLI presented the deploy config's inline `ghcr.io` credential, and GHCR rejects a revoked credential rather than falling back to anonymous.
3. **Why was a revoked credential still presented?** #7071 retired GHCR as a host *pull fallback* for our private images, but the same config entry also served the verifier-image pull, a second consumer that was not inventoried.
4. **Why did no one notice for six weeks?** WARN mode runs the image anyway, and `cosign_absent` was classified as a telemetry event, not an alert. Nothing distinguished "the signature is bad" from "the verifier never ran".
5. **Why was there no per-host check that verification actually succeeds?** Verification was asserted structurally (the call exists, the flags are right) and never graded from live evidence. The #8037 probe is that grader.

## Versions of Components

- **Version(s) that triggered the outage:** every web-platform release deployed after the PAT revocation (by 2026-07-29) up to PR #8456's apply.
- **Version(s) that restored the service:** PR #8456 via the `deploy_pipeline_fix` auto-apply (pending the #8037 grade).

## Impact details

### Services Impacted

Deploy-time image signature verification on the web-platform hosts. Serving was not affected.

### Customer Impact (by role)

Per learning `2026-05-06-user-impact-section-by-role-not-surface.md` — enumerate by USER ROLE, not by surface. This is the canonical "Customer Impact"; do NOT add a second free-text Customer Impact block.

- Prospect: none observed.
- Authenticated app user: none observed. They were exposed to a *latent* integrity gap: an image substituted in the registry would not have been caught by signature at deploy time. Images were still pulled by `@sha256` digest from the private-network zot registry.
- Legal-document signer: none.
- Admin via Access: none.
- Billing customer: none.
- OAuth installation owner: none.

### Revenue Impact

None.

### Team Impact

Two issues (#8036, #8037) and roughly 180 journald lines per week of noise from one root cause.

## Lessons Learned

### Where we got lucky

Digest pinning plus a private-network registry held the integrity line while signature verification was absent.

### What went well

The #8036 diagnosis measured the credential directly, and re-probed on the day of the fix, instead of inferring from the log pattern.

### What went wrong

Retiring a credential inventoried its purpose (host pull fallback), not its consumers. A security control failing open in WARN mode produced a per-deploy event nobody graded.

## Action Items & Follow-ups

Every action item and follow-up so this incident cannot recur (save logs, add tests, set up alerts, automation, documentation, code sweeps, PRs).

| Issue | Action | Status |
|---|---|---|
| #8037 | Grade per-host `IMAGE_VERIFY: ok` after the apply with the `cosign-verify-live-8037.sh` follow-through; close only on its PASS | open |
| #8036 | Operator ruling on 1c: retire the host-side GHCR read path (the dead credential's remaining consumers) | open |
