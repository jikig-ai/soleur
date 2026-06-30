---
title: "Claude-eval cron cohort outage — egress firewall over-blocked LB-rotated IPs"
date: 2026-06-16
incident_pr: 5413
incident_window: "~2026-06-08 to 2026-06-16 (per-cron; community-monitor down since 06-12, follow-through since ~06-08, bug-fixer since 06-14)"
recovery_at: "2026-06-29 (#5413 LB-rotation class verified recovered; residual egress-blocked volume is a separate class — see ## Status. NOT a #5413 regression.)"
suspected_change: "ADR-052 container egress firewall rollout (~06-08 to 06-14) — default-drop allowlist with a single-A-record resolver"
brand_survival_threshold: single-user incident
status: resolved
triggers:
  - "Sentry cron monitors: 6 heavy eval crons showing missed (not failed) check-ins"
  - "Sentry issue egress-blocked: container egress denied (654 hits, ongoing)"
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "n/a"
---

## Actor key

- `agent` — Claude Code did this autonomously.
- `human` — Operator did this directly.

# Incident Overview

The heavy "Claude-eval" cron cohort — `cron-community-monitor`,
`cron-content-generator`, `cron-follow-through`, `cron-bug-fixer`,
`cron-roadmap-review`, `cron-agent-native-audit` — silently stopped completing
for several days. Each cron boots a container, clones the repo, and calls
external services (GitHub, Anthropic, HN/Algolia, Discord/X/LinkedIn) over a
long critical path. The ADR-052 container egress firewall default-drops any
egress not in the `soleur_egress_allow` nftables set, which
`cron-egress-resolve.sh` rebuilt every minute from a **single-A-record snapshot**
of each allowlisted host. LB-fronted hosts (Cloudflare / AWS / Google) round-robin
across large IP pools, so a connect to a freshly-rotated IP before the next tick
was default-dropped — the non-GitHub analogue of incident 5516336 (the
api.github.com `/meta` CIDR gap). The crons never reached their final Sentry
heartbeat, producing **missed** (not failed) check-ins — the firewall-drop
fingerprint.

## Status

`resolved` — the fix (#5413) is implemented, merged, and verified: over a live
100-event sample of the `egress-blocked` issue (2026-06-27→06-29) **none** of the
allowlisted-host LB-rotation IPs that characterised this incident (Cloudflare
`104.18.x` linkedin/x/discord/resend, AWS `198.x`/`64.239.x` bsky/buttondown/
flagsmith, Google-LB hn.algolia) appear in the blocked DST set. The grace-window
retention accumulated each host's rotation pool as designed. The lightweight
pure-TS crons were never affected (sub-second single-call probes rarely hit a
rotated IP).

### Residual egress-blocked volume (post-#5413, characterised 2026-06-29 — #5676)

The issue keeps firing, but the residual is a **different class** from the one
#5413 fixed (which was LB-rotation on *already-allowlisted* hosts). The single
`op=egress_blocked` Sentry issue groups ALL blocked destinations (no DST grouping
in the emitter), so it conflated two unrelated phenomena. Live DST breakdown:

| Blocked DST | Host (DoH both resolvers + TLS-SNI) | Class |
|---|---|---|
| `104.16.x.34` (dominant) | `registry.npmjs.org` (Cloudflare anycast) | **Intended-by-design** — bare `npx` registry-metadata probe the firewall correctly drops; `@playwright/mcp` resolves to the image-baked dep (#5199). NOT an allowlist gap. Silenced at source in #5676 (`npm_config_prefer_offline`). |
| `34.149.66.137` | GCP global-LB (Datadog `us5` default vhost) — NOT the app's Sentry | **Resolved in #5691** — dialer is CC non-essential traffic / context7 backend (default-cert, host unproven). App's own Sentry ingest (`SENTRY_INGEST_DOMAIN` → `34.160.81.0`) is **never** in the blocked set, so there is no blackholed-observability hole. Silenced at source via `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1` (+ `--strict-mcp-config`); kept blocked, not allowlisted. |
| `64.239.123.129` / `104.18.25.159` / `198.x` | `mcp.vercel.com` / `mcp.cloudflare.com` / `mcp.stripe.com` | **Resolved in #5691** — dialer is the substrate's `--plugin-dir plugins/soleur` auto-connecting `plugin.json`'s four remote MCP servers at startup (tools hook-denied → non-essential). Silenced at source via `--strict-mcp-config`; kept blocked, not allowlisted. |

Neither residual class is a #5413 regression. The dominant noise is the intended
npm probe; the rest are low-volume un-enumerated hosts whose correct posture is
**blocked** pending per-host evidence (follow-up issue).

**Attribution is exact-IP-verified, NOT default-cert-inferred (the load-bearing
evidence for `resolved`).** Several residual IPs sit on LB ranges shared with
allowlisted #5413 hosts, so IP→host was disambiguated by resolving each allowlisted
host (DoH, both `8.8.8.8` + `1.1.1.1`) and confirming **none** rotates through any
residual blocked IP: `api.stripe.com` → `198.{137.150,202.176}.{21,101,221}` (never
the blocked `.161`/`.231` — those are `mcp.stripe.com`); `api.linkedin.com` →
`104.18.41.41` (never `104.18.25.159` — that is `mcp.cloudflare.com`);
`hn.algolia.com` → `34.160.168.181` only (never `34.149.x`); `discord.com`/`api.x.com`
on `162.159.x`. `34.149.66.137` serves only the Datadog `us5` cert across **every**
tested SNI (including allowlisted-host SNIs), confirming it fronts no allowlisted
host. So the #5413-class recovery rests on exact-IP disjointness, not on the
unreliable shared-anycast default-cert (the same caution this doc applies to the
Cloudflare `104.16.0.0/13` npm pool).

**Recovery-window caveat.** The 100-event sample spans ~2 days (06-27→06-29), shorter
than this incident's original 4–8-day per-cron manifestation latency. A low-frequency
cron could still surface a missed rotation IP later; the per-host recovery criterion
below keeps that observable, and any recurrence on an **allowlisted** host re-opens
this post-mortem.

## Symptom

6 of ~42 Sentry cron monitors in `error`/missed state for days; `egress-blocked`
Sentry events firing continuously (654 hits) with blocked `DST` IPs mapping to
Cloudflare `104.18.x` (linkedin/x/discord/resend), AWS `198.x`/`64.239.x`
(bsky/buttondown/flagsmith), and Google-LB `34.149.x` (hn.algolia, read by
community-monitor). Every blocked IP fronted a host **already** in
`cron-egress-allowlist.txt`.

## Incident Timeline

| Actor | Time (UTC) | Action |
|---|---|---|
| agent | ~2026-06-08 → 06-14 | ADR-052 egress firewall hardened/rolled out; single-A-record resolver under-covers LB pools. |
| — | 06-08 → 06-16 | Heavy crons begin missing check-ins (per-cron onset: follow-through ~06-08, content-generator 06-11, community-monitor 06-12, bug-fixer 06-14). |
| human | 2026-06-16 ~11:30 | Operator asks to audit whether this week's Inngest workflows ran. |
| agent | 2026-06-16 | Diagnosed via Sentry cron-monitor check-in history + egress-blocked issue + ipinfo.io IP→org mapping. Root cause confirmed; fix shipped (#5413). |

## Detection (+ MTTD)

Detected reactively by operator audit on 06-16, ~4–8 days after onset. The
durable run-log (`public.routine_runs`, PR #5342) had only deployed that morning
(9 rows, all 06-16) so could not surface the historical gap — **Sentry cron-monitor
check-in history was the only week-spanning source.** MTTD gap: the missed-check-in
monitors were `error` but no one was paging on the cohort pattern.

## Triggered by

The ADR-052 default-drop egress firewall + its single-A-record-per-tick resolver,
applied to LB-fronted allowlisted hosts whose rotation pools exceed one tick's
DNS snapshot.

## Root-cause hypothesis (triage)

| Hypothesis | Supporting evidence | Disconfirming evidence | Status |
|---|---|---|---|
| LB-rotation egress drops on allowlisted hosts | 654 egress-blocked hits; blocked IPs map to CDN/LB orgs fronting allowlisted hosts; missed-not-failed signature | — | CONFIRMED |
| GitHub CIDR gap (like 5516336) | GitHub-heavy crons also affected | `/meta` set-difference probe shows ZERO gap today; GitHub timeouts last fired pre-06-14-fix | RULED OUT (current) |
| Container restart loop interrupting crons | ~10–60 restarts/day; "cwd no longer exists"; firewall chain flush | Lightweight crons unaffected; secondary to egress | CONTRIBUTING (tracked #5417) |

## Resolution

Resolve-and-retain (grace-window IP retention) in `cron-egress-resolve.sh`: retain
every IPv4 observed for an already-allowlisted host within `GRACE_WINDOW_SECS`
(24h) in a `StateDirectory`-backed store, so the allow set accumulates each host's
full rotation pool — tight (no provider CIDRs), rotation-proof. See #5413.

## Recovery verification

Post-apply (no ssh, no dashboard-eyeball): `apply-web-platform-infra` post-apply
container probes green (no `ASSERT-FAILED`); Sentry `cron-egress-resolve` monitor
OK with a `retained=` count exceeding `allow=`; the six eval-cron monitors recover
to OK on their next scheduled fire (no manual trigger).

**Recovery criterion is PER-IDENTIFIED-HOST, never a raw `egress-blocked` DST-IP
threshold (corrected #5676).** The original "104.18.x/198.x/34.149.x DST hits
trend to zero" framing is unsatisfiable as written, because the same issue also
counts **intended-by-design** drops (npx→registry.npmjs.org, #5199) that are
permanent and correct. The criterion: for each *allowlisted* host that was
LB-rotation-dropped in this incident, its DST hits trend to zero within one grace
window (VERIFIED 2026-06-29). Intended drops (npx registry probe) are EXCLUDED —
they are silenced at source (#5676), not expected to reach zero via retention.
A DST-IP/range exclusion at the emitter is explicitly rejected (see ADR-052
amendment 2026-06-29): registry.npmjs.org rides Cloudflare's shared anycast
`104.16.0.0/13`, so muting it by IP would simultaneously blind a genuine future
gap to another Cloudflare-fronted host.

# Incident Post-Mortem Analysis

## Root Cause(s) — 5-Whys

1. Why did the heavy crons stop? Their egress was default-dropped. 2. Why dropped?
The destination IP was not in the nftables allow set. 3. Why not in the set? The
resolver pinned only the current tick's single-A-record answer. 4. Why insufficient?
LB-fronted hosts rotate across pools larger than one snapshot. 5. Why not caught?
The firewall rollout treated all allowlisted hosts as single-IP; the LB-rotation
class was only proven for GitHub (5516336) and not generalized.

## Impact details

### Services Impacted
The 6 Claude-eval crons (community digest, content generation, follow-through
nudges, autonomous bug-fix PRs, roadmap/agent-native audits). Lightweight crons
unaffected.

### Customer Impact (by role)
Solo-operator / tenant-zero: lost days of automated community monitoring, content,
follow-through, and autonomous engineering output. No external customer data
exposure (availability-only).

### Revenue Impact
None directly (pre-revenue automation).

### Team Impact
Operator audit + this remediation session.

## Lessons Learned

### Where we got lucky
The durable run-log had JUST deployed; without Sentry cron-monitor history the
outage would have been much harder to reconstruct.

### What went well
Multi-agent review confirmed the security-preserving fix (retain observed
DNS answers, not provider CIDRs) holds the ADR-052 boundary.

### What went wrong
A default-drop egress firewall was rolled out with a single-IP resolver for
LB-fronted hosts; nobody paged on the missed-check-in cohort pattern for days.

## Action Items & Follow-ups

**Each row cites a filed GitHub issue.**

| Issue | Action | Status |
|---|---|---|
| #5417 | Investigate + remediate the ~10–60×/day `soleur-web-platform` container restart loop (independent contributing factor: kills heavy crons mid-run, flushes the egress firewall chain). | open |
| #5676 | Residual egress-blocked volume characterised: dominant `104.16.x.34` is the intended npx→`registry.npmjs.org` probe (#5199), silenced at source (`npm_config_prefer_offline`); recovery criterion reframed per-host; ADR-052 amended (intended-drops expected, emitter DST-IP suppression rejected). | this PR |
| #5691 | **Resolved** — dialer identified per host: the claude-eval substrate's `--plugin-dir plugins/soleur` auto-connects `plugin.json`'s four remote MCP servers (vercel/cloudflare/stripe/context7) at startup, and `34.149.66.137` is CC non-essential traffic / context7 backend (default-cert, unproven host). All five hook-denied / non-essential → kept blocked, silenced at source via `--strict-mcp-config` + `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1` (no allowlist/CIDR widened). ADR-052 amended (2026-06-29 #5691). | resolved |
