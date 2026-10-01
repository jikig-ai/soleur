---
title: "Cloudflare 524s made cron Claude runs pay twice and commit nothing"
date: 2026-09-23
incident_pr: 8611
incident_window: "measured over the 30 days to 2026-09-23; onset not established (serveHost pinned to the proxied origin in #5159)"
recovery_at: "the #8611 web-platform deploy"
suspected_change: "#5159 — serveHost pinned to https://app.soleur.ai, a Cloudflare-proxied record"
brand_survival_threshold: aggregate pattern
status: resolved
triggers:
  - operator report: a $50 Anthropic top-up lasted about a day and a half
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "n/a — operator spend and missed cron output only; no personal data was exposed"
---

## Actor key

- `agent` — Claude Code did this autonomously (no operator ack required).
- `agent-with-ack` — Claude Code did this AFTER operator confirmed via menu option per `hr-menu-option-ack-not-prod-write-auth`.
- `human` — Operator did this directly.

# Incident Overview

The self-hosted Inngest server calls every step through `https://app.soleur.ai/api/inngest`, which Cloudflare proxies with a ~100 s origin timeout. Every claude-eval cron step runs 5–70 minutes, so each one got a 524. `retries: 1` re-invoked the unmemoized step, which spawned a second paid Claude session. The retry got a 524 as well, and the run was marked failed before its verify and commit steps ran.

## Status

resolved — one of `resolved` / `unresolved but ended` / `ongoing`. Mirrors the `status:` frontmatter above; do not introduce a second source of truth.

## Symptom

Anthropic credit drained far faster than the cron schedule explains. Better Stack showed pairs of `SOLEUR_CLAUDE_COST` markers under one Inngest run id with overlapping lifetimes, and most paid runs produced no PR or issue.

## Incident Timeline

- **Start time (detected):** 2026-09-23 (operator report)
- **End time (recovered):** the #8611 deploy
- **Duration (MTTR):** same-day fix; onset-to-fix not established

Order of events (load-bearing: the redaction sentinel scans this table; the Actor key feeds the Actor column):

| Actor | Time (UTC) | Action |
|---|---|---|
| human | 2026-09-23 | Reported the Anthropic cache-hit email and a $50 top-up consumed in about a day. |
| agent | 2026-09-23 | Queried Better Stack: paired cost markers per run id; inngest-server `invalid status code: 524` about 2 min into each step. |
| agent | 2026-09-23 | Measured 30 days of spend: $159.81, of which $82.04 (51%) was duplicate runs; 24 of 33 paid runs committed nothing. |
| agent-with-ack | 2026-09-23 | Ran the streaming spike (S1–S8) on the pinned server behind a real Cloudflare tunnel, then implemented #8611. |

## Participants and Systems Involved

Operator; Claude Code. Systems: self-hosted Inngest server, the web-platform `/api/inngest` handler, Cloudflare proxy, the claude-eval cron substrate, Better Stack Logs.

## Detection (+ MTTD)

- **How detected:** manual. The operator noticed the credit balance; no alert existed for spend rate or step 524s.
- **MTTD (mean time to detect):** not established. While credit was exhausted, every run failed in seconds and never reached the 100 s mark, which hid the pattern.

## Triggered by

system — a transport limit (Cloudflare origin timeout) combined with an Inngest retry policy.

## Root-cause hypothesis (triage)

Triage-time competing hypotheses; the post-resolution final root cause lives in the 5-Whys section below.

| Hypothesis | Supporting evidence | Disconfirming evidence | Status |
|---|---|---|---|
| Low prompt-cache hit rate drives the spend | Anthropic email | Agent SDK traffic already caches above 97%; the direct API calls are one-offs hours apart | rejected |
| Proxy 524 plus retry double-spawns each long step | Paired markers per run id; 524 logged ~2 min in; second spawn 2.5–4.7 min after the first while it still ran | none | confirmed |

## Resolution

#8611: Inngest steps stream their responses (ADR-243), so the proxy never times them out. A single-flight guard lets a retry join the in-flight or settled Claude run instead of spawning another. Every spawn site has a per-run dollar ceiling and a 2-per-hour throttle. Better Stack now alerts on step 524s, cut streams, daily spend above $25, and a silent cost stream.

## Recovery verification

After deploy: `bash scripts/probe-inngest-524-count.sh` reads `count=0`, and the 72 h probe `scripts/followthroughs/anthropic-double-bill-8611.sh` (tracker #8635) finds no repeated run id or retried founder turn. Over the 7 days before the deploy, the same probe reads 30 cron markers over 22 run ids.

---

# Incident Post-Mortem Analysis

## Root Cause(s) — 5-Whys

1. Why did credit drain? Each long cron paid for two Claude sessions and most committed nothing.
2. Why two sessions? `retries: 1` re-ran the claude-eval step after its first attempt failed.
3. Why did the first attempt fail? The Inngest server got a 524 from Cloudflare about 100 s in.
4. Why a 524? `serveHost` points at a Cloudflare-proxied hostname, and a claude-eval step held one request open for minutes.
5. Why was that not caught? No alert covered step 524s or spend rate, and the credit-exhausted period masked the pattern.

## Versions of Components

- **Version(s) that triggered the outage:** web-platform with `serveHost` pinned to the proxied origin (#5159); inngest SDK 3.54.2 without streaming.
- **Version(s) that restored the service:** web-platform with #8611.

## Impact details

### Services Impacted

Scheduled claude-eval crons (growth, content, triage, audits, bug-fixer and others): duplicated spend and missing output.

### Customer Impact (by role)

Per learning `2026-05-06-user-impact-section-by-role-not-surface.md` — enumerate by USER ROLE, not by surface. This is the canonical "Customer Impact"; do NOT add a second free-text Customer Impact block.

- Prospect: none.
- Authenticated app user: none observed. Founder BYOK leader-loop turns run through the same handler, but no founder double bill was measured; #8635 watches for one after the transport change.
- Legal-document signer: none.
- Admin via Access: none.
- Billing customer: none.
- OAuth installation owner: none.

### Revenue Impact

Operator cost: $82.04 of duplicate Claude spend in the measured 30 days, plus the paid runs that committed nothing.

### Team Impact

Cron-driven PRs and issues were silently missing; the operator had to top up credit early.

## Lessons Learned

### Where we got lucky

Credit exhaustion capped the loss: while the balance was zero, runs failed before spending.

### What went well

The per-run cost markers made the duplicates measurable to the cent in one query.

### What went wrong

No alert covered spend rate or step transport errors. The first explanation offered (prompt caching) was a red herring.

## Action Items & Follow-ups

Every action item and follow-up so this incident cannot recur (save logs, add tests, set up alerts, automation, documentation, code sweeps, PRs).

| Issue | Action | Status |
|---|---|---|
| #8635 | 72 h check that no paid Claude call ran twice after the #8611 deploy (rollback trigger). | open |
| #8613 | Tune `--max-turns` and recalibrate caps from the new `num_turns` data. | open |
| #8614 | Add a Console workspace monthly spend limit for the cron key. | open |
| #8628 | Upgrade inngest to v4 and delete the `stream-detach.ts` workaround. | open |
