---
title: "web-platform deploy pipeline frozen — GHCR image_pull_failed (auth_denied) recovers only on login-failure, not pull-denial"
date: 2026-07-14
incident_pr: 6408
incident_window: "2026-07-13 ~12:32 UTC → 2026-07-14 (deploy leg RED; prod frozen on 0.213.2)"
recovery_at: "2026-07-14 (prod advanced to 0.213.6; structural fix in PR #6408)"
suspected_change: "GHCR read credential login-ok/pull-deny capability split — §1A (#6395) recovers only on docker login failure, not on docker pull auth-denial"
brand_survival_threshold: aggregate pattern
status: resolved
triggers:
  - deploy-pipeline availability (web-platform-release deploy job RED)
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "n/a"
---

## Actor key

- `agent` — Claude Code did this autonomously (no operator ack required).
- `agent-with-ack` — Claude Code did this AFTER operator confirmed via menu option.
- `human` — Operator did this directly.

# Incident Overview

The `web-platform-release` deploy job failed at the `deploy` step with
`ci-deploy.sh exited 1 (reason=image_pull_failed)` / Sentry `WEB-PLATFORM-59`
`image pull failed (auth_denied)`. Prod (web-1) was frozen on the last green
build (`0.213.2`, 12:32 on 2026-07-13) while every subsequent merge failed the
same way — a **deploy outage**: the running service stayed up (200 on
`/health`) but no new code (feature, fix, or security patch) could reach the one
prod host serving all users for ~10+ hours.

PR #6395's §1A re-fetched the GHCR credential from Doppler and retried
`docker login` on a login **FAILURE**. It was applied to the host but the
redeploy still `auth_denied` — **necessary-but-insufficient**: the production
denial fires one step later, at `docker pull`, which had no recovery.

## Status

resolved — the acute outage self-resolved (a later deploy reached prod:
`app.soleur.ai/health` advanced to `0.213.6`); the durable structural fix ships
in PR #6408 so the class cannot recur.

## Symptom

`web-platform-release` deploy job RED since ~20:05 on 2026-07-13; Sentry
`op:image-pull pull_result:auth_denied` recurring (8 events across the window,
the most recent 2026-07-14 12:47 on the `v0.213.6` tag). The GHCR credential
pulled the denied tags off-host to HTTP 200 — the failure was host-side, at the
pull.

## Incident Timeline

| Actor | Time (UTC) | Action |
|---|---|---|
| system | 2026-07-13 ~12:32 | Last green deploy (`0.213.2`); prod frozen thereafter. |
| system | 2026-07-13 20:05–23:17 | `web-platform-release` deploy job RED on repeated merges; Sentry `auth_denied` recurs. |
| human | 2026-07-13 | §1A (#6395) applied to host; post-apply redeploy still `auth_denied`. |
| human | 2026-07-14 | Incident filed as #6400 with self-pulled evidence (Sentry + off-host pull proof). |
| agent | 2026-07-14 | Prod observed at `0.213.6` (acute outage self-resolved via a later deploy). |
| agent | 2026-07-14 | Structural pull-site recovery fix authored + shipped (PR #6408). |

## Detection (+ MTTD)

- **How detected:** monitoring — Sentry `WEB-PLATFORM-59` (`image pull failed (auth_denied)`, error) + `web-platform-release` deploy-job RED. No SSH needed; evidence self-pulled from Sentry API + off-host `docker pull` proof.
- **MTTD:** ~hours (the deploy-job RED and Sentry recurrence were visible from the first failed merge).

## Triggered by

system — a GHCR read credential that authenticates `docker login` but cannot
`docker pull` private packages (login-ok/pull-deny capability split), against a
recovery path that only fired on a login failure.

## Root-cause hypothesis (triage)

| Hypothesis | Supporting evidence | Disconfirming evidence | Status |
|---|---|---|---|
| `DOPPLER_TOKEN` absent in deploy exec context → §1A skipped (issue #6400 primary hypothesis) | plausible from §1A guard shape | `cloud-init.yml:408` writes `DOPPLER_TOKEN` prd-scoped into `/etc/default/webhook-deploy`; `webhook.service` sources it | **disproved** |
| baked/refetched cred is an App token (can't pull GHCR) vs a PAT (class mismatch) | ADR-088 App-token-can't-pull fact | `prd_terraform.GHCR_READ_TOKEN == prd.GHCR_READ_TOKEN` (same pull-capable PAT, verified this session) | partly — real gap is not class mismatch |
| §1A recovers on login-failure but the denial fires at `docker pull` (login-ok/pull-deny bypasses §1A) | code trace: `ghcr_prelude_and_login` gates on `docker login`; `pull_image_with_fallback` had no re-fetch/relogin/retry | — | **confirmed (root cause)** |

## Resolution

Move credential recovery to the site where pull capability is actually proven —
the pull itself. On a GHCR `docker pull` classified `auth_denied`, re-fetch the
current `prd` credential, `docker login` again, and retry the pull **once**
before aborting (`_ghcr_pull_or_recover` in `ci-deploy.sh`). Fail-open: a
recovery miss leaves the unchanged `image_pull_failed` terminal state. Delivered
via the existing `apply-deploy-pipeline-fix.yml` auto-apply (HTTPS
`/hooks/infra-config`, no SSH); the next release deploy self-recovers.

## Recovery verification

- Acute: `curl -s https://app.soleur.ai/health | jq .version` → `0.213.6` (past the frozen `0.213.2`).
- Structural: `ci-deploy.test.sh` 137/137 (7 new #6400 cases incl. login-ok/pull-deny→recovered, fail-open, relogin-fail→no-retry).
- Soak (post-deploy): `scripts/followthroughs/deploy-ghcr-pull-recovery-6400.sh` — zero `op:image-pull auth_denied` error events over 3 days (enrolled on #6400).

## Root Cause(s) — 5-Whys

1. Why did the deploy fail? `docker pull` of the private GHCR image returned `denied` (auth).
2. Why did the credential deny the pull? It could `docker login` but not `docker pull` (a login-ok/pull-deny capability split — a GitHub App installation token, or a stale baked snapshot).
3. Why didn't §1A recover it? §1A's recovery is gated on the `docker login` outcome; a cred that logs in successfully skips §1A entirely.
4. Why is login-gated recovery insufficient? `docker login` success is not proof of `docker pull` capability — only a pull attempt is.
5. Why was the fix at the wrong layer? §1A (#6395) targeted the observed *login* symptom of the earlier web-2 boot incident; the production deploy denial surfaces one step later at the pull, which had no recovery.

## Versions of Components

- **Version(s) that triggered the outage:** prod frozen on `0.213.2`; deploy attempts `0.213.3`–`0.213.5` RED.
- **Version(s) that restored the service:** `0.213.6` (acute); PR #6408 (structural).

## Impact details

### Services Impacted

web-platform deploy pipeline (new code could not reach prod). The running
service stayed available (200 `/health`) — no request-path outage.

### Customer Impact (by role)

- Prospect: none (marketing site unaffected).
- Authenticated app user: no direct outage; indirect — no feature/fix/security patch could ship for ~10+ hours (frozen build).
- Legal-document signer: none.
- Admin via Access: none.
- Billing customer: none.
- OAuth installation owner: none.

### Revenue Impact

None directly; deferred delivery of any pending fixes.

### Team Impact

Deploy pipeline blocked for the operator; ~2 fix attempts (§1A necessary-but-insufficient) before the structural cause was isolated.

## Lessons Learned

### Where we got lucky

The running prod service never went down — this was a *deploy-freeze*, not a
request-path outage. A concurrent request-path bug during the freeze would have
been unpatchable.

### What went well

Self-pulled observability (Sentry API + off-host pull proof) isolated the
host-side auth failure with no SSH; #6396's `host_id` tag + Vector log-shipping
had just landed to close the attribution blind spot.

### What went wrong

The prior PIR (`2026-07-13-web-2-fsn1-warm-standby-auth-denied-postmortem.md`)
framed this class as "resolved / no user impact (weight-0 web-2)". That framing
was wrong: the failing deploy leg fails the whole fan-out and prod (web-1) was
frozen. §1A fixed the login symptom, not the pull-site root cause.

## Action Items & Follow-ups

| Issue | Action | Status |
|---|---|---|
| #6400 | Structural pull-site GHCR recovery fix (`_ghcr_pull_or_recover`) + ADR-096 login≠pull recovery contract + 3-day soak follow-through (PR #6408) | open |
| #6410 | Boot-path GHCR seed-pull denial parity mirroring `ci-deploy.sh` (recreate-only; may be mooted by zot/ADR-096) | open |
