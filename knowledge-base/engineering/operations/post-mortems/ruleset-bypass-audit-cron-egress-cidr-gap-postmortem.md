---
title: "scheduled-ruleset-bypass-audit cron missed check-in — incomplete GitHub egress CIDR coverage"
date: 2026-06-14
incident_pr: "feat-one-shot-scheduled-ruleset-bypass-audit-cron"
incident_window: "2026-06-14 06:13 UTC (missed fire) → recovery pending post-apply"
recovery_at: "pending — next daily fire (06:13 UTC) or manual /soleur:trigger-cron after firewall re-applies"
suspected_change: "clone-fix #5244 (2026-06-12) populated cron-egress-allowlist-cidr.txt with only the 4 big GitHub git/pages blocks; the Azure /32 gap was latent until DNS returned an uncovered IP on 06-14"
brand_survival_threshold: single-user incident
status: unresolved but ended
triggers:
  - availability (security tripwire dark)
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "n/a — availability/monitoring outage, no personal-data exposure"
---

## Actor key

- `agent` — Claude Code did this autonomously (no operator ack required).
- `agent-with-ack` — Claude Code did this AFTER operator confirmed via menu option per `hr-menu-option-ack-not-prod-write-auth`.
- `human` — Operator did this directly.

# Incident Overview

The `scheduled-ruleset-bypass-audit` Inngest cron (daily `13 6 * * *` UTC) — the tripwire
that detects unauthorized widening of `bypass_actors` on the `CI Required` ruleset — missed
its Sentry Crons check-in (monitor `5ccb1e67-fb90-4863-97d3-f8fd23287b37`, incident
`5516336`). The control went dark for one audit window. No personal data was exposed; this
is an availability/monitoring outage of a security control.

## Status

unresolved but ended — the missed window has passed; the fix (full GitHub `/meta` CIDR
coverage) is shipping in the source PR. The cron recovers on the next daily fire after the
firewall re-applies on merge (or sooner via a manual `/soleur:trigger-cron`).

## Symptom

A "missed check-in" alert (not a `?status=error` failed check-in). The cron is all-
`api.github.com`; the Sentry heartbeat is the LAST step, gated on the GitHub calls. A blocked
GitHub call yields NO heartbeat at all → a *missed* check-in — the firewall-drop signature.

## Incident Timeline

- **Start time (detected):** 2026-06-14 ~06:43 UTC (08:43 CEST, just past the 30-min margin)
- **End time (recovered):** pending (post-apply)
- **Duration (MTTR):** ~ (fix shipped same day; recovery pending firewall re-apply)

| Actor | Time (UTC) | Action |
|---|---|---|
| system | 2026-06-13 06:13 | Last good check-in (DNS returned a covered 140.82.x IP). |
| system | 2026-06-14 06:13 | Daily fire landed on an uncovered Azure 20.x/4.x IP → default-dropped → no heartbeat. |
| system | 2026-06-14 ~06:43 | Sentry monitor flagged the missed check-in (incident 5516336). |
| human | 2026-06-14 08:43 (CEST) | Operator received the Sentry alert; routed to /soleur:go → one-shot. |
| agent | 2026-06-14 | Root-caused (file = 4 ranges; live /meta = 52), extended the CIDR file, shipped the fix. |

## Participants and Systems Involved

Inngest cron `cron-ruleset-bypass-audit`; the container egress firewall (`cron-egress-firewall`,
nft `soleur_egress_allow_cidr` interval set); GitHub `api.github.com` / `/meta`; Sentry Crons.

## Detection (+ MTTD)

- **How detected:** Sentry Crons monitor miss (margin 30m, threshold 1) — automated.
- **MTTD:** ~30 min (the monitor's miss margin).

## Triggered by

system — GitHub DNS round-robin returned an uncovered LB IP for a host whose full IP pool was
not in the CIDR allowlist.

## Root-cause hypothesis (triage)

| Hypothesis | Supporting evidence | Disconfirming evidence | Status |
|---|---|---|---|
| Incomplete egress CIDR coverage for api.github.com's LB pool | committed file = 4 ranges; live `/meta` `.git`+`.api` = 52; 48 Azure /32s uncovered; missed (not failed) check-in | none | CONFIRMED |
| Auth/JWT/rate-limit (Octokit) | — | a transient auth error → `?status=error` (failed), not a *missed* check-in; #5258 already widened retry | RULED OUT |
| DNS-resolution failure | — | would manifest as `egress-dns-exfil` drops, not the missed-heartbeat signature | RULED OUT |

## Resolution

Extended `apps/web-platform/infra/cron-egress-allowlist-cidr.txt` to the COMPLETE GitHub
`/meta` `.git`+`.api` IPv4 union (52 ranges, snapshot 2026-06-14, generated mechanically).
Added Azure-range presence asserts + an exact-count guard (=52) to the firewall drift-guard,
and a delimiter-anchored `(20|4).` post-apply assert to `server.tf`. Re-applies on merge via
`apply-web-platform-infra.yml`; the post-apply container probe proves enforcement.

## Recovery verification

TBD post-apply — confirm a fresh `?status=ok` check-in on the Sentry monitor after the
firewall re-applies (manual `/soleur:trigger-cron cron/ruleset-bypass-audit.manual-trigger`
or the next 06:13 UTC fire), and that incident 5516336 transitions to recovered
(recovery_threshold=1).

---

# Incident Post-Mortem Analysis

## Root Cause(s) — 5-Whys

1. **Why did the cron miss its check-in?** The GitHub API call was dropped by the egress firewall, so the heartbeat (gated on it) never ran.
2. **Why was the call dropped?** `api.github.com` resolved to an Azure `20.x`/`4.x` IP not in the `soleur_egress_allow_cidr` interval set.
3. **Why was that IP not in the set?** The CIDR allowlist carried only the 4 big GitHub git/pages blocks, not the ~48 Azure `/32`s in the `/meta` `.git`+`.api` union.
4. **Why only the 4 big blocks?** Clone-fix #5244 populated the file from the git-clone ranges (`github.com`'s big blocks) and did not include the full `api.github.com` LB pool.
5. **Why did it pass for a day first?** `api.github.com` round-robins DNS; 06-13 happened to return a covered `140.82.x` IP (green), 06-14 returned an uncovered range (red) — a latent partial-coverage gap that surfaces intermittently.

## Versions of Components

- **Version(s) that triggered the outage:** firewall CIDR file at #5244 state (4 ranges).
- **Version(s) that restored the service:** this PR (52 ranges, full `/meta` union).

## Impact details

### Services Impacted

The `scheduled-ruleset-bypass-audit` security control (one missed audit window). No user-
facing service was impacted; the prod app (`soleur.ai`) served normally.

### Customer Impact (by role)

- Prospect: none.
- Authenticated app user: none (the cron is an internal CI-ruleset audit; no user surface).
- Legal-document signer: none.
- Admin via Access: indirect — the bypass-actor drift tripwire was dark for one window, so an unauthorized ruleset bypass during that window would have gone undetected.
- Billing customer: none.
- OAuth installation owner: none.

### Revenue Impact

None.

### Team Impact

One Sentry alert → one autonomous one-shot dispatch (this session). No human firefighting.

## Lessons Learned

### Where we got lucky

The DNS round-robin meant the gap surfaced as a clean, alerting *missed* check-in within a
day rather than staying silently green on a permanently-covered IP. The Sentry monitor's
miss-margin caught it within 30 min.

### What went well

The missed-vs-failed check-in distinction immediately localized the cause to the firewall
layer (L3), not auth (L7). The fix followed the exact #5244 precedent (static CIDR set,
file-provisioned, auto-apply on merge).

### What went wrong

A partial-coverage CIDR list for an LB host is an intermittent foot-gun: it passes on most
fires and fails only when DNS returns an uncovered IP — invisible to a one-time "it resolves
to a covered IP" check. Coverage must be verified by set-difference against `/meta`.

## Action Items & Follow-ups

| Issue | Action | Status |
|---|---|---|
| #5284 | Self-refreshing GitHub `/meta` CIDR generator (replace the static snapshot so a future `/meta` rotation cannot re-open this gap) | **closed** — generator `apps/web-platform/infra/scripts/gen-github-egress-cidr.sh` + `cron-github-cidr-refresh` Inngest cron (daily; direct-merge PR on drift → existing apply path re-provisions the firewall) + de-magicked structural drift-guard. The earlier resolve-timer / pre-plan-regen hooks were rejected (availability hot-path / uncommitted state drift); the Inngest cron + `safeCommitAndPr` lane was chosen so the refresh fires unattended from merge. |
