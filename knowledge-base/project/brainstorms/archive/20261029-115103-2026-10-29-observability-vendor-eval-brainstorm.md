---
title: Observability vendor re-evaluation — Sentry + Better Stack vs Datadog vs SigNoz
date: 2026-10-29
issue: 4296
pr: 11494
branch: feat-observability-vendor-eval
lane: cross-domain
brand_survival_threshold: single-user incident
status: decision-captured
---

# Observability vendor re-evaluation #4296

This session executed the 60-day re-decision deferred from #4273 on 2026-05-22
(tracker #4296, ~130 days overdue; it was effectively superseded by the 2026-08-14
Better Stack quota outage and the forced paid upgrade).

## What We're Building

Not a migration — a **certification + right-sizing**. The operator asked whether
Datadog or SigNoz would be cheaper than the current Sentry + Better Stack split
(€156.67/mo: Sentry €75.53, Better Stack €81.14) for a pre-launch product with
~1 active user, and what migration would cost.

**Decision: stay multi-provider and right-size.** Both bills are
*architecture-driven, not vendor-driven*, and two already-filed issues carry the
fix:

1. **Sentry bill = monitor count, not usage.** ~67 `sentry_cron_monitor` PAYG
   seats × $0.78 (~$52) + 4 uptime monitors × $1.00 + $26 Team base. Fix lives in
   **#6590** (deep prune + ADR-031 monitor-per-cron amendment) — the deferred
   NG3/NG4 of the July `feat-sentry-monitor-spend` spec. Only ~44 live Inngest
   crons post heartbeats, so ~23 declared monitors may already be orphaned.
2. **Better Stack bill = log volume.** Post-mortems measured host_metrics >99%
   then multi-line container logs ~75% of ingest; the 2026-08-16 paid upgrade
   was forced by a 49 h quota-402 outage and volume is unchanged since. Fix
   lives in **#7577** (cut ingest at the Vector chokepoint).

Expected outcome: ~€55–90/mo (~40–65% reduction) in days, zero capability loss,
preserving the deliberate vendor-isolation doctrine (ADR-218: the pager must not
live on the vendor it watches — Better Stack is the escape that survives a
Sentry send-path failure).

## Price comparison (measured against this repo's footprint)

| Option | Est. monthly | One-time effort | Notes |
|---|---|---|---|
| Today | €156.67 | — | Monitor seats + log volume driven |
| **Stay + right-size** | **~€55–90** | **days** | Executes #6590 + #7577 |
| SigNoz Cloud | ~€45–82 + companion tool | **~2–4 wks** | No heartbeats/uptime/on-call/status-page → still 2 systems; US importer (Ch. V transfer); OTel port of emit funnel |
| SigNoz self-hosted | ~€20–35 | ~2–4 wks + ongoing ops | Best GDPR posture (no new sub-processor); worst ops — zot-registry post-mortem series is the measured cost of self-hosted infra on this fleet; CX33 8 GB ruled non-viable 2026-03 |
| Sentry-only (Path A) | ~€95–110 | ~1–2 wks | Kills redirect-health (`follow_redirects=false` is inexpressible on Sentry — ADR-204), DB-readiness body-keyword pager (ADR-222), independent wake path; gated on #3814/#3815/#3865/#3866 + #4297 contract test |
| Better Stack-only | ~€140+ | ~1–2 wks | Sentry-SDK-compatible error tracking exists now (new since May) but heartbeats cost 2.5× Sentry crons ($2.00 vs $0.78 — measured in feat-sentry-monitor-spend NG2); loses Sentry-grade error triage; DPA unexecuted (#7529) |
| Datadog | ~€210–240 | ~3–6 wks | **Dead — reaffirmed.** Unanimously rejected 2026-05-22 (#4273: +$140–155/mo, $3–4.5k migration); fresh pricing confirms worse. US importer; APM ingests request bodies (OAuth tokens) by default. Re-open only if a paying customer requires APM AND cost floor is amortized |

## Why This Approach

**The migration bill is larger than the SaaS bill.** Repo-research measured
~370–450 tracked files and ~185 Terraform resources in the blast radius: 120
`sentry_*` TF resources, 63 `betteruptime_`/`logtail_` resources, ~280 emit call
sites (narrow — they funnel through `reportSilentFallback`/`postSentryHeartbeat`),
80 heartbeat step registrations across ~44 Inngest crons, 24 heartbeat invocations
in 19 workflows, ~13 host scripts with byte-pinned Sentry transport blocks,
~15 credential names, ~60 runbooks, ~55 guard/test files. Prior engineering
estimate $3–4.5k → **~20–38 month payback** at ~€70–100/mo savings (CFO).

**Neither candidate delivers "one system."** SigNoz lacks cron heartbeats,
uptime/synthetics (the redirect-301 assertion is structurally expressible only on
Better Stack — ADR-204), on-call paging, and a status page; Datadog has them but
at a higher bill than today. Consolidation to Sentry-only removes the only alarm
on redirect-health and DB-readiness — gaps previously paid for with 89-min and
37-min outages.

**The two-vendor split is deliberate, not sprawl.** ADR-218 + ADR-260 + ADR-298:
Better Stack is the independent wake path (Slack + push + GitHub-issue mirror —
the channel that provably reached the operator during the 2026-10-22 incidents).
Single-vendor collapse deletes the watchdog-of-the-watchdog.

## User-Brand Impact

**Brand-survival threshold:** `single-user incident`.

- **Artifact:** the observability wake path (Sentry alerts + Better Stack
  paging/mirror) for a product onboarding its first external testers (CPO: 1/10
  alpha cohort; error tracking + uptime + DB-readiness paging are launch-critical).
- **Vector:** worst case is a silent coverage regression during a vendor swap —
  a monitor dark while a recruit's first session is down.
- **Mitigation in chosen path:** right-sizing changes no transport, no wake
  chain, no IaC doctrine — only monitor count and ingest volume.

## Key Decisions

| # | Decision | Rationale |
|---|----------|-----------|
| 1 | Stay multi-provider (Sentry + Better Stack); do not migrate | Bills are architecture-driven; migration is ~370–450 files / ~185 TF resources for ~20–38-mo payback |
| 2 | Execute #6590 (Sentry monitor deep prune, ADR-031 amendment) | $52/mo of the Sentry bill is per-monitor seats; ~23 of 67 monitors have no live producer |
| 3 | Execute #7577 (Better Stack ingest trim at Vector chokepoint) | Post-mortem-measured volume drivers unchanged since the forced upgrade |
| 4 | Datadog stays dead | Fresh pricing confirms the 2026-05-22 unanimous rejection; re-open trigger unmet |
| 5 | SigNoz logged as the durable OTel direction, not now | Feature gaps keep it a two-vendor world anyway; revisit criteria in Open Questions |
| 6 | #4296 re-decision executed by this document | Certifies "stay multi-provider"; Path A (Sentry-only) remains deferred with its prerequisites (#3814/#3815/#3865/#3866/#4297) intact |

## Open Questions

1. **Revisit SigNoz/OTel when:** (a) the product has real multi-user traffic AND
   (b) either error-triage needs outgrow Sentry, or the consolidated bill (after
   right-sizing) still exceeds ~€100/mo. SigNoz Cloud's $49 floor + a free-tier
   uptime companion would then be the candidate.
2. **Better Stack Art. 28(3) DPA remains unexecuted** (`compliance/critical`
   #7529) — independent of vendor choice; executing it (or dropping the vendor)
   is the only path to a clean register row.
3. **Sentry Vendor DPA Status row missing** — same omission class corrected for
   Cloudflare (#7601) and Proton (#7845); record the instrument.
4. **Orphaned monitors** — ~23 declared `sentry_cron_monitor` resources have no
   Inngest producer; #6590's prune should enumerate live-vs-declared first
   (`sentry-monitors-audit.sh` + `heartbeat-live-reconcile.ts` already diff this).
5. **Monitor-value evidence** — #6591 (which monitors ever caught a real miss)
   informs which ~15–20 monitors survive the prune.

## Domain Assessments

**Assessed:** Engineering, Product, Legal, Finance, Operations (5 of 8).
Marketing, Sales, Support not relevant for internal observability substrate.

### Engineering (CTO)

**Summary:** Emit layer is centralized (port surface ~5 functions, not 1,700 call
sites), but the IaC/alert layer is the true blast radius — each alert rule is
re-derivation, not translation. Right-sizing current plans captures most savings
at a fraction of the effort; SigNoz+OTel is the durable direction but trades
which two vendors you run, not whether you run two.

### Product (CPO)

**Summary:** Alpha onboarding is underway (1/10 testers) — this is still the
cheapest feasible change window, but error tracking, uptime, DB-readiness paging
and cron-dark detection are launch-critical; if migration ever proceeds it must
be a parallel-run cutover, never big-bang.

### Legal (CLO)

**Summary:** Self-hosted SigNoz is the only option that *improves* posture (no
new sub-processor); both cloud options introduce a US Chapter V transfer. Sentry
remains the Art. 33 breach-clock anchor — no unanchored interval at any future
cutover. Better Stack's unexecuted DPA (#7529) is independent debt.

### Finance (CFO)

**Summary:** Observability is ~40% of product COGS ($141.56 of $354.47/mo).
Right-sizing pays back in days–weeks; a $3–4.5k migration pays back in ~2–3
years. Sentry cost grows with the cron/agent fleet regardless of users —
monitor count is the structural lever.

### Operations (COO)

**Summary:** Optimize before migrating: shave Sentry PAYG monitor seats and
verify the unnamed ~$68 Better Stack plan. Self-hosted SigNoz is an ops
regression on this fleet; Datadog stays dead per standing unanimous rejection.

## Capability Gaps

None — every required capability exists; the chosen path executes filed issues.

## Session Errors

None. Prior-art discovery worked as designed: the #4296 re-decision tracker,
the July `feat-sentry-monitor-spend` spec, and both right-sizing issues (#6590,
#7577) were found before option framing, so the option space was bounded by
measured facts rather than re-derived.

## Productize Candidate

None — the work executes existing issues; the re-decision is a one-time event.

## Deferred Items

- **SigNoz/OTel migration** — revisit criteria recorded in Open Questions 1.
  Not a new issue: #4296 remains the tracker of record for vendor re-decisions.
- **Path A (Sentry-only consolidation)** — stays deferred with its recorded
  prerequisites (#3814, #3815, #3865, #3866, #4297).
- **Datadog** — dead; re-open only on the #4273-recorded trigger.

## References

- Prior decisions: #1218 (2026-03 vendor selection), #4273 brainstorm + spec
  (Path B/C dead, Path D chosen), #4296 (this re-decision), ADR-031, ADR-204,
  ADR-218, ADR-222, ADR-260, ADR-298.
- Right-sizing work: #6590 (monitor prune), #6591 (monitor-value telemetry),
  #7577 (ingest cut), `feat-sentry-monitor-spend` spec (PAYG cliff fixed,
  delete path fixed).
- Compliance: #7529 (Better Stack DPA unexecuted), PA-8 Article 30 row,
  Sentry Art. 33 clock anchor.
- Live pricing fetched 2026-10-29: datadoghq.com/pricing, signoz.io/pricing,
  sentry.io/pricing, betterstack.com/pricing.
