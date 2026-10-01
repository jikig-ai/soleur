---
title: "soleur-ai runtime App private key reachable from any branch through Doppler soleur/prd (exposure, #8609)"
date: 2026-09-30
incident_pr: 9263
incident_window: "≥2026-05-29 (the runtime key row was added and held in soleur/prd) → open until #8609 R-steps R6/R7 remove the key from prd and delete it at GitHub"
recovery_at: "pending — #8609 R-step 7 (old key returns 401) and PR-B"
suspected_change: "The runtime App key was stored in the root Doppler config `soleur/prd`, which every `prd`/`prd_*` branch-config repository-secret token can read from a workflow on any branch of the public repository."
brand_survival_threshold: single-user incident
status: ongoing
triggers:
  - credential-placement (a write-capable App key in a config readable from any branch)
  - branch-config-inheritance (a Doppler branch config inherits every secret of its root)
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "n/a — CLO determination (knowledge-base/legal/audits/2026-09-30-8609-runtime-app-key-exposure-assessment.md): REACHABILITY-ONLY, no Art. 33/34 or DPD §7.2 duty on the facts established to date; PROVISIONAL, and re-opens with a fresh 72h from awareness of any evidence of use"
---

## Actor key

- `agent` — Claude Code did this autonomously (no operator ack required).
- `agent-with-ack` — Claude Code did this AFTER operator confirmed via menu option per `hr-menu-option-ack-not-prod-write-auth`.
- `human` — Operator did this directly.

# Incident Overview

The soleur-ai GitHub App's runtime private key sat in Doppler `soleur/prd`. Every repository-secret
Doppler token that resolves `prd` or a `prd_*` branch config could read it, from a workflow on any
branch of the public repository. The App holds `administration`, `contents`, `secrets`, `actions`
and `pull_requests` write on three installations, two of them outside `jikig-ai`. This is a
security exposure, not an outage: no service degraded, and no evidence of use has been gathered.

## Status

ongoing — the key is still in `soleur/prd` until the post-merge R-steps of #8609 move it.

## Symptom

None observable. Every read of the key is a legitimate read by a legitimate holder, so no monitor
could surface it. It was found by measurement.

## Incident Timeline

- **Start time (detected):** 2026-09-22 (the #8209 measurement session)
- **End time (recovered):** pending (#8609 R-step 7)
- **Duration (MTTR):** open

| Actor | Time (UTC) | Action |
|---|---|---|
| human | 2026-05-29 | The runtime key row (`SHA256:grkwzCZX…`) was added to the App and stored in `soleur/prd` (K0 inventory). |
| agent | 2026-09-22 | #8209 measurements establish that `prd_terraform` is a branch config of `prd`; the runtime key's reachability is recorded as ADR-241 residual R1. |
| agent | 2026-09-23T13:27:39Z | #8609 filed. |
| agent-with-ack | 2026-09-30 | PR #9263 (PR-A) opened: isolated project, token delivery, host overlay, runbook and closure gates. |

## Participants and Systems Involved

Doppler (`soleur/prd` and its branch configs), GitHub Actions repository secrets, the soleur-ai
GitHub App, the web hosts' deploy channel.

## Detection (+ MTTD)

- **How detected:** manual measurement during the #8209 credential-tier work, not monitoring.
- **MTTD (mean time to detect):** at least 116 days (2026-05-29 → 2026-09-22); the true start may be earlier.

## Triggered by

system — a credential placed in a config whose read set was wider than its holder.

## Root-cause hypothesis (triage)

| Hypothesis | Supporting evidence | Disconfirming evidence | Status |
|---|---|---|---|
| The key was placed where the runtime could read it, without accounting for who else can read that config | Branch configs inherit the root; five repository secrets resolve `prd` or a `prd_*` config | none | confirmed |

## Resolution

Not yet resolved. PR #9263 ships the mechanism (isolated `soleur-github-app` project, Tier-B read
token, main-signed-image overlay). The key moves in runbook R-steps R0–R9; PR-B then makes
isolation mandatory.

## Recovery verification

Pending. The closing proof is runbook R-step 7: the new key returns `200` from `GET /app`, the
retired key returns `401`, and every `prd`/`prd_*` config returns not-found for the key.

---

# Incident Post-Mortem Analysis

## Root Cause(s) — 5-Whys

1. Why could any branch read the key? It lived in `soleur/prd`, readable through several repository-secret tokens.
2. Why did those tokens reach it? A Doppler branch config inherits every secret of its root, so `prd_*` tokens read `prd`.
3. Why was the key in `prd`? The web app reads its runtime secrets from `prd`, and the key was placed with them.
4. Why was the read set not checked? Credential placement was judged by the consumer, not by the full set of readers.
5. Why did nothing flag it? Every read is legitimate, so no read-based monitor can detect the exposure; only a census of readers can.

## Versions of Components

- **Version(s) that triggered the outage:** n/a (no outage; exposure since the key was stored in `prd`)
- **Version(s) that restored the service:** n/a

## Impact details

### Services Impacted

None degraded. Potentially exposed: installation-token minting for all three soleur-ai installations.

### Customer Impact (by role)

- Prospect: none.
- Authenticated app user: none observed; repository content of connected users was reachable through a holder of the key.
- Legal-document signer: none.
- Admin via Access: none.
- Billing customer: none.
- OAuth installation owner: the two third-party installations were reachable (reachability-only; see DC-1 on a courtesy notice).

### Revenue Impact

None.

### Team Impact

One planning and implementation cycle (#8609 PR-A), plus the post-merge R-step sequence.

## Lessons Learned

### Where we got lucky

The reachable class is small, named, and not the public (CLO assessment, §The reachable class, stated precisely).

### What went well

The #8209 census found the exposure by measurement, and the CLO assessment recorded the evidence deadlines (K0 before any key delete, K1 before the 90-day Actions retention horizon).

### What went wrong

The custody of a key delivered to a host is bounded by every channel that can change that host. Review found the deploy channel and Tier-A `prd` writers still branch-reachable, so closing #8609 now waits on two more gates. See `knowledge-base/project/learnings/security-issues/2026-09-30-isolating-a-secret-onto-a-host-is-bounded-by-every-channel-that-can-change-the-host.md`.

## Action Items & Follow-ups

| Issue | Action | Status |
|---|---|---|
| #8609 | Run R-steps R0–R9 (move the key, retire and delete the old one), then PR-B to make isolation mandatory | open |
| #9294 | Closure gate G1: move the deploy channel secrets out of branch reach, then rotate | open |
| #9295 | Closure gate G2: no branch-nameable token may write `soleur/prd` | open |
| #9277 | Move the App's webhook and client secrets into `soleur-github-app` | open |
| #9278 | Drop metadata-endpoint traffic from forwarded Docker containers on web hosts | open |
