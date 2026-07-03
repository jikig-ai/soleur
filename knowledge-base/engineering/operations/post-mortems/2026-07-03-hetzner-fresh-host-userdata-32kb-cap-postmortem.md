---
title: "Hetzner fresh web-host provisioning blocked — cloud-init user_data over the 32KB cap"
date: 2026-07-03
incident_pr: 5922
incident_window: "latent — never manifested in production (fresh-host provision gated behind operator cutover #5887)"
recovery_at: "2026-07-03 (fix merged; guard added)"
suspected_change: "Cumulative growth of inlined host bootstrap scripts + hooks.json in server.tf user_data, most recently #5918 (multi-host GA cutover)"
brand_survival_threshold: aggregate pattern
status: resolved
triggers:
  - availability (fresh/replacement web-host provisioning)
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "n/a"
# Classification rationale: availability-only latent defect on backend provisioning
# infra. No personal-data breach, no confidentiality/integrity loss — GDPR Art. 33/34
# do not apply (n/a). git-data host (holds user git data) was untouched by the defect.
---

## Actor key

- `agent` — Claude Code did this autonomously (no operator ack required).
- `agent-with-ack` — Claude Code did this AFTER operator confirmed via menu option.
- `human` — Operator did this directly.

# Incident Overview

A fresh (or replacement/HA-recovery) Hetzner **web** host could not be provisioned:
`apps/web-platform/infra/server.tf` rendered 22 bootstrap scripts + `hooks.json` as
base64 into cloud-init `user_data` at ~282 KB — ~8.6× over Hetzner's hard 32,768-byte
`user_data` cap. Any fresh-host provision would have failed at cloud-init. The defect
was **latent**: it never affected production because running `web-1` carries
`ignore_changes=[user_data]` and no fresh-host provision had been attempted (that is
gated behind the not-yet-executed operator cutover #5887). It was caught proactively by
measurement while sizing the multi-host cutover, not by a user-facing outage.

## Status

resolved — fixed in PR #5922 with a regression guard; no production recovery was needed
(steady state was never degraded).

## Symptom

Terraform-rendered web `user_data` = ~282 KB vs the 32,768-byte Hetzner cap. A fresh
`hcloud_server.web` apply would reject or truncate cloud-init, leaving the host unable to
bootstrap → the app container never comes up → absent service for any traffic routed to
that host (only during a scale-out or failover event).

## Incident Timeline

- **Start time (detected):** 2026-07-02 (during #5921 sizing analysis)
- **End time (recovered):** 2026-07-03 (fix merged)
- **Duration (MTTR):** n/a — latent defect, no live outage window

| Actor | Time (UTC) | Action |
|---|---|---|
| agent | 2026-07-02 | Measured rendered web `user_data` = ~282 KB (and gzip+base64 = ~141 KB, still 4.3× over) — cap breach identified during multi-host sizing. |
| agent | 2026-07-02 | Root cause traced to cumulative inlining of host scripts + `hooks.json` in server.tf user_data. |
| agent | 2026-07-03 | Bake-and-extract fix implemented (#5922); guard `cloud-init-user-data-size.test.ts` added. |
| agent | 2026-07-03 | Discovered git-data host ALSO over cap (~41.7 KB) → filed #5927. |

## Detection (+ MTTD)

- **How detected:** proactive measurement during sizing analysis (`terraform`/byte count),
  not a monitoring alert or user report. There was no production signal because the defect
  cannot fire until a fresh-host provision is attempted.
- **MTTD:** n/a (no live incident).

## Triggered by

system — cumulative infra growth (each added host-bootstrap script enlarged `user_data`);
most recent contributor #5918.

## Root-cause hypothesis (triage)

| Hypothesis | Supporting evidence | Disconfirming evidence | Status |
|---|---|---|---|
| Inlined scripts + hooks.json exceed Hetzner user_data cap | measured 282 KB vs 32,768 B cap | — | confirmed |
| gzip compression would suffice | issue option 1 | measured gzip+base64 = 141 KB, still 4.3× over | rejected |

## Resolution

Bake-and-extract (extends ADR-080): bake the 22 scripts + `hooks.json.tmpl` +
`journald-soleur.conf` + a new `soleur-host-bootstrap.sh` into the app image at
`/opt/soleur/host-scripts/`; cloud-init's minimal launcher pulls the image, `docker cp`s
the baked set, verifies a Terraform-computed combined content-hash, then runs the baked
installer which writes the fail-closed `/run/soleur-hostscripts.ok` sentinel the terminal
`docker run` gates on (`poweroff -f` on absence). Web `user_data`: ~282 KB → ~29,290 B
(~3.1 KB under cap).

## Recovery verification

`bun test plugins/soleur/test/cloud-init-user-data-size.test.ts` — 21 pass (web < 30,500 B
strict + structural extraction contract + Dockerfile↔server.tf baked-set parity; also pins
git-data host at a no-further-growth ceiling). Live fresh-host verification **completed
2026-07-03** (#5942, closed): fresh `soleur-web-2` provisioned through the bake-and-extract
path (created 07:13:22Z, 61s after #5922 merged) and healthy ~9h later — confirmed via
self-pulled signals (no SSH): (1) host `running` not powered off ⇒ fail-closed
`/run/soleur-hostscripts.ok` sentinel written; (2) **zero** `stage=extract|verify|install`
(+5 other stages) Sentry bootstrap-trap events in 24h. Dedicated per-host Better Stack
uptime alarm for future boots deferred to #5933.

---

# Incident Post-Mortem Analysis

## Root Cause(s) — 5-Whys

1. **Why** couldn't a fresh web host provision? cloud-init `user_data` exceeded Hetzner's 32 KB cap.
2. **Why** was it over cap? 22 bootstrap scripts + a 10.7 KB `hooks.json` were base64-inlined into `user_data`.
3. **Why** were they inlined? The original single-host design inlined everything; it was under cap at the time.
4. **Why** did it silently grow past cap? Each new host-bootstrap script added bytes with no size guard on the rendered `user_data`.
5. **Why** no size guard? The cap was an implicit provider constraint never encoded as a test — nothing failed loudly until a fresh provision was sized.

Root cause: **an implicit provider size cap with no regression guard**, allowing cumulative inlining to silently approach and exceed it.

## Versions of Components

- **Version(s) that triggered:** server.tf user_data as of #5918 (post multi-host GA cutover).
- **Version(s) that restored:** PR #5922 (bake-and-extract + size guard).

## Impact details

### Services Impacted

Fresh/replacement Hetzner **web** host provisioning only. No steady-state impact (web-1
unaffected via `ignore_changes=[user_data]`). git-data host untouched.

### Customer Impact (by role)

- Prospect: none (steady state unaffected).
- Authenticated app user: none in steady state; would see degraded/absent service ONLY if routed to a fresh host during a scale-out/failover before the fix.
- Legal-document signer: none.
- Admin via Access: none.
- Billing customer: none.
- OAuth installation owner: none.

### Revenue Impact

None — no live outage occurred.

### Team Impact

Blocked the multi-host cutover path until fixed; ~1 session of engineering to design and guard.

## Lessons Learned

### Where we got lucky

The cap breach was caught by proactive sizing during the multi-host cutover work, BEFORE
a real fresh-host provision was attempted in production. Had the operator cutover (#5887)
run first, the failover/scale event would have produced a real outage.

### What went well

Bake-and-extract reused an existing idiom (ADR-080), added integrity (content-hash) and a
fail-closed sentinel, and shipped with a strict byte-cap regression guard in the same PR.

### What we can do better

Encode implicit provider limits (size caps, quotas) as loud regression guards the moment
they are discovered — the guard added here (`cloud-init-user-data-size.test.ts`) is now the
pattern for the git-data host too (#5927).

## Action Items & Follow-ups

Every action item and follow-up so this incident cannot recur.

| Issue | Action | Status |
|---|---|---|
| #5927 | git-data host cloud-init `user_data` is ALSO over cap (~41.7 KB, no-docker host so bake-and-extract N/A) — resolve before ADR-068 Phase 2; size guard pins it at a no-further-growth ceiling in the meantime. | open |
| #5887 | `apply-web-platform-infra.yml` red since #5877 (moved resources excluded by `-target` allow-list) — this blocked infra-apply pipeline gated any fresh-host provision reaching prod, so it had to go green before this fix was exercised live. | **closed 2026-07-03** (unblocked via #5950 deferring the web-1 placement reboot with `ignore_changes`; infra-apply green). |
| #5942 | Live fresh-host recovery-verification (extraction + content-hash + sentinel end-to-end on a real host). | **closed 2026-07-03** — verified on fresh `soleur-web-2` (running + zero Sentry stage-trap events). |
| #5933 | Dedicated per-host Better Stack "provision-armed uptime absence" monitor (ADR-082 Item 1) — the PRIMARY fresh-boot alarm; not yet wired, so #5942 relied on the fail-closed running-state proxy + Sentry absence instead. | open |
