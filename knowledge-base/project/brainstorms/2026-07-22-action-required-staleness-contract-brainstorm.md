---
date: 2026-07-22
topic: action-required escalation staleness contract
issue: 6769
status: design-chosen
lane: cross-domain
brand_survival_threshold: single-user incident
---

# Brainstorm: `action-required` Escalation Staleness Contract (#6769)

## TL;DR — the finding inverts the issue's premise

#6769 asked whether `action-required` has a ~0% resolution rate because it is a
write-only sink nobody reads, and named `operator-digest` Section 4 as the most
likely single point of failure. **The cheap check disproved that.** The digest
runs weekly, mostly green, and has surfaced the backlog ~18 times. The channel is
not dead — it is **untriaged, polluted, undelivered, and un-aged**. Four distinct
root causes, none of which is "the digest doesn't run."

## The evidence (all verified this session)

| Layer | Failure | Evidence |
|---|---|---|
| **Delivery** | Weekly digest filed with **no assignee / no notification** | `jikig-ai/operator-digest` issues #1–#7 all have `assignees=[]`. Only #8 — *"probe: verify digest assignee delivery (#6769)"* — is assigned to `deruelle`, and **that run failed** (`gh issue create --assignee` errored). Digest lands in a private repo the operator must proactively open. |
| **Presentation** | Section 4 is a flat, age-blind, priority-blind, uncapped list | Harvest query is `gh issue list --label action-required --json title,url` (SKILL.md §4). No sort, no age, no priority, no cap. In the W29 digest, a P1 infra ask renders with the same weight as *"Decision challenges — informational, not blocking"*; #4375 (the cron watchdog) is the second-to-last line and never escalated as it aged 36 → 58 days. |
| **Routing** | `decision-challenge` and content chores are **double-stamped** `action-required` | Of 30 open: 13 are a `decision-challenge` burst, 6 are content-publishing chores (64–131 days old). Both classes already have their **own** labels (`decision-challenge`, `content`/`content-starvation`) but producers also stamp `action-required`, collapsing the harvest back into noise. A reader shown mostly noise skims all of it, including the P0. |
| **Lifecycle** | No SLA / escalate / expire | 131-day chores (#553, #555 "post to HN/IndieHackers") never age out. The non-technical operator structurally will not do manual social posting, so these can never resolve where they sit. `content-starvation`'s description ("auto-filed/**closed** by cron-content-publisher") proves auto-close is already an accepted in-repo pattern. |

**Counts:** 30 open / 57 closed → the label **partially drains** (not a write-only
sink). **Load-bearing by design:** `scheduled-inngest-health.yml:853` picks
`action-required` explicitly *because* "operator-digest harvests ONLY issues
carrying it." Age distribution: 23 of 30 are <30d; the rot is concentrated in 7
aged items, 6 of which are structurally-dead content chores + 1 genuine watchdog (#4375).

**On the #6768 data point:** routing *around* the channel (keeping the operator in
the loop for UC-1 instead of filing action-required) was a rational response to a
channel that *looks* dead. The fix is to make the channel **trustworthy** again —
not to abandon it, which would scatter escalation into ad-hoc loops.

## What We're Building — a four-layer staleness contract

Chosen scope (operator decision, 2026-07-22): **Full contract, staged.** The four
layers ship independently so value lands incrementally and blast radius is bounded.

1. **Delivery fix (ship first — highest impact, smallest change).** Every weekly
   digest issue is **assigned to the operator and notifies** them (fix the failing
   `--assignee` path the #8 probe exposed; add a push channel if assignee-notify
   alone is insufficient). A digest nobody is pinged about is the whole failure in
   one line.
2. **Triage the render.** Rewrite Section 4 to sort by **(priority, age)**, surface
   an explicit **"🔴 oldest / SLA-breaching"** sub-block with **per-item age in
   days**, and **cap** the long tail with "+N more". Age becomes a visible signal.
3. **De-pollute the channel.** Stop double-stamping `action-required` on
   `decision-challenge` and content classes; have the harvest use a **stricter
   predicate** (true only-you-can-do asks). `decision-challenge` already routes to
   its own operator-reversal surface — it does not belong in the same "act now" list.
4. **SLA lifecycle cron.** Escalate an item's priority label as its age crosses
   thresholds; **auto-expire structurally-dead classes only** (content-publishing
   chores past N days → close as stale + re-route to a distribution backlog,
   mirroring `content-starvation`); **never auto-close a genuine ops/infra ask**;
   emit a monitored `SOLEUR_*` stdout marker on SLA breach so the next occurrence
   self-reports to Better Stack (`hr-no-dashboard-eyeball-pull-data-yourself`).

## Key Decisions

| # | Decision | Rationale |
|---|---|---|
| D1 | **Not** a "replace the label" refactor | Label is load-bearing (`inngest-health:853`) and the finer taxonomy (`decision-challenge`, `content-*`) already exists — the job is to stop collapsing it, not to invent a new one. |
| D2 | Full contract, staged in the order above | Delivery fix alone recovers most of the loss for near-zero cost; later layers compound. Independent stages bound blast radius. |
| D3 | Auto-expire **dead classes only**; nag/escalate the rest; never auto-close ops asks | Operator decision (risk knob). `content-starvation` is the precedent for safe auto-close; genuine emergencies must never be silently closed. |
| D4 | Age + priority must be **legible per item** in the digest, not just implied | Answers Q2 directly: "age is itself a signal rather than invisible." |
| D5 | SLA breaches emit a `SOLEUR_*` marker | Self-reporting per `hr-no-dashboard-eyeball`; the operator is told, not asked to retrieve. |

## Open Questions (for /plan)

- **Q-A. SLA thresholds per class.** What age → escalate → expire windows per class
  (ops/infra: escalate only; content: expire at N days; decision-challenge: drop
  from harvest immediately)? Needs concrete day-counts.
- **Q-B. Delivery mechanism.** Is `--assignee` + GitHub notification sufficient, or
  does the operator need a push channel (email/Slack) for the weekly digest? The #8
  probe suggests assignee delivery was failing under the workflow token — confirm
  the token scope in the private repo can assign.
- **Q-C. Stricter harvest predicate.** Define exactly which label(s) the digest
  Section 4 harvests after de-pollution (e.g. `action-required AND NOT
  (decision-challenge OR content*)`), and update every producer that currently
  double-stamps.
- **Q-D. Cron home.** Does the lifecycle cron live in public `soleur`
  (`.github/workflows/scheduled-*.yml`) or the private `operator-digest` repo?
  Public keeps it with the other watchdogs; private keeps close authority off the
  public repo. Lean public (co-located with producers it must re-label).
- **Q-E. Backfill.** One-time triage of the existing 30: expire the 6 dead content
  chores, drop the 13 decision-challenges from the harvest, leave the ~11 genuine
  asks — so the first post-contract digest is credible.

## User-Brand Impact

- **Artifact:** the `action-required` operator-escalation channel + `operator-digest`
  Section 4 render.
- **Vector:** a genuine only-you-can-fix emergency (saturating disk, dead cron,
  expiring cert) is filed correctly, surfaced weekly, and *still* silently ignored
  because it is undelivered and buried in noise — the outage broadens unattended
  (exactly #4375: 1 cron → 8 while the escalation sat 57 days).
- **Threshold:** `single-user incident`.

Tagged **user-brand-critical** (auto, per #5175). The plan inherits
`Brand-survival threshold: single-user incident`.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

Assessment was **empirical/diagnostic-led** rather than leader-fan-out: the four
root causes were established directly from live workflow-run history, the digest
render, label counts, and assignee state, which settled the design more decisively
than strategic assessment would. Relevant-domain lenses applied inline:

### Engineering
**Summary:** Core surface. Touches `operator-digest/SKILL.md` §4 (render), a new/edited
scheduled lifecycle cron (label escalation + auto-expire), and every producer that
double-stamps `action-required` (`scheduled-inngest-health.yml`, content pipeline,
decision-challenge filer). Must add a monitored `SOLEUR_*` marker on SLA breach and
keep close-authority fail-safe (never auto-close ops asks).

### Product
**Summary:** The operator is non-technical; comprehension is the product here. A flat
age-blind list trains the reader to skim past the P0. Making age/priority legible and
cutting noise is the user-facing win, not a cosmetic one.

### Operations
**Summary:** The rot is dominated by ops escalations that broaden while unattended
(#4375, Hetzner cap, plaintext disk). The delivery + escalation fix is an operational
reliability improvement, not just a digest tweak.

## Session Errors

None material. Note for PR-body authors: `operator-digest` scheduling lives in the
**private** `jikig-ai/operator-digest` repo (`operator-digest.yml`), not in public
`soleur` — verify run history there with `gh run list -R jikig-ai/operator-digest`.
