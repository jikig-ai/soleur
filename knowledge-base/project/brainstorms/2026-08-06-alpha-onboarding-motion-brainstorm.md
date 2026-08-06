# Brainstorm: Alpha Onboarding Motion — Recording the Start of Active User Onboarding

**Date:** 2026-08-06
**Trigger:** Operator onboarding `2my8r9ry2t-wq/Skouer` as the first alpha tester, co-located with the Skouer founder in a coworking space.
**Lane:** cross-domain
**Brand-survival threshold:** single-user incident

---

## What We're Building

Two artifacts plus a set of updates to records that **already exist**:

1. **A validation record** marking the transition from pre-launch to *active user onboarding*, with Skouer as recruit #1 of 10.
2. **A repeatable per-tester onboarding runbook**, so testers 2–10 do not rediscover the process ad hoc.
3. **Updates to the existing Phase 4 protocol issues** (#1439–#1443) and the roadmap, rather than a parallel structure beside them.

## Why This Approach

**The premise check reframed the request.** The request read as greenfield ("record that we're starting onboarding"), but Soleur's roadmap already defines this exact motion as a sequenced five-stage validation protocol with open P1 issues:

| Roadmap row | Issue | Stage |
|---|---|---|
| 4.1 | [#1439](https://github.com/jikig-ai/soleur/issues/1439) | Recruit 10 solo founders |
| 4.2 | [#1440](https://github.com/jikig-ai/soleur/issues/1440) | Problem interviews (explicitly *no demo*) |
| 4.3 | [#1441](https://github.com/jikig-ai/soleur/issues/1441) | Guided onboarding, top 5 |
| 4.4 | [#1442](https://github.com/jikig-ai/soleur/issues/1442) | 2-week unassisted usage tracking |
| 4.5 | [#1443](https://github.com/jikig-ai/soleur/issues/1443) | Exit interviews + willingness-to-pay |

Creating a new "alpha cohort" structure beside these would orphan five open P1 issues and a roadmap phase. The correct move is to **advance the existing protocol** and record Skouer against it.

`Beta users` on the roadmap reads **0**. This work moves it to **1** — the first non-zero value in the product's history, which is why the record is worth getting right rather than jotting down.

## Key Decisions

| # | Decision | Rationale |
|---|---|---|
| D1 | Advance the existing Phase 4 protocol; do **not** create a parallel alpha-cohort structure | #1439–#1443 are open, P1, and milestone-tracked. A parallel structure orphans them. |
| D2 | Skouer is recorded as **recruit #1 of 10** against #1439 | Roadmap row 4.1. |
| D3 | Skouer counts against the **Claude-Code-user** allocation, not the non-CC quota | Their repo carries `CLAUDE.md`, `.agents/`, `skills/` (geocoder, press-reader, press-review-mentions) and a `knowledge-base/project/` tree — they are an existing Claude Code user. #1439's CMO constraint requires **≥3 of 10 to NOT be Claude Code users**; tracking the mix from tester #1 prevents discovering the violation at tester #10. |
| D4 | Today's session is **operator-driven CLI onboarding**, recorded against #1441 with an explicit deviation note | The hosted web platform (Concierge) is degraded with in-flight deploy issues, so the operator is driving onboarding personally in the CLI. This is simultaneously a dogfood of the onboarding experience itself. |
| D5 | Test surface is the **self-hosted CLI plugin** now; hosted web platform once functional | Operator decision. Gates what #1442 can measure — see D8. |
| D6 | **No third-party PII in git.** Knowledge-base records stay company-level (`Skouer`, repo URL). The named contact lives in the beta-CRM database only. | The beta-CRM LIA §46 is explicit: git-committed third-party PII is an Art. 17 erasure impossibility because git history is permanent. This is a load-bearing boundary, not a style preference. |
| D7 | GDPR posture: **Art. 13 governs a tester who signs up**; the LIA's Art. 14 pasteable notice line covers the CLI/no-signup case | Art. 14 is the *involuntary third party* path (data not obtained from the subject). An alpha tester who knowingly signs up is Art. 13, satisfied by the privacy policy at `accept-terms`. Skouer is CLI-first and never hits that flow, so the LIA's one-line notice applies — delivered in the alpha welcome message, not as any in-person ceremony. It goes into the runbook template once and is then automatic for testers 2–10. |
| D8 | Record that **#1442's metrics are only partially measurable on CLI** | #1442 tracks returns, KB growth, and non-engineering agent usage. On a self-hosted CLI plugin there is no server-side telemetry. *Partial mitigation:* the operator is a collaborator on the Skouer repo, so **KB growth is observable via git history** on their `knowledge-base/` tree. Returns and agent-mix are not. |
| D9 | The **beta-CRM contact write is a tracked gate, not a silent deferral** | Migration `126_beta_crm.sql:170-172` REVOKEs INSERT/UPDATE/DELETE from `PUBLIC, anon, authenticated, service_role`. Per ADR-102 there is **no service-role write pipeline by design** — writes go only through `auth.uid()`-pinned SECURITY DEFINER RPCs as the authenticated owner in the web platform. With that platform degraded, the write cannot be automated from CLI without defeating the security posture it exists to enforce. Recorded as a gate that fires when the platform returns. |
| D10 | Produce the **repeatable runbook now**, not at tester #2 | Skouer is #1 of 10; the process repeats nine more times. Writing it while the first run is live is the cheapest and most accurate moment. |

**Productize Candidate:** `soleur:alpha-onboard` — a skill wrapping the per-tester runbook (record contact, deliver notice, seed tracking, schedule the 2-week checkpoint). Deferred: run the runbook manually for testers 1–3 first and let real friction shape the skill, rather than encoding a guessed process.

## Non-Goals

- Building an alpha-cohort dashboard or tester-facing surface (ADR-102 explicitly defers tester-visible CRM surfaces; it would change the transparency posture).
- Fixing the Concierge/web-platform deploy issues. Recorded as context and as the gate on D9/D5, but out of scope here.
- Drafting alpha-tester terms or a DPA — see Open Questions.
- Backfilling the four not-yet-triggered protocol stages (#1440, #1442, #1443) with speculative content.

## Open Questions

1. **No agreement covers this relationship.** There are no alpha-tester terms and no DPA between Jikigai and Skouer. Two distinct exposures:
   - *Soleur → Skouer's data:* Skouer's product is a **venture database containing personal data about founders and investors** (French, Clever Cloud Postgres/PostgREST). If Soleur agents operate on that repo, Jikigai plausibly becomes a **processor of Skouer's third-party personal data**, which is a controller/processor question the beta-CRM LIA does not cover — it addresses the operator's notes *about testers*, not tester data Soleur processes.
   - *Skouer → Soleur:* no terms bound what the alpha tester may expect (support, uptime, data handling, confidentiality of a private repo).
   A `data-processing-agreement-template.md` and `side-letter-template.md` already exist in `knowledge-base/legal/`. **Recommend a follow-up issue before agents touch the Skouer repo in earnest.**
2. **When does the hosted platform become the test surface?** This gates D5 and D8 — #1442's usage tracking is only fully measurable once Skouer is on the web platform.
3. **Does the operator want the recruitment-mix constraint enforced mechanically** (e.g. a checklist gate at tester #7) or tracked in the runbook by hand?

## User-Brand Impact

- **Artifact:** the alpha-tester onboarding record + per-tester runbook, and the beta-CRM contact record the runbook prescribes.
- **Vector:** a tester's personal data written into git — permanent and un-erasable, defeating Art. 17 — or an alpha tester onboarded with no notice of what is recorded about them. Either is a trust breach against the product's *first* external user, at the moment the brand is least able to absorb one.
- **Threshold:** single-user incident.

## Domain Assessments

**Assessed:** Product, Legal, Engineering, Sales, Marketing, Operations, Finance, Support

Assessments were performed **inline by the orchestrator**, not via spawned domain-leader agents (this session runs under an operator constraint against agent fan-out). Recording this explicitly so the depth of these assessments is not over-trusted downstream — they are grounded in direct file reads (migration `126`, the beta-CRM LIA, `roadmap.md`, issues #1439–#1443, the Skouer repo tree) rather than independent domain review.

### Product

Skouer is recruit #1 of 10 against an already-defined protocol; the request is protocol advancement, not new structure. The recruitment-mix constraint (≥3 non-Claude-Code users) is the live risk and needs tracking from tester #1. `Beta users: 0 → 1` is the headline state change.

### Legal

Art. 13 governs a tester who signs up; the LIA's Art. 14 one-line notice covers the CLI/no-signup path — neither requires anything in person. The load-bearing constraint is **no third-party PII in git**. The genuine gap is upstream of the CRM: no alpha terms and no DPA exist, while Skouer's repo holds third-party personal data that Soleur agents may process.

### Engineering

The beta-CRM write path is `auth.uid()`-pinned and REVOKEd from `service_role` by design, so no CLI automation exists without breaking ADR-102's posture. The degraded web platform therefore gates the CRM record. Separately, CLI-only testing means #1442's server-side telemetry is absent; git history on the tester's own `knowledge-base/` is the one measurable proxy.

### Sales

Pipeline stage for Skouer is `evaluating` (0.5) under `STAGE_PROBABILITY` — past `qualified` (recruited and actively onboarding) but short of `committed` (no agreement, no willingness-to-pay signal). Stage transitions are append-only, so the entry stage should be set deliberately rather than defaulted to `new`.

### Marketing

#1439's mix constraint originates in CMO review. No external communication is in scope; the alpha welcome message is the only tester-facing copy, and it carries the Art. 14 notice line.

### Operations

The runbook belongs in `knowledge-base/engineering/operations/runbooks/`, matching 40+ existing runbooks. The 2-week checkpoint (#1442) needs a scheduling mechanism or it will be missed.

### Finance

No revenue implication at alpha. Break-even is 5 users at $49/mo against $223.39/mo COGS; #1443's willingness-to-pay signal is the first real input to that model.

### Support

No support channel is defined for alpha testers. For a co-located founder this is moot; for testers 2–10 recruited remotely it is a gap the runbook should name.

## Capability Gaps

1. **No alpha-tester terms or DPA.** Evidence: `ls knowledge-base/legal/` shows `data-processing-agreement-template.md`, `data-processing-agreements/` (anthropic, flagsmith only), `tenant-dpa-register.md`, and `side-letter-template.md` — templates exist, but no executed or drafted agreement for an alpha tester. Domain: Legal.
2. **No scheduling mechanism for the #1442 two-week checkpoint.** Evidence: `#1442` body defines the window but names no trigger; no cron or follow-through hook references it (`git ls-files | grep -iE 'alpha|tester'` returns nothing). Domain: Operations.
3. **No CLI-surface usage telemetry.** Evidence: `#1442`'s metrics (returns, KB growth, non-engineering agent usage) have no server-side source for a self-hosted plugin. Domain: Engineering/Product.
