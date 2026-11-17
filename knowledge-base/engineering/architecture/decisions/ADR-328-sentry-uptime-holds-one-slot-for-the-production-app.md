---
title: Sentry uptime holds one slot, for the production app; Better Stack owns marketing-site uptime
status: active
date: 2026-11-17
issue: 12844
amends:
  - ADR-204
---

# ADR-328: Sentry uptime holds one slot, for the production app; Better Stack owns marketing-site uptime

## Context

Sentry includes one uptime monitor and bills each further one at $1.00/mo as pay-as-you-go. On
2026-11-17 the org had five, so four were billed ($4.00 accrued this period, read live from
`GET /customers/jikigai-eu/`). Four were declared in `apps/web-platform/infra/sentry/uptime-monitors.tf`:
`soleur_apex`, `soleur_www_reachability`, `soleur_changelog_deep` and `soleur_acme_probe`. The fifth,
1422253 on `https://app.soleur.ai`, was auto-detected by Sentry and unmanaged (mode 3, #6606).

Better Stack includes ten uptime monitors and used seven. It already watched the marketing apex
(`betteruptime_monitor.soleur_apex`) and www (`betteruptime_monitor.soleur_www_redirect`, which
requires a 301 without following it, so it also fails on DNS, TLS and 5xx errors on www).

Three facts decide which monitor keeps the one free Sentry slot:

- The ACME probe always passes since the Cloudflare Pages cutover (ADR-194). Pages serves its own
  404 whatever the carve-out rule does, and the resource's own description says it is vacuous. The
  carve-out property it was meant to guard stays open on #7799.
- 1422253 is Sentry's only watch on the production app. On 2026-07-17 the operator ruled (DC-1,
  #6606) that the app stays on two vendors.
- The marketing site holds no user data.

ADR-204 recorded "apex reachability is deliberately second-sourced across Sentry and Better
Stack" as a consequence. This decision ends that for the marketing site, so it needs its own record
(ruling D-F-C).

## Considered Options

| Option | Why not |
|---|---|
| **Chosen:** the app monitor holds Sentry's slot as a newly declared monitor, and 1422253 is deleted through the API; marketing-site uptime moves to Better Stack | See Decision |
| Keep the ACME probe as the included slot and delete 1422253 (the brief's option A) | The probe cannot fail, so it watches nothing, and deleting 1422253 takes the production app off its second vendor, against DC-1 |
| Adopt 1422253 by an `import` block (the first D2 ruling) | Cannot pass CI. `scripts/sentry-adoption-plan-assert.sh` runs unconditionally in `plan_pr` and in the apply job, and reads any import or forget row as the #7650 alert adoption: it requires 2 `sentry_alert` pairs and a no-op import row, so this plan failed it on run 44095436160. The `removed {}` variant is a forget and fails the same way. Weakening that gate to merge this change was rejected (D2 re-ruling) |
| Move the ACME probe to Better Stack | A check that cannot fail buys nothing on any vendor |
| Keep both vendors on the marketing apex ($1.00/mo) | The marketing site holds no user data, and `betteruptime_monitor.soleur_apex` already watches it at 180 s |
| Route a Sentry alert for the app uptime monitor | Better Stack already pages for the app, so a routed Sentry alert would page the same outage twice (ruling D-F-E) |

## Decision

1. **Sentry's one included uptime monitor watches `https://app.soleur.ai`.** It is
   `sentry_uptime_monitor.app` (`soleur-app-reachability`), a new manual monitor declared in
   Terraform. The auto-detected 1422253 is deleted through the API (read, delete, read expecting
   404), so no auto-detected monitor remains (ruling D2, D3a). Its check history is lost; that is
   accepted. Cadence: 60 s checks, downtime threshold 3, recovery threshold 1 (ruling D7). This keeps
   two-vendor coverage where user data lives (DC-1).
2. **Better Stack pages for the app; the Sentry monitor only detects.** `betteruptime_monitor.app`
   and `betteruptime_monitor.app_health` page. The Sentry monitor opens an issue on downtime and is
   bound to no alert route, which is what the `sentry -> founder` edge in `model.c4` already says.
3. **Marketing-site uptime is Better Stack only.** Reachability, redirect health and the deep path
   are watched by `soleur_apex`, `soleur_www_redirect`, `soleur_changelog_deep` (moved from Sentry
   to a free Better Stack slot, so the "root 200, deep pages 404" check stays at $0) and the three
   sampled redirect probes of ADR-204's 2026-09-20 amendment. The Sentry monitors `soleur_apex`,
   `soleur_www_reachability`, `soleur_changelog_deep` and `soleur_acme_probe` are deleted.
   Better Stack goes from 7 to 8 of its 10 included uptime monitors.
4. **Vendor split rule.** New uptime monitors go to Better Stack while it has included slots.
   Dead-man and cron signals go to Sentry whenever the next Better Stack $20 heartbeat pack would be
   crossed; the first case is the four paused `soleur-host-kernel-*` heartbeats, which page from
   per-host Sentry cron monitors when #12386 arms them (ruling D4). The production app always stays
   on two vendors. Once Better Stack's ten included uptime monitors are used, the next uptime
   monitor goes to Sentry at $1.00/mo rather than starting a paid Better Stack tier.
5. **The rule is checked, not trusted.** An uptime section in
   `scripts/sentry-alert-live-fidelity.sh` reports any live uptime detector whose mode is not
   manual, and a live count above the declared count (ruling D-F-B). No auto-detection setting is
   written: the org-level option, which decides, has no public API field, and Sentry turned it off
   itself when it created 1422253. The project-level option is writable through the project PUT
   but does not override the org one.

### Sequencing

This record is true at merge once both apply workflows finish and 1422253 is deleted.
`apply-sentry-infra.yml` (full root) and `apply-web-platform-infra.yml` (target-scoped) run
independently, so the Sentry changelog monitor can be gone minutes before the Better Stack one
exists; that gap is one apply on a static page and is accepted. 1422253 is deleted immediately
before the merge, not after it: the post-apply live-fidelity probe in `apply-sentry-infra.yml` runs
under `set -e` and fails on any live uptime monitor that is not manual, so a delete after the apply
would turn that merge's run red. The app has no Sentry uptime monitor from the delete until the
apply creates `sentry_uptime_monitor.app`, minutes later; Better Stack pages for the app through
that window (Decision 2). The new monitor is read back after the apply (mode 1, url
`https://app.soleur.ai`). The Better Stack changelog entry
in `cutover-verify.sh` CUT8 and its baseline row land together in the follow-up PR (ruling D-F-F),
and the host-kernel cron monitors land in #12386.

## Consequences

- Sentry uptime bills $0, and no auto-detected Sentry monitor remains, which closes #6606.
- The production app keeps two vendors: Better Stack pages and Sentry detects, so a Sentry outage
  is still survivable for the app.
- **Dissent, recorded:** a Better Stack outage leaves soleur.ai (apex, www and the deep path)
  unwatched. This is accepted because the marketing site holds no user data. A hard 522 on www is
  now detected only by `soleur_www_redirect`, in about 23 min worst case instead of about 15 min
  through the deleted Sentry www monitor.
- **Dissent, recorded (D4):** after #12386 arms the host-kernel monitors on Sentry, one outage of
  the dead-man feeder pages on five Sentry monitors instead of one.
- The ACME carve-out property is no longer watched at runtime by any vendor; it stays tracked on
  #7799, as it effectively was since the Pages cutover.
- `cutover-verify.sh` CUT8 no longer grades Sentry monitors: Sentry watches no marketing URL.
- Sentry could auto-detect a new monitor again. Its own code turns the option off after the first
  auto monitor and does not re-create deleted ones; if it does, the uptime check reports it within
  one scheduled run.
- ADR-204 is amended by pointer at its apex second-sourcing consequence and at its rejected
  "delete `sentry_uptime_monitor.soleur_www` outright" row. Its accepted body is unchanged.

## Cost Impacts

- Sentry uptime: $4.00/mo becomes $0. That is the whole direct saving.
- The Sentry line read live on 2026-11-17 is $54.06 ($29 base + $21.06 cron for 27 billable
  monitors + $4.00 uptime accrued). The 2026-12-16 invoice is $50.06 to $54.06, depending on whether
  the accrued $4.00 is refunded (unverified). Steady state is $50.06/mo, and $53.18/mo after #12386
  adds four cron monitors. The 2026-11-17 invoice of $84.48 is billing lag from the 2026-10-29
  monitor prune, not a figure from this decision.
- Better Stack: $0. Uptime goes from 7 to 8 of 10 included monitors.
- The host-kernel re-route costs $3.12/mo on Sentry instead of a second $20.00 Better Stack
  heartbeat pack: $16.88/mo avoided, realized in #12386.
- Ledger: `knowledge-base/operations/expenses.md` (Sentry Team and Better Stack rows) and
  `knowledge-base/finance/cost-model.md` (2026-11-17 review note).

## NFR Impacts

No NFR changes status.

- **NFR-003 Service-Level Monitoring, NFR-013 Synthetic Monitoring:** the production app keeps
  synthetic uptime checks on two vendors; marketing-site checks move to one vendor. The register's
  "No uptime monitoring" rows for the dashboard and API routes predate both vendors' app monitors.
  Correcting them is outside this decision.

## Principle Alignment

- **AP-001 Terraform-only infrastructure provisioning:** aligned. The app monitor is declared in
  Terraform; the one unmanaged monitor was created by Sentry, not by us, and is deleted through the
  API because no import can pass the adoption gate. The Better Stack monitor is declared there too.
- **AP-007 Exhaust automation before manual steps:** aligned. No dashboard step: the agent-run API
  delete and the scheduled check replace a settings change that has no API.
- **AP-011 ADRs for architecture decisions:** aligned (this record).
- **AP-024 A verification surface does not actuate:** aligned. The uptime check reports an
  unmanaged monitor and does not delete it.
- **AP-012 New vendor checklist:** not applicable. No new vendor.

## Diagram

No C4 element or view changes. The `sentry` and `betterstack` element descriptions in
`knowledge-base/engineering/architecture/diagrams/model.c4` now say that the production app is
second-sourced (Better Stack pages, Sentry detects), that marketing-site uptime is Better Stack only,
and that Sentry holds one uptime monitor.
