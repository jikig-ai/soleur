---
title: "Legal-corpus defects — dead guards, self-contradictions, and published-mirror under-disclosure"
type: fix
date: 2026-08-10
issue: 7349
branch: feat-one-shot-7349-legal-corpus-defects
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# Legal-corpus defects — dead guards, self-contradictions, and published-mirror under-disclosure (#7349)

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
<!--
Phase 2.8 (Infrastructure-as-Code Routing Gate) reviewed and does not apply. This plan
provisions no infrastructure: no server, systemd unit, cron job, vendor account, DNS record,
TLS cert, secret, firewall rule, or monitoring webhook. Every edit is a markdown document, a
TypeScript literal, a shell gate script, or a knowledge-base record. The only "operator" steps
named are CLO legal rulings and CPO sign-off — human judgement calls that no IaC mechanism can
or should execute. No .tf file is touched and no apply is triggered.
-->


## Enhancement Summary

**Deepened on:** 2026-08-10
**Mandatory halts:** 4.6 User-Brand Impact — PASS (section present, threshold valid).
4.7 Observability — PASS (all five fields present and non-empty; `discoverability_test.command`
contains no `ssh`). 4.8 PAT-shaped variables — PASS (no matches). 4.9 UI wireframe — not
triggered (no UI-surface file; `.md`/`.ts`/`.sh` only). 4.10 Encryption Posture — not triggered
(no store, no new cross-component connection). 4.5 Network-outage — not triggered.
2.8 IaC routing — reviewed and acked (no infrastructure).

### Key improvements from review

1. **CPO sign-off granted, conditional on four corrections — all folded in.**
2. **A wrong figure withdrawn.** The plan claimed the `TC_VERSION` bump would interrupt "every
   tester". Measured: the sole tester is on the self-hosted CLI and never traverses
   `/accept-terms`. **Real-user blast radius is zero.** The overstated cost was itself a risk — it
   is the kind of number later cited to justify deferring a legal fix.
3. **"Tier 1 ⇒ bump" was wrong.** Tier 2 also bumps (PATCH), so this PR bumps regardless of how
   the CLO grades individual items. The "time the bump separately" option never existed.
4. **`gdpr-policy` carved back into scope (C3).** Deferring it wholly was self-contradictory — it
   was already in `Files to Edit` for B4 and E5 — and its canonical-only Art. 6(1) lawful-basis
   bullets are the *most severe* of the three verified under-disclosures. Deferring the worst
   instance while fixing the lesser ones would reproduce this issue's own thesis defect at the
   scope level. New Phase 3b ports them as a lockstep addition; the other ~60 lines stay deferred.
5. **A notice channel with no re-notice path (M1).** The bump is the only re-notice mechanism and
   it structurally cannot reach the one cohort that exists. New AC35 + a standing runbook step.
6. **E9's fix already had a house rule (AC37).** The brand guide mandates *soft floors* for
   component counts because the live site renders exact counts from the filesystem. Updating the
   numbers would reset the drift clock and guarantee E9 recurs; soft floors make the class extinct.
7. **A date refresh over stale counts is the thesis defect (C4).** The roadmap's `## Current State`
   milestone counts are 293 issues adrift. Refreshing only the date makes the section *look*
   verified. AC11 now requires syncing the counts or leaving the date alone.

### CLO review — six rulings made, and four of this plan's claims overturned

8. **PA-30 must be re-characterised in place, not re-homed.** Art. 30(2) requires naming a
   controller *other than* the processor, and Jikigai is the beta-CRM's only store owner. A
   re-home would drop six of PA-30's limbs — a **deletion gate 2 passes silently** — and orphan
   two citations inside a production migration that cannot be edited.
9. **Three of the nine T&C contradictions were misdiagnosed.** E2's forum conflict does not exist
   (the DPD has no forum clause; T&C and Disclaimer agree on France/Paris). E5's direction was
   backwards — the real conflict is intra-T&C. Two of E8's three limbs are not defects. All three
   came from the issue body and read as plausible.
10. **Two defects the plan missed**, both in `disclaimer.md`: a **factually false** "provided free
    of charge" premise (Stripe subscriptions exist), and an unqualified **direct-damages**
    exclusion that risks the whole limitation clause under Directive 93/13.
11. **AC19 was unreachable and the phase order deadlocked.** The AUP mirror renders
    `{{ stats.agents }}` through Eleventy and the canonical cannot, so zero normalised drift is
    impossible while a count sits in that sentence. E9 moved from Phase 5 to Phase 4.
12. **AC8 was unsatisfiable** — a repo-wide `SOC 2` grep legitimately returns third-party
    attestations and learnings. Rescoped to three files.
13. **A gate-invisible hazard in this PR's own scope.** The DPD carries a hard-wrapped scope block
    whose referent is *"The paragraph above"*; inserting a restored §2.3 item above it re-points
    the referent while **both gates stay green**, because the block's own line never changes.

### New considerations discovered

- Verified independently, not inherited: the DPD mirror lacks **six** §2.3 items, not one, and the
  published surface carries **10** dangling cross-references.
- PA-30's re-home has wider blast radius than filed — PA-32's lawful-basis cell cites it as
  *decisive internal precedent* for an Art. 6(1)(f) necessity argument.
- The `engineering/ops/` sweep's 8th hit is the learning file whose own subject is this exact
  carve-out; rewriting it would destroy the example.

## Overview

#7349 consolidates eleven pre-existing defects in the legal corpus, surfaced while researching
the #7331 controller/processor determination. Six of the eleven share one failure shape: **an
artifact that reads as coverage while providing none** — a guard whose predicate cannot match,
a gate over an empty set, a cross-reference to a missing section, a register row pointing at
the wrong issue.

Research for this plan **confirmed every filed item** and found the scope is materially larger
than filed on three of them. It also found four in-class defects the issue does not list.

The single most consequential correction: **the Eleventy mirror is the published document, and
the canonical is the internal record.** `eleventy.config.js` sets `INPUT = "plugins/soleur/docs"`,
`deploy-docs.yml`'s path filter covers only `plugins/soleur/docs/**`, no Next.js route serves
`docs/legal/**`, and the app's own links point at `https://soleur.ai/pages/legal/*.html`. So
"mirror drift" is not a copy falling behind a source — it is **the published legal notice
under-disclosing relative to the record**, which is an Art. 13/14 transparency question, not a
housekeeping one.

## Problem Statement

### Premise validation (Phase 0.6)

Every reference the issue cites was checked against live state:

| Cited | Claim | Verdict |
|---|---|---|
| `#7331` | surfacing issue | CLOSED — holds |
| `#7342` | the PR that surfaced these | MERGED — holds |
| `#736` | tracks "T&C blanket statement contradictions" | **STALE — confirmed.** State CLOSED (by PR #880); actual title *"legal: update Terms & Conditions for web platform cloud services"*. Different subject. The contradictions are genuinely untracked. |
| `#4330` | treats the 90-day SOC 2 form as live | CLOSED — holds |
| `#7387` / PR #7388 | landed the two write-time gates | MERGED at `bab29e651` — holds |

**No prior art exists for the T&C contradictions.** Confirmed by `git log` on the canonical and a
repo-wide grep for prior enumerations. This plan enumerates them for the first time.

### A caution inherited from #7387

`knowledge-base/project/learnings/2026-08-10-every-gate-i-built-passed-85-green-assertions-and-had-two-fail-opens.md`
records that the immediately-preceding legal PR **reproduced an issue-body list under the word
"measured" without checking it**, and two of six items were wrong. That list was about *this*
issue. Accordingly:

- Every count and every missing item in this plan was **re-derived in this session**, not
  inherited. Where a number came from a subagent, it is marked as such.
- The plan's own claims are stated with the command that would falsify them.
- The issue body's `#7349` comment table listing per-doc drift is itself **incomplete**: it lists
  five docs summing to 197 lines, but the corpus total is 220. `cookie-policy` (4),
  `corporate-cla` (12) and `individual-cla` (7) were omitted from it. Corrected below.

### Research Reconciliation — issue claims vs. codebase

| Issue claim | Reality (verified this session) | Plan response |
|---|---|---|
| DPD mirror "lacks §2.3(ad)" | Mirror lacks **six** items: `(p) (w) (x) (y) (z) (ad)`. Canonical carries 29 sub-items, mirror 23. Re-derived independently this session. | Port all six; scope widened |
| "a dangling cross-reference to it" | **10 dangling cross-reference instances** on the published surface: `(ad)`×1, `(p)`×2, `(w)`×3, `(x)`×3, `(y)`×1 | Generalised AC: zero dangling `2.3(x)` refs on either surface |
| AUP mirrors "materially different" | Confirmed. 18 drift lines; divergence is **bidirectional** (mirror-only text AND canonical-only text) | Reconcile both directions, not a one-way copy |
| DPD drift is the six items | 56 drift lines / 17 hunks. Also: two §4.2 processor rows, two Chapter V transfer bullets, a gutted §5.3, missing Art. 17 limbs, a truncated §2.3(i) | Full DPD resync |
| compliance-posture `#736` row | Confirmed stale on both status and subject | Replace with an accurate row pointing at this plan's enumeration |
| `engineering/ops/` cited once | **13 live citations across 7 files** | Repo-wide sweep with historical-artifact carve-out |
| T&C contradictions | **9 confirmed, 6 ambiguous** — none previously tracked | Enumerate all; fix the 9 |

### Confirmed defect inventory

#### A. Guards that cannot fire

- **A1 — `tenant-dpa-register.md` signed-row guard is structurally dead.** The guard greps
  `status: dpa-signed`; the status vocabulary in the same file defines a bare `dpa-signed` with
  no `status:` prefix. The predicate cannot match. The register also carries **no data rows**, so
  the guard has never had an input. The file's own prose repeats the bogus `status: `-prefixed
  form, so the defect is in three places, not one.
- **A2 — `tenant-provisioning.md` gate is vacuously true.** The gate is
  `test -s <register> && grep -c '^|' <register>` against a `>= 3` threshold. The empty register
  already returns **3** — table header, separator row, and a `| _(none yet)_ |` placeholder. The
  gate passes today and will keep passing until the first real row, which is the moment it
  matters.
- **A3 (not in the issue) — a second vocabulary mismatch in the same runbook.** The teardown path
  writes status `aborted-provisioning` while the vocabulary defines
  `aborted-provisioning-at-step-N`. Identical class to A1.
- **A4 (not in the issue) — the TC_VERSION seed-parity gate has a hole, and it is currently
  drifted.** `check-tc-document-sha.sh` checks `SEED_SCRIPTS=(seed-dev-users.sh seed-qa-user.sh)`.
  `apps/web-platform/scripts/seed-live-verify-user.sh` is **not in the list** and sits at
  `TC_VERSION="2.3.0"` against a canonical `2.4.0` — despite its own comment saying it must match.
  The synthetic prod principal it provisions gets the middleware redirect-to-`/accept-terms` loop.
  A parity gate whose file list omits a real producer is exactly this issue's thesis defect.

#### B. Contradictions and stale records

- **B1 — DPA template §10.3 contradicts itself on SOC 2, across four sites.** §10.3 states
  Jikigai does **not** hold a SOC 2 Type II and "will evaluate"; a later commitments table says
  *"Initiate SOC 2 engagement within 90 days of first executed DPA (§10.3 commitment)"*; a third
  site refers to "the commitment in §10.3"; and `compliance-posture.md` carries the 90-day form as
  a live commitment. The alpha-tester processing annex agrees with the **no-commitment** reading.
  Both positions are in an instrument that would be executed with a customer.
- **B2 — `compliance-posture.md` register rows are stale.** The `#736` T&C-contradictions row is
  struck through and self-annotated stale but was never replaced with anything accurate. Separately
  the document-inventory rows carry Last-Updated dates that no longer match the documents (T&C row
  vs. the canonical's actual date; same class for AUP, Cookie Policy, Disclaimer, both CLAs), and
  the table has **no version column at all**, so `TC_VERSION = 2.4.0` is not tracked anywhere in
  the posture document.
- **B3 — `roadmap.md` row 4.1 contradicts the same file.** Row 4.1 reads "Not started" while the
  narrative section records recruitment underway with the first founder onboarded. The
  `## Current State` heading also carries a date months older than the newest fact in the file.
- **B4 — PA-30 declares Jikigai a processor but sits in the Art. 30(1) controller register.** A
  30(1) record is scoped to controller capacity by its own preamble. `article-30-2-register.md`
  (created by #7331/#7342) is the correct home. **Re-homing has more blast radius than the issue
  implies** — PA-30 is referenced from the DPD §2.3(ad) item, from `gdpr-policy.md` on both
  surfaces, from `compliance-posture.md`, and — found this session — **from PA-32's own
  lawful-basis reasoning inside `article-30-register.md`, where PA-30 is cited as the "decisive
  internal precedent"** for rejecting git-committed PII as an Art. 17 impossibility, plus the
  counsel-review question that rests on that citation. A re-home that breaks those references
  weakens a live Art. 6(1)(f) necessity analysis, so the sweep is load-bearing, not cosmetic.

#### C. Published-mirror under-disclosure

Measured per pair with the gate's own normaliser (`scripts/lib/legal-normalise.sh`) — the same
implementation the ratchet uses, so these numbers are the ones the gate sees:

| Pair | Drift lines | Character |
|---|---|---|
| `gdpr-policy` | 63 | substantive — canonical-only Art. 6(1) lawful-basis bullets |
| `privacy-policy` | 58 | substantive |
| `data-protection-disclosure` | 56 | substantive — see C2 |
| `acceptable-use-policy` | 18 | substantive — see C1 |
| `corporate-cla` | 12 | unclassified |
| `individual-cla` | 7 | unclassified |
| `cookie-policy` | 4 | unclassified |
| `disclaimer` | 2 | cosmetic — one autolinked email address |
| `terms-and-conditions` | 0 | clean — the one doc already body-equivalence guarded |
| **total** | **220** | |

- **C1 — AUP, 18 drift lines, divergence in both directions.** The canonical frames the
  knowledge-base sharing prohibition as **acts** ("you must not **Share** documents containing…");
  the published mirror reframes it as **document properties** ("**Contain** confidential…").
  The canonical permits "explicit consent **or another lawful basis under applicable law**"; the
  published version **drops the alternative lawful basis**, making the published policy stricter
  than the record. The canonical cross-references "Section 4.2 (Harmful or Illegal Content)"; the
  mirror replaces the link with freestanding text. The mirror adds *"Violation of this section may
  result in share-link revocation"* with **no counterpart in the canonical**. The canonical carries
  a workspace-logo paragraph absent from the mirror. Two published documents claim to be the same
  policy and are not.
- **C2 — DPD, 56 drift lines across 17 hunks.** The published notice omits: six §2.3 processing
  activities — `(p)` LinkedIn Company Page publication, `(w)` delegated-credential prompt routing,
  `(x)` team activity feed, `(y)` knowledge-base file metadata, `(z)` workspace logo image,
  `(ad)` owner-private beta-tester/prospect CRM; two §4.2 sub-processor rows (LinkedIn Ireland,
  Microsoft Ireland); two Chapter V transfer bullets; an Art. 17 carve-out; four Art. 17 erasure-
  cascade limbs; and a §5.3 data-subject-rights block reduced from a full description to stubs —
  including the removal of the self-serve export route at `/dashboard/settings/privacy`, which is
  the Art. 15/20 fulfilment path.
- **C3 — 10 dangling `§2.3(x)` cross-references on the published surface.** Enumerated this
  session by set-differencing the cross-references against the items that exist **on the same
  surface**. Canonical: zero dangling. Mirror: `(ad)`×1, `(p)`×2, `(w)`×3, `(x)`×3, `(y)`×1.
- **C4 (not in the issue) — a user-facing link to an unserved path.**
  `apps/web-platform/lib/messages/trust-tier-copy.ts` tells a user whose content was revoked for an
  AUP violation to "See the policy at `/docs/legal/acceptable-use-policy`". The web platform serves
  no such path (`apps/web-platform/public/docs` does not exist; no app route matches). The real
  published URL, per `apps/web-platform/infra/seo-bulk-redirects.tf`, is
  `https://soleur.ai/legal/acceptable-use-policy/`. A user told *why* they were sanctioned is sent
  to a 404.

#### D. Coverage gaps

- **D1 — `tenant-offboarding.md` has no non-tenant alpha-tester exit path.** The real path exists,
  in the alpha-tester onboarding runbook's offboarding section, with **no cross-link from the
  tenant runbook**. An operator following the tenant runbook finds nothing and cannot tell whether
  the case is uncovered or covered elsewhere.
- **D2 — `engineering/ops/` is cited 14 times across 8 files.** The directory does not exist; the
  correct path is `engineering/operations/`. Filed as a single citation in
  `tenant-offboarding.md`. Measured this session:

  | File | Disposition |
  |---|---|
  | `knowledge-base/engineering/operations/runbooks/tenant-offboarding.md` | fix |
  | `knowledge-base/engineering/operations/runbooks/vendor-pin-drift-resolution.md` | fix |
  | `knowledge-base/engineering/operations/runbooks/sentry-support-ticket-drafts.md` | fix |
  | `knowledge-base/engineering/operations/runbooks/plausible-dashboard-filter-audit.md` | fix |
  | `knowledge-base/engineering/operations/runbooks/ruleset-bypass-drift.md` | fix |
  | `knowledge-base/engineering/operations/runbooks/codeql-bot-coverage.md` | fix |
  | `knowledge-base/engineering/operations/post-mortems/dashboard-error-postmortem.md` | fix |
  | `knowledge-base/project/learnings/best-practices/2026-06-03-path-rename-sweep-exclude-own-migration-artifacts.md` | **carve out** |

  The last entry is a learning file that cites the old path *as its own worked example* — and its
  subject is precisely "a path-rename sweep must exclude its own migration artifacts". Rewriting
  it would destroy the example. It must be carved out of both the sweep and the residual-zero AC.

#### E. T&C contradictions — first enumeration

Nine confirmed contradictions, six ambiguities, two version defects. Each is a genuine
incompatibility between two statements in force, not a wording preference. Several are
**cross-document**, which is load-bearing for how this ships (see Alternatives Considered).

**CLO-adjudicated.** Six of the nine held as filed; **three were misdiagnosed by this plan's first
draft** and are corrected below; **two further defects** were found that the first draft missed.
The corrections are recorded rather than quietly absorbed — they are the same
inherited-claim class the plan's own caution section warns about, committed by the plan itself.

| # | Contradiction | Verdict | Sites |
|---|---|---|---|
| **E1** | Liability cap: T&C §11.2 caps at greater of (12-month spend, EUR 100); `disclaimer.md` §3.2 caps at 12-month spend and asserts *"the Platform is provided free of charge, this amount is zero (EUR 0.00)"* | **REAL — and worse than filed.** T&C governs (it is the instrument with an acceptance record; the Disclaimer has none) | T&C §11.2, `disclaimer.md` §3.2 |
| **E1b** | **NEW —** the Disclaimer's premise is **factually false**: the Web Platform sells subscriptions via Stripe Checkout (T&C §5), so "provided free of charge" is wrong on its face | **REAL, missed by the first draft** | `disclaimer.md` §3.2 |
| **E1c** | **NEW —** `disclaimer.md` §3.1 excludes **direct** damages while T&C §11.1 excludes only indirect. An unqualified direct-damages exclusion against an EU consumer is the clause in this corpus most likely to be struck under Directive 93/13 Annex 1(b) — and its presence risks the whole limitation | **REAL, missed by the first draft** | `disclaimer.md` §3.1 |
| **E2** | ~~Governing law / forum differs between the T&C and the DPD~~ | 🔴 **HALF NOT REAL.** Measured: the DPD contains **no governing-law and no forum clause at all**. T&C §15.1/§15.2 and `disclaimer.md` §8.1/§8.2 both say France / exclusive jurisdiction of Paris — they **agree**. The real defect is the surviving half: **§16.1 is a bare entire-agreement clause with no order of precedence**, so E1's genuine conflict has no resolution rule | T&C §16.1 |
| **E3** | Unscoped plugin-local absolutes | **REAL, CONFIRMED.** Measured `plugin-local`/scope-block occurrences: DPD 12, gdpr-policy 9, AUP 4, disclaimer 2, privacy-policy 1, **T&C 0**. The existing Plugin-vs-Web-Platform sentences do **not** reach the defect: operator-assisted sessions run *the Plugin* on a Jikigai machine, so §4.1's "does not… store your data on remote infrastructure controlled by us", §4.2's "through your own API keys", and §8.1's "remain on your local machine" are each false in that configuration — the one recorded in Art. 30(2) P-1 | T&C §§4.1, 4.2, 8.1 |
| **E4** | T&C §8.1b names four processors; the DPD and Art. 30 register additionally disclose **Anthropic PBC (US)**, Flagsmith, Cloudflare R2, LinkedIn Ireland, Microsoft Ireland | **REAL.** Anthropic's absence is the serious one — it is the primary recipient of *message content*, and §8.1b purports to enumerate what the Web Platform processes. **Fix: stop enumerating in the T&C** (two enumerations is what produced the divergence) but add Anthropic explicitly | T&C §8.1b |
| **E5** | ~~T&C asserts controller over "all personal data" while the DPD/GDPR Policy carve out the team-workspace case~~ | 🔴 **MISDIAGNOSED — direction was backwards.** T&C §3b.1 says the **Workspace Owner** is controller, which *matches* DPD §2.1b(a); `compliance-posture.md` already adjudicated this as "no contradiction". Fixing as filed would have edited the wrong document. **The real contradiction is intra-T&C:** §3b.1 makes the Owner controller of "**all** personal data", while §3b.2 says each Co-Member retains Arts. 15–22 rights **against Jikigai** — rights that run against a *controller*. If "all" is true, §3b.2 is void. "All" also sweeps in Co-Member account data and the 10-year invoice records under Code de commerce L123-22 | T&C §3b.1 ↔ §3b.2 |
| **E6** | Processor status asserted in the present tense while no Art. 28(3) instrument is executed | **REAL.** Art. 28(3) makes a processor relationship exist *only* under a written contract. **Fix: supply the missing instrument in the T&C itself** (DPA-by-incorporation, standard SaaS practice, strictly more protective than the current gap) | T&C §3b.1, §8.1c; DPD §2.1b(a) |
| **E7** | Share links described as processor-capacity processing | **REAL, sharper than filed.** PA-4 sits in the Art. 30(1) **controller** register with full controller limbs including unauthenticated viewers' IP addresses. Register and notice say controller; contract says processor. **Controller governs** — the serving, IP logging, revocation semantics and no-analytics choices are all Jikigai-determined and nobody instructs them | T&C §8.1c |
| **E8** | BYOK joint vs sole controllership; side letter mandatory vs optional; AUP cross-references a nonexistent T&C section | 🔴 **TWO OF THREE LIMBS NOT REAL.** (a) *Dangling cross-reference* — **FALSE**: every T&C section referenced from any legal document (`3a.7`, `3b`, `3b.1`, `3b.3`, `3b.4`) resolves. Zero dangling. **Do not "fix" a non-defect.** (b) *Mandatory vs optional* — **FALSE**: these are two different instruments, and the AUP says so in the same sentence — §5.6 mandates the **Delegation Consent Side Letter**, *"distinct from the workspace co-member Side Letter in Section 5.5"*, which §3b.4 makes optional. (c) *Joint vs sole controllership* — **REAL**, same root as E5 | T&C §3b.1, AUP §5.6 |
| **E9** | Component counts stated as fixed numbers | **REAL.** Measured today: **68** agent files, **95** skills, **9** domains — against "45 AI agents", "45 skills", "five domains". **Fix: remove the counts, do not restate them** (converges with CPO AC37) | T&C §4, AUP §2, `privacy-policy.md` |

**E-amb1..6** — six further passages where two readings are available but neither is clearly in
force. These are **enumerated, not fixed**: they are recorded in the enumeration artifact for CLO
adjudication so a future reader is not left to rediscover them.

**Version defects:** `TC_VERSION = 2.4.0`; `TC_BUMP_METADATA.lastUpdated = "July 2, 2026"`; the
canonical's own Last-Updated line; and the `compliance-posture.md` row must all agree and
currently do not (B2). Plus A4.

## User-Brand Impact

Ordered by determinism — the first bullet is product-triggered and 100% reproducible, and is what
carries the threshold. The rest are real but require the user to go looking.

- **If this lands broken, the user experiences (C4 — the one that needs no investigation):** they
  are sanctioned for an acceptable-use violation and the enforcement message itself sends them to
  a 404. `trust-tier-copy.ts` renders "See the policy at `/docs/legal/acceptable-use-policy`" and
  the web platform serves no such path. Zero investigative effort, fully deterministic, and it
  lands at the exact moment the user is most adversarial. **One sanctioned user, one 404, one
  incident.**
- **If this lands broken, the user experiences (2):** a published Data Protection Disclosure at
  `https://soleur.ai/pages/legal/data-protection-disclosure.html` that fails to tell them their
  knowledge-base file metadata, team activity feed, workspace logo, delegated prompt routing, and
  beta-CRM record are processed at all, and points them at five section letters that do not exist
  in the document they are reading.
- **If this lands broken, the user experiences (3):** a Terms & Conditions capping Jikigai's
  liability at a fixed sum while the Disclaimer they also accepted caps it at zero — two
  simultaneously-in-force instruments giving different answers to "what am I owed if this breaks".
- **If this leaks, the user's data is exposed via:** no new exposure vector — this plan publishes
  *disclosure of processing that already happens*. The exposure being remediated is the inverse:
  processing that occurs **without** the Art. 13/14 notice that makes it lawful to occur.
- **Brand-survival threshold:** `single-user incident`

An Art. 13/14 transparency deficiency is established by **one** data subject's Art. 15 request;
volume changes the fine, not the finding. CPO sign-off obtained at plan time (conditional —
see Domain Review); `user-impact-reviewer` runs at review time.

## Proposed Solution

Fix all eleven filed items plus the four in-class defects found during research, in one PR,
phased so the highest-consequence work lands against a verified baseline. Then **convert each fix
into a ratchet** so the class cannot silently recur: activate canonical↔mirror body-equivalence
enforcement for every document this PR brings into agreement.

Deliberately **out of scope**, with a successor issue filed in the same PR: the pre-existing
mirror drift in `gdpr-policy` (63), `privacy-policy` (58), `corporate-cla` (12), `individual-cla`
(7) and `cookie-policy` (4). Rationale in Alternatives Considered.

## Technical Approach

### The write-time gate landscape

Five gates bind this PR. Four are required status checks. Getting these wrong is the single
largest execution risk, so they are specified before the work.

| Gate | Where | What fails |
|---|---|---|
| **SHA pin** — `tc-document-sha-guard` | `apps/web-platform/scripts/check-tc-document-sha.sh` | Editing any `docs/legal/<doc>.md` without refreshing its SHA literal. **Unconditional** for the 8 notice docs (`LEGAL_DOC_SHAS`); the T&C has a `TC_VERSION`-bump bypass. Also enforces seed-script `TC_VERSION` parity and, for docs listed in `BODY_EQUIVALENCE_DOCS`, normalised canonical↔mirror body equality. |
| **Gate 1 — scope-block referent agreement** | `scripts/lint-legal-scope-block-placement.sh` | An **added** line asserting plugin-local scope whose declared referent is larger than the plugin-local text. Added-lines-only ratchet. Exit `0`/`1`/`2` — never a vacuous 0. |
| **Gate 2 — mirror-drift ratchet** | `scripts/lint-legal-mirror-drift-baseline.sh` | Drift that **grows, reorders, or changes content** relative to the merge base. Reduction always passes. Lockstep edits pass. **Editing a currently-drifting line in place, on one side, into a third form FAILS** as `CONTENT CHANGED`. |
| **Cross-document lockstep** | `.github/workflows/legal-doc-cross-document-gate.yml` | Only fires when a DSAR surface file is touched. **This PR touches none — trivially passes.** |
| **Consistency suite** | `apps/web-platform/test/legal-doc-consistency.test.ts` | Heading-sequence parity (all 9 docs, already enforced), Last-Updated parity, and sentinel-string presence on both surfaces. |

Both gates are green on the clean tree — verified this session:

```
$ bash scripts/lint-legal-scope-block-placement.sh --base origin/main   # exit 0
$ bash scripts/lint-legal-mirror-drift-baseline.sh --base origin/main   # exit 0
  legal mirror drift: 9 pair(s) checked, drift is within the baseline.
```

**The three ways this PR can trip a gate, and the discipline for each:**

1. **Resyncing a drifting line by rewriting it.** Gate 2 reads that as `CONTENT CHANGED` and
   fails. The correct move is always to make the two surfaces **identical**, which removes the
   drift-line pair from the sequence entirely and passes as a strict reduction. Never rewrite a
   drifting line into a third form on one side only.
2. **Porting a scope block into a mirror.** The corpus is dense with
   `**Scope.** This section describes **plugin-local processing** …` blocks. Every one ported into
   a mirror is an **added line** that gate 1 will classify. They pass today only because each
   carries its negative delimiter (`must not be read as covering it`) **on the same line** —
   arm (c) discharges. A ported block that gets hard-wrapped, or that lands in a section carrying
   a cloud marker with a section-scoped referent, will fire.
   **Known trap:** `docs/legal/gdpr-policy.md` contains one scope block that *is* hard-wrapped,
   unlike every sibling. Its negative delimiter is on a later line. If that document is ever
   resynced, that block will fire arm (c). Recorded in Sharp Edges; it is in the deferred set.
3. **Adding to E3's scope-block sweep.** E3 requires *adding* scope blocks to the T&C — the exact
   input gate 1 exists to police. Each added block must carry a referent no larger than the
   plugin-local text and its negative delimiter on the same line.

**A gate firing is signal to satisfy it.** No arm toggle, no `--base` widening, no
`BODY_EQUIVALENCE_DOCS` removal, no baseline regeneration used to launder a failure. The one
legitimate baseline write is the post-resync refresh in Phase 6, which *lowers* the frozen drift.

### Direction of authority

Because the mirror is what is published and the canonical is the internal record, "resync" is not
a mechanical copy. For each divergence the CLO must decide which text is **correct**, and then
both surfaces carry that text:

- Where the canonical is right and the mirror omits (the six DPD items, the AUP logo paragraph):
  **port canonical → mirror**. Canonical unchanged ⇒ no SHA refresh needed for that document.
- Where the mirror is right or carries text worth keeping (the AUP share-link revocation
  sentence): **port mirror → canonical**, which *does* require a `LEGAL_DOC_SHAS` refresh.
- Where **neither** is right (the AUP consent-only clause, which drops a lawful basis the GDPR
  provides): draft new text and land it on both surfaces in lockstep.

### Implementation Phases

#### Phase 0 — Preconditions and baseline (no edits)

- Re-run both gates and the SHA guard on the clean tree; record exit codes and the per-pair drift
  table as the measured baseline the ACs will diff against.
- `sha256sum docs/legal/*.md` and record; this is the before-picture for every SHA refresh.
- Re-derive the DPD §2.3 item sets and the dangling cross-reference set with the commands in
  Test Scenarios, and confirm they match this plan. **If any number disagrees, stop and correct
  the plan before editing** — the plan's numbers are claims, not permissions.
- Confirm the deferred-set drift numbers **and their character** — not just the counts (CPO C3).
  The C table marks `privacy-policy` (58) "substantive" with no character description, and the
  CLAs and `cookie-policy` "unclassified". **If `privacy-policy` carries an under-disclosure of
  the same class as `gdpr-policy`'s Art. 6(1) bullets, the split decision changes** — and that
  must be known before Phase 3, not after merge. The successor issue must require classification,
  not merely resync.

#### Phase 1 — Guards that cannot fire (A1–A4)

Fix the predicate, then **prove the guard can reach its input and fires on a planted defect** —
per the #7387 learning, verifying detection without verifying reachability is how the original
defect shipped.

- A1: reconcile the guard predicate and the status vocabulary to one form; fix the same bogus
  form in the file's prose. Decide explicitly which form is canonical rather than making the grep
  match the prose by accident.
- A2: make the gate fail-closed on an empty register. A count threshold that the empty-state
  placeholder already satisfies is not a gate. Either assert on data rows specifically, or assert
  the empty state explicitly and distinctly from the populated one.
- A3: reconcile `aborted-provisioning` with `aborted-provisioning-at-step-N`.
- A4: add `seed-live-verify-user.sh` to `SEED_SCRIPTS` **and** correct its `TC_VERSION` to the
  canonical value. Order matters — adding it to the list while it is drifted turns the gate red.
- Add a test that each guard fires on a planted defect **and** that a run against the real corpus
  reaches a non-empty input. A `MIN_ASSERTIONS` floor so a neutered suite cannot report green.

#### Phase 2 — Stale records and register shape (B1–B4)

- B1: **CLO decides the SOC 2 position first**, then all four sites carry it. Do not fix three
  sites to match a fourth chosen by proximity. The alpha-tester annex already agrees with the
  no-commitment reading, and #4330 treats the 90-day form as live — that tension is the decision,
  and it belongs to the CLO.
- B2: replace the struck-through `#736` row with an accurate row pointing at this PR's T&C
  enumeration artifact; refresh the stale Last-Updated dates; add a version column so
  `TC_VERSION` is tracked in the posture document at all.
- B3: correct roadmap row 4.1. Verified live: `#1439` is OPEN on the Phase 4 milestone, and the
  correct state is **"In progress — 1 of 10"** (tester #1 onboarded 2026-08-06 on the self-hosted
  CLI; mix is 1 Claude-Code user / 0 non-CC against #1439's `≥3 of 10 non-CC` requirement).
  **CPO C4 — do not refresh the `## Current State` date alone.** That section's milestone counts
  are themselves stale against the live API (Phase 4: roadmap 81/200 vs live 89/206; Post-MVP:
  roadmap 710/1283 vs live **1003/1549** — a 293-issue drift). Refreshing the date over a stale
  count produces a section that *looks* freshly verified and is not — this issue's thesis defect,
  committed by the PR that fixes it. **Either sync the counts or leave the date alone.** Syncing
  is preferred and is cheap.
- B4: 🔴 **RE-CHARACTERISE IN PLACE. The re-home is overruled by CLO review.** Four reasons:
  1. **Art. 30(2)(a) requires naming "each controller on behalf of which the processor is
     acting."** The beta-CRM is owner-private and `user_id`-scoped, and its only store owners
     today are Jikigai personnel. A `P-2` record would have to name Jikigai as its own controller.
     Art. 28 presupposes two persons. `P-1` works precisely because it names a real third party.
  2. **Jikigai determines purposes and means today** — the 24-month `pg_cron` horizon, Anthropic
     PBC as the agent-reasoning recipient, the DSAR export chain, `crm_erase_contact`. None is
     instructed. That is Art. 4(7) controllership.
  3. **The corpus already anticipated this trigger and it has not fired.**
     `audits/2026-07-counsel-review-6172.md` names "first arms-length / non-Soleur tenant becomes
     a store owner" as the re-evaluation trigger.
  4. **Re-homing is a deletion of accurate record that gate 2 passes silently.** Art. 30(2)
     carries no purposes, no data-subject categories, no personal-data categories, no retention
     and no DSAR limbs — so PA-30's limbs (a)–(c) and (f)–(h) would be dropped. And
     `apps/web-platform/supabase/migrations/126_beta_crm.sql` cites PA-30 twice in a migration
     **already applied to production**; its body cannot be edited, only superseded.

  **Do instead:** amend PA-30's role sentence in place — Jikigai is controller *as it runs today*
  because it is the only store owner; the roles change on the first arms-length store owner, at
  which point an Art. 28(3) instrument is owed *before* processing and a `P-2` record opens. Add a
  **reservation stub** to `article-30-2-register.md` §Register maintenance recording `P-2` as
  reserved for that trigger.

  **The referrer sweep is still required** — the role sentence changes even though the location
  does not — and is wider than filed: `article-30-register.md` (the record, PA-32's lawful-basis
  cell, Register-Maintenance item 9); `legitimate-interest-assessments/2026-07-07-beta-crm-lia.md`
  ×3, including *"full list in PA-30 §(g)"* which **would have broken** on a re-home since
  Art. 30(2) has no (g); `.../2026-07-31-claude-eval-fleet-and-ci-lia.md` ×3;
  `compliance-posture.md` ×3; `server/tool-tiers.ts`, `server/dsar-export-allowlist.ts`,
  `server/dsar-export.ts`; `migrations/126_beta_crm.sql`; DPD §2.3(ad) + mirror;
  `gdpr-policy.md` §3.13 + mirror. **Carve out** `audits/2026-07-counsel-review-6165.md` and
  `-6172.md` — point-in-time counsel records, same class as AC27's carve-out.

#### Phase 3 — Published-mirror under-disclosure: DPD (C2, C3)

The largest and highest-value phase. Bring the published DPD into agreement with the record:

- Port the six missing §2.3 items verbatim from canonical.
- Port the two §4.2 sub-processor rows, the two Chapter V transfer bullets, the Art. 17 carve-out
  and the four erasure-cascade limbs.
- Restore §5.3 to the canonical text, **including** the `/dashboard/settings/privacy` self-serve
  export route — this is the Art. 15/20 fulfilment path and its absence is one of the three
  CLO-verified under-disclosures.
- Restore the truncated §2.3(i) and the §2.3 roll-call entry for `(p)`.
- Confirm zero dangling `2.3(x)` cross-references remain **on either surface**.
- 🔴 **§2.3(ad) is the one item that must NOT be ported verbatim.** Phase 2's B4 changes its
  controller/processor characterisation, and Phase 3 runs after Phase 2 — so publishing the
  canonical text as-is would tell users the "operator" is controller of a store whose only owner
  is Jikigai. Restate the role sentence first, then publish. Sequence this explicitly.
- 🔴 **A gate-invisible hazard the first draft missed.** `docs/legal/data-protection-disclosure.md`
  contains a hard-wrapped scope block whose referent is *"The paragraph above"*. **Inserting a
  restored §2.3 item between that paragraph and the block silently re-points the referent at
  different text.** The block's own line is unchanged, so gate 1 (added-lines-only) never sees it
  and gate 2 sees no drift change. The first draft named only `gdpr-policy.md`'s hard-wrapped
  block as a trap and treated the DPD as safe — but the DPD carries the same shape **and is in
  this PR's scope**. Verify every scope block adjacent to an insertion point **by reading**, not
  by gate.
- 🔴 **Porting is textually a copy but legally a first publication.** AC34 covers claims the PR
  adds to a legal document; it does not reach a canonical→mirror copy. Re-verify each of
  `(p)(w)(x)(y)(z)(ad)` against the live implementation before publishing — especially **(z)**
  workspace-logo upload and **(w)** delegated-credential routing (`BYOK_DELEGATIONS_ENABLED`),
  whose flags may have moved since authorship. This is the PR #4353/#4558 drift class.

#### Phase 3b — GDPR Policy lawful-basis carve-back (CPO C3)

- Port the canonical-only **Art. 6(1) lawful-basis bullets** into the published `gdpr-policy`
  mirror as a targeted **lockstep two-surface** addition — the same technique B4 uses, which
  passes gate 2 without a full resync. This is the most severe of the three CLO-verified
  under-disclosures and is an Art. 13(1)(c) defect of the same class this PR exists to fix.
- Do **not** attempt the remaining ~60 `gdpr-policy` drift lines, and do **not** add the document
  to `BODY_EQUIVALENCE_DOCS`. Both stay with the successor issue — notably the hard-wrapped
  scope block that trips gate 1 arm (c) (see Sharp Edges).

#### Phase 4 — Published-mirror under-disclosure: AUP (C1) and the 404 (C4)

- Reconcile §4.6 in **both directions** per the direction-of-authority rule. The consent-only
  clause is the one where neither side is right: the published text drops "or another lawful basis
  under applicable law", which narrows the user's position below what the GDPR provides. New text,
  both surfaces.
- Restore the canonical cross-reference to §4.2 rather than the mirror's freestanding paraphrase.
- Decide the share-link revocation sentence (mirror-only) and the workspace-logo paragraph
  (canonical-only): each either lands on both surfaces or neither.
- 🔴 **Execute E9 HERE, not in Phase 5 — AC19 is otherwise unreachable.** The AUP *mirror* renders
  `{{ stats.agents }}` / `{{ stats.skills }}` through Eleventy; the canonical is not
  Eleventy-processed and cannot. So the two surfaces can **never** reach zero normalised drift
  while a count appears in that sentence, whatever the count says. **E9's count-free prose is a
  precondition of AC19**, and AC19 is a precondition of the Phase 6 `BODY_EQUIVALENCE_DOCS`
  activation. Left in Phase 5, the ordering deadlocks and turns a required check red.
  Use soft floors, not refreshed numbers (AC37).
- Reconcile the changelog abridgement. The mirror drops the §5.7 residual-risk parenthetical and
  the §5.6 side-letter summary; both substantive disclosures survive verbatim in the section
  *bodies* on both surfaces, so no disclosure is lost — but AC19 forces convergence, so port the
  fuller canonical changelog to the mirror.
- C4: point the enforcement message at the served URL.
- Refresh `LEGAL_DOC_SHAS["acceptable-use-policy"]` if canonical changed.
- Resync `disclaimer` (2 cosmetic lines) — it is the cheapest document in the corpus to bring to
  zero drift and it is a counterparty to E1.

#### Phase 5 — T&C contradictions (E1–E9) and the version bump

Sequenced last because it depends on the counterparty documents being settled.

- Write the enumeration artifact under `knowledge-base/legal/` recording all nine contradictions
  **and** the six ambiguities, each with both quoted sides and the resolution taken. This is the
  durable record the `#736` row falsely appeared to be.
- Fix E1–E9. Several are cross-document and **must land with their counterparty in the same
  commit** or the corpus becomes contradictory in a new way: E1↔Disclaimer, E2↔DPD, E5↔GDPR
  Policy, E8↔AUP, E9↔AUP+Privacy Policy.
- E3 adds scope blocks to the T&C — the gate-1-sensitive edit. Same-line negative delimiter,
  referent no larger than the plugin-local text.
- The T&C mirror is at **zero drift**. Every T&C edit must be exactly lockstep or gate 2 fails
  immediately. This is the strictest document in the PR.
- Classify the change set per `knowledge-base/legal/tc-version-bump-policy.md`. E1, E2, E4 and E8
  read as Tier 1 (liability, forum, new sub-processor disclosure, rights scope); the rest as
  Tier 2. **Tier 1 *and* Tier 2 both require a bump** (Tier 2 takes PATCH) — so this PR bumps
  regardless of how the CLO grades individual items. Only Tier 3 (cosmetic) avoids a bump, and
  these are contradictions between statements in force, not cosmetics.
- The bump redirects web-platform principals to `/accept-terms` on next page load and closes live
  WebSocket sessions on the next gated message. **Measured blast radius on real users: zero** —
  the sole alpha tester is on the self-hosted CLI and never traverses that flow (CPO §2b). Do not
  restate this cost as "interrupts every tester"; that figure is wrong and would later be cited to
  justify deferring a legal fix.
- **M1 — re-notice the CLI cohort (CPO C2).** The bump is the only re-notice mechanism and it
  cannot reach the one cohort that exists. Tester #1 got the Terms as an out-of-band email
  paragraph and has accepted no `TC_VERSION`; E1 and E2 change exactly what they were told. Reset
  the alpha-tester roster's `Terms` column and re-send the corrected paragraph to every tester at
  `agreed` or `sent-awaiting-reply`, and add that step to `alpha-tester-onboarding.md` so the
  channel has a standing re-notice path.
- **M2 — the bump metadata is user-facing copy (CPO C2).** `TC_BUMP_METADATA.substantiveChange`
  renders verbatim into the Art. 13(3) banner on `/accept-terms`. Per the brand guide's tone
  spectrum for non-technical founders, a string like *"liability cap and forum-selection clause
  reconciliation"* fails on the one screen where a user is asked to consent. Write it in plain
  outcome language.
- Update in lockstep: `TC_VERSION`, `TC_DOCUMENT_SHA`, all four `TC_BUMP_METADATA` fields, the
  canonical Last-Updated line, the mirror, all **three** seed scripts (per A4), and the
  `compliance-posture.md` version row (per B2).
- CLO sign-off is the gating signal for merge of a Tier 1/2 T&C change.

#### Phase 6 — Coverage gaps, ratchets, and successor tracking (D1, D2)

- D1: add the non-tenant alpha-tester exit path to `tenant-offboarding.md`, or a cross-link to the
  runbook that owns it. Prefer the cross-link — one owner, one procedure — but make the tenant
  runbook state the case explicitly so it does not read as uncovered.
- D2: sweep all 13 `engineering/ops/` citations. **Carve out** `knowledge-base/project/plans/**`,
  `knowledge-base/project/specs/**`, `**/archive/**`, and this plan's own artifacts — those are
  point-in-time records that must retain the historical path. The residual-zero AC must carry the
  same carve-out or it contradicts itself.
- **Activate the ratchet:** add `acceptable-use-policy`, `data-protection-disclosure` and
  `disclaimer` to `BODY_EQUIVALENCE_DOCS`. This is what converts the fix into a guarantee — the
  committed note in the script has been waiting for exactly this remediation PR.
- Refresh the gate-2 baseline so the reduced drift is frozen at the new, lower level.
- File the successor issue for the deferred set with the measured per-doc drift table, **each
  document's character classification** (not just its count), the note that `gdpr-policy` is
  partially remediated here, and the 2026-09-30 target.
- **Re-point gate 2's header and runtime output** from `#7349` to the successor issue. The gate
  asserts `#7349` and `2026-09-30` in its output and its suite pins that assertion — closing this
  issue while drift remains would leave the gate citing a closed tracker. The suite must be
  updated in the same commit.
- Update the three legal skill/agent surfaces that carry the identical gate-discoverability block
  (`legal-audit`, `legal-generate`, `clo`) so they describe the new `BODY_EQUIVALENCE_DOCS` state.

## Alternative Approaches Considered

| Approach | Why not |
|---|---|
| **Split the T&C amendment into its own PR** | Rejected. E1, E2, E5, E8 and E9 are **cross-document**. Fixing the counterparty in this PR while the T&C waits would leave the corpus contradictory in a *new* way for the duration — moving the contradiction, not resolving it. Cross-document contradictions must resolve atomically. |
| **Resync all nine mirror pairs (220 lines) in this PR** | Rejected as primary scope. `privacy-policy` (58) + CLAs (19) + `cookie-policy` (4) are a **pure copy exercise orthogonal to the contradictions**. Bundling them into an already-large CLO review degrades the scarce resource this PR depends on. The ratchet guarantees this PR's progress is permanent, so the split costs nothing but calendar. Successor issue filed in-PR with the 2026-09-30 target. |
| **Defer `gdpr-policy` wholly** | **Rejected on CPO review (C3).** Two reasons. (a) It is *already* in scope — `Files to Edit` lists it on both surfaces for B4 (PA-30 re-home) and E5 (controller/processor carve-out), so a "total" deferral was really a partial one presented as total. (b) Its canonical-only **Art. 6(1) lawful-basis bullets** are the most severe of the three CLO-verified under-disclosures: a published GDPR policy missing the lawful-basis enumeration is the same Art. 13(1)(c) defect class this PR exists to fix, and is the first thing a regulator asks for. Shipping an under-disclosure fix that leaves the worst verified instance live until 2026-09-30 would reintroduce this issue's own thesis defect **at the scope level**. **Carve-back:** port the Art. 6(1) bullets to the published mirror as a targeted lockstep addition (the technique Phase 2/B4 already proves passes gate 2 without a full resync). **Still deferred:** the remaining ~60 structural/cosmetic drift lines, including the hard-wrapped scope block that trips gate 1 arm (c). **Do NOT** add `gdpr-policy` to `BODY_EQUIVALENCE_DOCS` — the carve-back fixes the disclosure; the ratchet waits for the full resync. |
| **Fix the guards' predicates only, without a reachability test** | Rejected — this is precisely the #7387 failure mode. A guard verified to detect a planted defect but never verified to *reach* its input is the same artifact-that-reads-as-coverage this issue exists to eliminate. |
| **Make the tenant runbook own a duplicate alpha-tester procedure (D1)** | Rejected in favour of a cross-link. Two copies of an offboarding procedure is the mirror-divergence defect class this PR is fixing, reintroduced in the runbooks. |
| **Leave `#736`'s row struck through** | Rejected. A struck-through row that names no successor is still an artifact that reads as coverage. The replacement must point at something real — hence the enumeration artifact. |

## Domain Review

**Domains relevant:** Legal (CLO), Engineering (CTO), Product (CPO), Operations

### Legal (CLO) — REVIEWED; six rulings made, sign-off deferred to diff-time

**Status:** reviewed. All six rulings below are made and their drafted replacement wording is
recorded. **Merge sign-off is NOT granted here** — Tier 1 sign-off must be written against the
actual diff, at `knowledge-base/legal/audits/2026-08-counsel-review-7349.md`, with a per-artifact
verdict and a DISCHARGED/BLOCKED disposition.

The CLO independently re-derived the plan's load-bearing premises and **overturned four of them**.
Those reversals are folded into the sections above; they are summarised here because a plan that
quietly absorbed them would hide that its first draft was wrong on the same class of inherited
claim it was written to eliminate.

| Ruling | Outcome |
|---|---|
| **1. SOC 2** | **No-commitment position governs.** §10.3 is the operative clause in an executable instrument and expressly disclaims a date certain; a summary table cannot create an obligation the operative clause negates. `security-sentinel` already forced this recast away from date-certain on §12.2(b) contract-formation grounds — reinstating 90 days reverses a risk decision. #4330 is CLOSED and cannot make anything live. The template's **§10.3 stays unchanged**; the 90-day form is replaced at the three other sites with an evaluation-plus-12-month-status-update form. |
| **2. PA-30** | **RE-CHARACTERISE IN PLACE — the plan's re-home is overruled.** See B4 above. |
| **3. AUP §4.6** | Canonical governs on act-framing, authorization, and the §4.2 cross-reference; (b) and (c) get **new merged text**; the workspace-logo paragraph ports verbatim. Both tail clauses belong — the mirror's revocation consequence *and* the canonical's liability disclaimer. |
| **4. DPD** | **Confirmed an Art. 13/14 deficiency**, not housekeeping: Art. 13(1)(e)/(f) and 14(1)(e)/(f) are mandatory content; dropping §5.3(a)/(e) removes the Art. 13(2)(b) statement of rights *and* the only published fulfilment pointer, additionally failing Art. 12(2). §2.3(ad)'s subjects are Art. 14 involuntary third parties, where the notice *is* the lawfulness condition and an unreachable canonical does not discharge it. Verbatim port is right for every item **except §2.3(ad)**, which needs new role wording first. |
| **5. T&C E1–E9** | Six real, **three misdiagnosed** (E2 half, E5 direction, E8 two of three limbs). Two further defects found that the plan missed entirely. Drafted wording supplied for every real item, including gate-1-safe scope blocks for E3. |
| **6. Tier** | **Tier 1 → `TC_VERSION` 2.4.0 → 2.5.0 (MINOR).** MAJOR is reserved for changes expected to cause abandonment ("new license restriction, new jurisdiction") — neither occurs; every substantive change is neutral-to-favourable to the user. CLO sign-off gates merge. |

**E3 — the mechanical constraint is handled in the drafted wording.** Each scope block uses the
`PARA_REF` referent (*"The paragraph above"*) rather than `This section`, so gate 1's arms (a) and
(b) — both keyed on `SECTION_REF` — never engage. This also follows the gate header's own recorded
CLO ruling that the remedy for over-reach is to narrow the referent in place. Each block is one
physical line carrying its negative delimiter and cross-reference on that same line, with the
locality verb inside 60 characters of the locality claim so it classifies rather than landing in
UNCLASSIFIED/exit 2. **None may be indented under a bullet** (arm b).

**Deletions the CLO endorses, with reasons** (every other change must be an addition or a
reconciliation — no lockstep removal of a disclosure anywhere):

- **The 45/45/five counts (E9)** — a fixed count in a versioned instrument is false the day the
  next agent lands, and the replacement is a pointer to a live inventory, so no disclosure is lost.
- **`disclaimer.md` §3.1's "Direct damages" bullet** — an unqualified direct-damages exclusion
  against an EU consumer is very likely unenforceable under Directive 93/13 Annex 1(b), and its
  presence risks the entire limitation clause.

Per `knowledge-base/project/learnings/` guidance that legal *decisions* route to the CLO and that
the CLO returns **drafted replacement wording**, not a verdict, the following are CLO deliverables
and must not be authored by the implementer:

1. **B1** — the SOC 2 position (no-commitment vs 90-day), and the wording for all four sites.
2. **C1/C2/C4** — for every divergence, which surface is correct; and new text where neither is.
   Specifically the AUP consent-only clause, which currently narrows the user's position below the
   statutory floor.
3. **E1–E9** — the resolution and drafted wording for each, including which instrument governs on
   E1 (liability) and E2 (forum).
4. **E-amb1..6** — adjudication or an explicit "recorded, not resolved" with reasons.
5. **B4** — whether PA-30 is re-characterised or re-homed, and the Art. 30(2) limb set.
6. **Phase 5 tier classification** and sign-off, which is the merge-gating signal for a Tier 1/2
   T&C change.

### Engineering (CTO)

Concerns the five gates, the guard reachability tests, the `BODY_EQUIVALENCE_DOCS` activation and
baseline refresh, and the gate-2 header re-point with its pinned suite assertion.

### Product (CPO) — sign-off GRANTED, conditional

**Status:** reviewed. `requires_cpo_signoff: true`; sign-off granted subject to four conditions,
all folded into this plan (C1–C4 below).

**Threshold:** agreed at `single-user incident`, but carried by C4 (the enforcement-message 404),
not by the notice-comparison argument. `## User-Brand Impact` reordered accordingly.

**Forced re-acceptance — SHIP WITH THIS PR.** Two corrections to the plan's original framing:

1. **"Tier 1 ⇒ bump" was wrong.** `tc-version-bump-policy.md` requires a bump for **Tier 2 as
   well** (PATCH). The plan classifies E3/E5/E6/E7/E9 as Tier 2, so even a full CLO downgrade
   still bumps. The real choice is *fix the T&C now or later*, and cross-document atomicity
   already settled that. There is no "time the bump separately" option.
2. **The blast radius is zero, not "every tester."** Measured: the cohort is **one** tester, on
   the **self-hosted CLI plugin**. `alpha-tester-onboarding.md` states a self-hosted CLI tester
   never passes through the platform's `accept-terms` flow. The middleware redirect and
   `recheckTcMidSession` WebSocket close reach web-platform authenticated principals only —
   currently the founder plus seed/QA principals. **No real user is interrupted.**

   Leaving an overstated cost in the plan is itself a risk: it is exactly the figure a future
   reader would cite to justify deferring a legal fix.

**The gap this surfaced (M1) — a notice channel with no re-notice path.** The `TC_VERSION` bump is
the only re-notice mechanism, and it cannot reach the only cohort that exists. Tester #1 received
the Terms as an out-of-band email paragraph and has never accepted any `TC_VERSION`. E1 (liability
cap) and E2 (forum) change precisely what that tester was told, and a bump generates **no notice
to them at all**. This is a roadmap-level coverage gap, not a detail — see AC35.

**Brand constraint on E9 (from `knowledge-base/marketing/brand-guide.md`).** The guide already
rules on this failure mode: *numbers are soft floors in prose* ("60+ agents"), because the live
site renders exact counts from the filesystem. **Resolving E9 by updating the numbers to today's
values resets the drift clock and guarantees E9 recurs.** Soft floors make the class extinct.
Routed to the CLO as a named constraint on the E9 wording. (The guide's "don't call it a plugin"
rule carries an explicit exception for legal documents where "Plugin" is a defined term, so E3's
scope-block sweep has no brand conflict.)

**Scope split — agreed, with one mandatory carve-back (C3).** See Alternatives Considered.

### Product/UX Gate

**Tier:** none.
**Rationale:** the mechanical UI-surface override does **not** fire. Files to edit are `.md`,
`.ts` literals and `.sh` gate scripts; the glob superset requires
`{tsx,jsx,vue,svelte,njk,html,astro}` and matches none of them. The `ui-surface-terms.md`
exclusion list explicitly covers "pure copy… with no structural/layout change" and
"docs / knowledge-base changes". No wireframe is required and `ux-design-lead` is correctly
absent — this is not a silent skip of a UI feature.

### Operations

`tenant-provisioning.md`, `tenant-offboarding.md` and the alpha-tester onboarding runbook change.
D1's cross-link direction is an operations ownership decision.

## Architecture Decision (ADR/C4)

**No ADR required.** This plan makes no architectural decision: no data-model ownership or tenancy
boundary moves, no new substrate or integration pattern, no resolver/dispatch/trust boundary
change, and no divergence from any existing ADR. It corrects documents, register placement, and
guard predicates on an already-decided architecture.

**C4: no impact — enumeration performed.** All three model files
(`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`) were read rather
than keyword-grepped, per the completeness mandate:

- **External human actors** — `founder`, `emailSender`, `betaContact`, `contributor`. All already
  modelled. `betaContact` is directly relevant: it is already described as an involuntary Art. 14
  third-party data subject originating the beta-CRM PII that DPD §2.3(ad) discloses. Publishing
  that disclosure changes the notice, not the actor.
- **External systems / vendors** — none added. LinkedIn Ireland and Microsoft Ireland appear as
  *disclosed sub-processors in a notice being restored to the published surface*; they are not new
  integrations and no new edge is created by this PR.
- **Containers / data stores** — none touched.
- **Actor↔surface access relationships** — none change. This PR alters published notice text, not
  who can access what.

No element description is falsified by this change.

## Observability

```yaml
liveness_signal:
  what: "CI required status checks tc-document-sha-guard, legal-scope-block-placement, legal-mirror-drift-baseline, and legal-doc-cross-document-gate enforce"
  cadence: per-PR and per-merge-group
  alert_target: PR status checks; a red required check blocks merge
  configured_in: .github/workflows/ci.yml, scripts/test-all.sh, apps/web-platform/scripts/check-tc-document-sha.sh

error_reporting:
  destination: GitHub Actions annotations via ::error:: from each gate script
  fail_loud: "each gate names the failing document, the computed vs expected value, and a numbered remediation; gate exit 2 means cannot-decide and is never a vacuous pass"

failure_modes:
  - mode: "a canonical legal doc is edited without its SHA literal refreshed"
    detection: "check-tc-document-sha.sh step 3 compares sha256(canonical) against the literal"
    alert_route: "tc-document-sha-guard required check fails the PR"
  - mode: "mirror drift grows, reorders, or a drifting line is rewritten on one side"
    detection: "lint-legal-mirror-drift-baseline.sh subset-ratchet comparison against the merge base"
    alert_route: "legal-mirror-drift-baseline required check fails the PR"
  - mode: "an added scope block claims a referent larger than its plugin-local text"
    detection: "lint-legal-scope-block-placement.sh arms (a)/(b)/(c) over added lines only"
    alert_route: "legal-scope-block-placement required check fails the PR"
  - mode: "a resynced document silently re-diverges after this PR"
    detection: "BODY_EQUIVALENCE_DOCS normalised body-equality for aup, dpd and disclaimer — the ratchet this PR activates"
    alert_route: "tc-document-sha-guard required check fails the PR"
  - mode: "a seed script drifts from TC_VERSION and QA users hit the accept-terms redirect loop"
    detection: "check-tc-document-sha.sh step 2.5 parity over SEED_SCRIPTS, extended to all three scripts by A4"
    alert_route: "tc-document-sha-guard required check fails the PR"
  - mode: "the guard suites are neutered and report green with zero assertions"
    detection: "MIN_ASSERTIONS floor at each suite exit, derived from a green run of the current suite"
    alert_route: "suite exits non-zero in test-all.sh"

logs:
  where: GitHub Actions job logs for the four required checks; local stdout/stderr from each script
  retention: GitHub Actions default log retention

discoverability_test:
  command: "bash scripts/lint-legal-scope-block-placement.sh --base origin/main; bash scripts/lint-legal-mirror-drift-baseline.sh --base origin/main; bash apps/web-platform/scripts/check-tc-document-sha.sh"
  expected_output: "all three exit 0; the drift gate prints '9 pair(s) checked, drift is within the baseline'"
```

## Acceptance Criteria

### Pre-merge (PR)

#### Guards (A)

- [ ] **AC1** — The `tenant-dpa-register.md` signed-row guard's predicate matches the file's own
      status vocabulary. Verified by running the guard against a **planted signed row** and
      asserting it fires, then removing the row.
- [ ] **AC2** — The same guard is proven to **reach a non-empty input**, not merely to detect a
      planted defect. A run whose input is empty must be distinguishable from a run that passed.
- [ ] **AC3** — The `tenant-provisioning.md` gate fails closed against the empty register. Verified
      by running it against the current (empty) register and asserting it does **not** report the
      populated-state verdict.
- [ ] **AC4** — No occurrence of the `status: `-prefixed status form remains in
      `tenant-dpa-register.md`, prose included.
- [ ] **AC5** — `aborted-provisioning` and `aborted-provisioning-at-step-N` are reconciled to one
      form across the runbook.
- [ ] **AC6** — `seed-live-verify-user.sh` appears in `SEED_SCRIPTS` **and** its `TC_VERSION`
      equals the canonical. `grep -c '^TC_VERSION="'` across `apps/web-platform/scripts/*.sh`
      returns 3, and all three values are identical to `lib/legal/tc-version.ts`.
- [ ] **AC7** — Each guard suite carries a `MIN_ASSERTIONS` floor derived from a green run of the
      **current** suite (never its predecessor, never an equality).

#### Contradictions and records (B)

- [ ] **AC8** *(rescoped — the original was unsatisfiable)* — across exactly three files
      (`data-processing-agreement-template.md`, `compliance-posture.md`,
      `2026-08-06-alpha-tester-processing-annex.md`) every SOC 2 statement carries the
      **no-commitment** position; no "90 days" form survives. **Do not grep the whole repo** — a
      repo-wide `grep -rn "SOC 2"` legitimately returns Cloudflare/Supabase third-party
      attestations, ADR-151's SOC 2 CC6.1 evidence path and four learnings, so the original AC
      could never pass.
- [ ] **AC9** — `compliance-posture.md` contains no struck-through `#736` row, and its replacement
      names the T&C enumeration artifact by path.
- [ ] **AC10** — `compliance-posture.md` carries a version column and its T&C row's version equals
      `TC_VERSION`; its Last-Updated values equal the corresponding documents'.
- [ ] **AC11** — `roadmap.md` row 4.1 reads "In progress — 1 of 10" (or equivalent) and is
      consistent with the same file's narrative; no row contradicts prose in the same document.
      **AND** either the `## Current State` milestone counts are synced to the live API, or the
      section's date is left untouched — never a date refresh over stale counts.
- [ ] **AC12** *(rewritten — CLO overruled the re-home)* — PA-30 **remains** in
      `article-30-register.md` with all its 30(1) limbs intact, and its role sentence states that
      Jikigai is controller today as the only store owner, naming the first-arms-length-owner
      trigger that flips the roles. `article-30-2-register.md` carries a `P-2` **reservation stub**
      for that trigger and no `P-2` record. **Assert the limbs survived:** PA-30 still carries its
      purposes, data-subject categories, personal-data categories, retention and DSAR limbs — a
      re-home would have silently dropped them and gate 2 would have passed.
- [ ] **AC13** — Every referrer to PA-30 resolves: `grep -rn "PA-30\|Processing Activity 30"` shows
      each site pointing at the new location, on **both** surfaces where the referrer is mirrored.
      The sweep must include **PA-32's lawful-basis cell and the counsel-review question that cite
      PA-30 as decisive internal precedent** — those citations carry an Art. 6(1)(f) necessity
      argument and must still resolve after the re-home.

#### Published-mirror agreement (C)

- [ ] **AC14** — DPD §2.3 sub-item sets are **identical** on both surfaces. The set-difference
      command in Test Scenarios returns empty in both directions.
- [ ] **AC15** — **Zero** dangling `2.3(x)` cross-references on **either** surface, verified by
      resolving each reference against the item set of the **same** surface.
- [ ] **AC16** — DPD §5.3 on the published surface names the `/dashboard/settings/privacy`
      self-serve export route.
- [ ] **AC17** — The two §4.2 sub-processor rows, two Chapter V bullets, the Art. 17 carve-out and
      the four erasure-cascade limbs are present on both surfaces.
- [ ] **AC18** — AUP §4.6 is identical on both surfaces and permits a lawful basis other than
      consent.
- [ ] **AC19** — `acceptable-use-policy`, `data-protection-disclosure` and `disclaimer` each report
      **zero** normalised body drift. **Precondition: E9 must already be applied** — the AUP
      mirror renders `{{ stats.agents }}` through Eleventy and the canonical cannot, so zero drift
      is unreachable while any count appears in that sentence. E9 therefore executes in Phase 4,
      not Phase 5.
- [ ] **AC39** *(CLO)* — Every scope block adjacent to a §2.3 insertion point in the DPD was
      **read** and its referent still points at the paragraph it was written for. Neither gate can
      see this: the block's line is unchanged, so gate 1 (added-lines-only) skips it and gate 2
      sees no drift delta.
- [ ] **AC40** *(CLO)* — Each of the six ported §2.3 items was re-verified against the live
      implementation before publication — particularly `(z)` workspace-logo upload and `(w)`
      delegated-credential routing. A canonical→mirror port is textually a copy but legally a
      first publication, and AC34 does not reach it.
- [ ] **AC41** *(CLO)* — `disclaimer.md` §3.2's "provided free of charge" premise is corrected
      (the Web Platform sells Stripe subscriptions per T&C §5) and §3.1's unqualified
      **direct-damages** exclusion is removed, with direct damages left subject to the §3.2 cap.
- [ ] **AC20** — The user-facing AUP link in `trust-tier-copy.ts` resolves to a served URL; no
      `/docs/legal/` path appears in user-facing copy.

#### T&C (E)

- [ ] **AC21** — The enumeration artifact exists under `knowledge-base/legal/`, records all nine
      contradictions **and** all six ambiguities, and quotes both sides of each with a content
      anchor.
- [ ] **AC22** — Each of E1–E9 is resolved with its counterparty document **in the same commit**.
      Verified per contradiction by walking the commit and asserting both region markers are
      present in that commit's diff — not by `git log -- <pathA> <pathB>`, which is a **union**
      filter and cannot distinguish a paired commit from a one-sided one.
- [ ] **AC23** — `terms-and-conditions` reports **zero** normalised body drift (it starts at zero;
      any T&C edit must be exactly lockstep).
- [ ] **AC24** — `TC_VERSION`, `TC_DOCUMENT_SHA`, all four `TC_BUMP_METADATA` fields, the canonical
      Last-Updated line, the mirror's Last-Updated line, all three seed scripts and the
      `compliance-posture.md` version row are mutually consistent.
- [ ] **AC25** — The PR body states the tier classification and its reasoning, and CLO sign-off is
      recorded.
- [ ] **AC35** *(CPO C2 / M1)* — `alpha-tester-onboarding.md` carries a standing step: when the
      canonical T&C changes materially, the roster's `Terms` column resets and the corrected
      paragraph is re-sent to every tester at `agreed` or `sent-awaiting-reply`. The step is
      executed for tester #1 in this PR.
- [ ] **AC36** *(CPO C2 / M2)* — `TC_BUMP_METADATA.substantiveChange` is legible to a
      non-technical founder. It renders verbatim into the Art. 13(3) banner on `/accept-terms`;
      no clause names, no jargon. AC24 checks consistency — this checks comprehensibility.
- [ ] **AC37** *(CPO §5b)* — E9 is resolved with **soft floors** ("60+ agents"), not refreshed
      exact counts, per the brand guide's rule that the live site renders exact counts from the
      filesystem. An exact count in prose resets the drift clock and guarantees E9 recurs.
- [ ] **AC38** *(CPO C3)* — The published `gdpr-policy` mirror carries the canonical Art. 6(1)
      lawful-basis bullets, added as a lockstep two-surface edit. `gdpr-policy` is **not** added
      to `BODY_EQUIVALENCE_DOCS` (its remaining ~60 drift lines stay with the successor issue).

#### Coverage and ratchet (D)

- [ ] **AC26** — `tenant-offboarding.md` states the non-tenant alpha-tester case explicitly and
      resolves it (procedure or cross-link to the owning runbook).
- [ ] **AC27** — `grep -rn 'engineering/ops/'` returns zero **excluding**
      `knowledge-base/project/plans/**`, `knowledge-base/project/specs/**`, `**/archive/**`, and
      `knowledge-base/project/learnings/best-practices/2026-06-03-path-rename-sweep-exclude-own-migration-artifacts.md`.
      The carve-out is part of the AC, not an exception to it — this plan, its tasks file, and
      that learning (whose subject *is* this carve-out) legitimately cite the old path. A
      residual-zero AC without the carve-out contradicts itself.
- [ ] **AC28** — `BODY_EQUIVALENCE_DOCS` contains `terms-and-conditions`, `acceptable-use-policy`,
      `data-protection-disclosure` and `disclaimer`.
- [ ] **AC29** — The gate-2 baseline is refreshed and total frozen drift is **strictly lower** than
      the measured 220.
- [ ] **AC30** — The successor issue exists and carries (a) the measured per-doc drift table for
      the deferred set, (b) each document's **character classification**, not just its count
      (CPO C3 — a resync-only successor repeats the "unclassified" gap), (c) a note that
      `gdpr-policy` is **partially** remediated here (Art. 6(1) bullets ported; ~60 structural
      lines remain), and (d) the 2026-09-30 target. Gate 2's header and runtime output cite
      **it**, not a closed `#7349`, and the suite assertion pinning that string is updated in the
      same commit.
- [ ] **AC31** — The three legal skill/agent gate-discoverability blocks (`legal-audit`,
      `legal-generate`, `clo`) describe the new `BODY_EQUIVALENCE_DOCS` state consistently.

#### Quality gates

- [ ] **AC32** — All five gates green, each run by **its own invocation**, not a hand-enumerated
      reconstruction of its input set:
      `bash scripts/lint-legal-scope-block-placement.sh --base origin/main`,
      `bash scripts/lint-legal-mirror-drift-baseline.sh --base origin/main`,
      `bash apps/web-platform/scripts/check-tc-document-sha.sh`, plus the consistency suite and
      `scripts/test-all.sh`.
- [ ] **AC33** — No gate was weakened to pass: no arm toggle changed, no document removed from
      `BODY_EQUIVALENCE_DOCS`, no `--base` widened, and the only baseline write lowers frozen drift.
      Verified by reading the diff of every gate script.
- [ ] **AC34** — Every claim this PR **adds** to a legal document traces to a named line in a cited
      source or to a CLO ruling recorded in the enumeration artifact. Absence-greps alone (AC14,
      AC15, AC27) test the new text's *shape* and can all pass while an added claim is false.

## Test Scenarios

### Verification commands (each re-derives a plan claim)

```bash
# DPD §2.3 sub-item parity — must return empty in both directions (AC14)
extract() { awk '/^### 2\.3 /{f=1} f&&/^### 2\.[4-9]|^## [3-9]/&&!/^### 2\.3 /{exit} f' "$1" \
  | grep -oE '^- \*\*\([a-z]{1,2}\)\*\*' | sed -E 's/^- \*\*\(([a-z]+)\)\*\*/\1/' | sort -u; }
comm -23 <(extract docs/legal/data-protection-disclosure.md) \
         <(extract plugins/soleur/docs/pages/legal/data-protection-disclosure.md)
comm -13 <(extract docs/legal/data-protection-disclosure.md) \
         <(extract plugins/soleur/docs/pages/legal/data-protection-disclosure.md)

# Dangling cross-references, resolved against the SAME surface (AC15)
for surface in docs/legal plugins/soleur/docs/pages/legal; do
  extract "$surface/data-protection-disclosure.md" > /tmp/items.$$
  grep -rhoE '2\.3\([a-z]{1,2}\)' "$surface"/*.md | sed -E 's/2\.3\(([a-z]+)\)/\1/' | sort -u \
    | while read -r i; do grep -qx "$i" /tmp/items.$$ || echo "DANGLING $surface 2.3($i)"; done
done

# Seed-script TC_VERSION parity (AC6)
grep -h '^TC_VERSION="' apps/web-platform/scripts/*.sh | sort -u   # expect exactly one line

# engineering/ops sweep with the historical carve-out (AC27)
grep -rn 'engineering/ops/' --include=*.md . \
  | grep -v 'knowledge-base/project/plans/' \
  | grep -v 'knowledge-base/project/specs/' \
  | grep -v '/archive/'                                            # expect empty
```

### Acceptance tests (RED targets)

- Given the register carries a planted signed row, when the guard runs, then it fires. Given the
  row is removed, then it does not. **Both arms required** — only the pair proves the predicate
  matches rather than that the guard always fires.
- Given the register is empty, when the provisioning gate runs, then it does not report the
  populated-state verdict.
- Given a legal canonical is edited without its SHA literal refreshed, when the SHA guard runs,
  then it fails naming that document.
- Given a drifting mirror line is rewritten on one side only, when gate 2 runs, then it fails with
  `CONTENT CHANGED`.
- Given a scope block is added whose referent exceeds its plugin-local text, when gate 1 runs, then
  it exits 1.

### Edge cases

- A document brought to zero drift and added to `BODY_EQUIVALENCE_DOCS` must be verified in that
  order; adding it while drift remains turns a required check red.
- A **lockstep deletion** removes the same disclosure from both surfaces, leaves drift unchanged,
  and passes gate 2. Gate 2's own output says so. Only the SHA pin and human review catch it — so
  every deletion in this PR needs an explicit CLO reason, not a gate's silence.
- `MIN_ASSERTIONS` must be a floor, never an equality, or each added assertion becomes a spurious
  failure.

## Risk Analysis & Mitigation

| Risk | Mitigation |
|---|---|
| A gate fires and the fastest fix is to weaken it | AC33 reads the diff of every gate script. The operator brief is explicit: a firing gate is signal to satisfy it. |
| Resyncing rewrites a drifting line into a third form and trips `CONTENT CHANGED` | Direction-of-authority rule: always make the two surfaces identical, never rewrite one side. |
| ~~The T&C bump forces re-acceptance for the whole alpha cohort mid-alpha~~ **WITHDRAWN — the figure was wrong** | Measured on CPO review: the sole tester is on the self-hosted CLI and never traverses `/accept-terms`; the bump reaches the founder plus seed/QA principals only. Blast radius on real users is **zero**. The real risk is the inverse — see the next row. |
| The bump cannot reach the only cohort that exists, so E1/E2 change what a tester was told with no notice to them | M1: reset the roster `Terms` column, re-send the corrected paragraph, and add a standing re-notice step to `alpha-tester-onboarding.md` (AC35). |
| A stale `## Current State` date refresh makes the roadmap *look* verified over a 293-issue count drift | CPO C4: sync the milestone counts or leave the date alone. AC11 covers both. |
| A cross-document contradiction is fixed on one side only | AC22 walks each commit for both region markers. `git log -- A B` is a union filter and is explicitly rejected. |
| Plan numbers are wrong and propagate into legal text | Phase 0 re-derives every number before any edit and stops on disagreement. AC34 requires added claims to trace to a source. |
| PA-30 re-home leaves a dangling referrer on the published surface | AC13 checks both surfaces, not just the canonical. |
| The successor issue is filed but the gate keeps citing a closed `#7349` | AC30 couples the header, the runtime output and the pinned suite assertion in one commit. |
| The `engineering/ops/` residual-zero AC contradicts this plan's own citations | AC27 carries the carve-out as part of the criterion. |

## Sharp Edges

- **The mirror is the published document.** Every instinct that says "the canonical is the source
  of truth, just copy it down" is backwards on the *legal* question: the mirror is what a data
  subject reads and what a regulator would be shown. Where the two disagree, the question is not
  "which is upstream" but "which is correct".
- **`docs/legal/gdpr-policy.md` contains one hard-wrapped scope block** whose negative delimiter
  falls on a later line, unlike every sibling block in the corpus which is a single long line.
  Gate 1's arm (c) requires the delimiter **on the same line**. If that document is resynced (it
  is in the deferred set), that block will fire. Do not "fix" it by widening the gate.
- **The DPD carries the same hard-wrapped shape, and it IS in this PR's scope.** Its block's
  referent is *"The paragraph above"*. Inserting a restored §2.3 item above it silently re-points
  that referent at different text — and **both gates are blind to it**, because the block's own
  line never changes. This is the sharpest edge in the PR: a correctness regression in legally
  operative text that passes every required check. Read, don't grep.
- **A canonical→mirror port is legally a first publication, not a copy.** AC34's
  "every added claim traces to a source" does not reach a port, so the six DPD items need
  live-implementation re-verification of their own (AC40).
- **Three of the plan's own first-draft claims were false** (E2's forum conflict, E5's direction,
  two of E8's three limbs). They came from the issue body and read as plausible. If you find
  yourself "fixing" a dangling T&C cross-reference or a mandatory-vs-optional side-letter
  conflict, stop — measured, neither exists.
- **Gate 2 passes a lockstep deletion.** Removing a disclosure from both surfaces leaves drift
  unchanged. The gate says so in its own output. Deletions need a reason, not a green check.
- **`grep -c '^|'` over a markdown table counts the header and separator.** That is why A2 exists;
  do not reintroduce the same shape when writing the replacement gate.
- **A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder
  text, or omits the threshold will fail `deepen-plan` Phase 4.6.**
- **`#7349`'s own comment thread contains a self-correction** withdrawing two of six claimed
  mirror omissions. Read the whole thread before quoting any figure from it; the earliest
  comment's list is superseded.

## Open Code-Review Overlap

**None.** All 64 open `code-review` issues were queried and their bodies searched for each file
this plan intends to edit (`tenant-dpa-register.md`, `tenant-provisioning.md`,
`data-processing-agreement-template.md`, `compliance-posture.md`, `roadmap.md`,
`article-30-register.md`, `acceptable-use-policy.md`, `data-protection-disclosure.md`,
`terms-and-conditions.md`, `tenant-offboarding.md`, `gdpr-policy.md`). Zero matches.

## Files to Edit

**Legal corpus — canonical (`docs/legal/`)**
`terms-and-conditions.md`, `acceptable-use-policy.md`, `data-protection-disclosure.md`,
`disclaimer.md`, `gdpr-policy.md` (targeted E5 + PA-30 lines only), `privacy-policy.md`
(targeted E9 line only)

**Legal corpus — published mirror (`plugins/soleur/docs/pages/legal/`)**
the same six files, each edit in lockstep with its canonical counterpart

**Knowledge base — legal (edit)**
`compliance-posture.md`, `data-processing-agreement-template.md`, `article-30-register.md`
(PA-30 role sentence — **not** a re-home), `article-30-2-register.md` (`P-2` reservation stub
only), `legitimate-interest-assessments/2026-07-07-beta-crm-lia.md`,
`legitimate-interest-assessments/2026-07-31-claude-eval-fleet-and-ci-lia.md`

**Files to CREATE**
- a T&C-contradiction enumeration artifact under `knowledge-base/legal/`
- `knowledge-base/legal/audits/2026-08-counsel-review-7349.md` — the CLO's Tier 1 sign-off,
  written against the actual diff with a per-artifact verdict and a DISCHARGED/BLOCKED
  disposition. This is the merge gate for the T&C change.

**Do NOT edit** (carve-outs): `knowledge-base/legal/audits/2026-07-counsel-review-6165.md` and
`-6172.md` (point-in-time counsel records), `2026-08-06-alpha-tester-processing-annex.md`
(already states the correct SOC 2 position),
`apps/web-platform/supabase/migrations/126_beta_crm.sql` (applied to production — supersede, never
edit).

**Knowledge base — product / runbooks**
`knowledge-base/product/roadmap.md`,
`knowledge-base/legal/tenant-dpa-register.md` *(verified path — the register lives under
`knowledge-base/legal/`, not under the runbooks tree)*,
`knowledge-base/engineering/operations/runbooks/tenant-provisioning.md`,
`knowledge-base/engineering/operations/runbooks/tenant-offboarding.md`,
plus the 7 files carrying live `engineering/ops/` citations enumerated in D2 (the 8th hit is
carved out, not edited)

**Application / gates**
`apps/web-platform/lib/legal/tc-version.ts`, `apps/web-platform/lib/legal/legal-doc-shas.ts`,
`apps/web-platform/lib/messages/trust-tier-copy.ts`,
`apps/web-platform/scripts/check-tc-document-sha.sh`,
`apps/web-platform/scripts/seed-live-verify-user.sh`,
`apps/web-platform/scripts/seed-dev-users.sh`, `apps/web-platform/scripts/seed-qa-user.sh`
(only if `TC_VERSION` bumps), `scripts/lint-legal-mirror-drift-baseline.sh` (header + baseline),
`scripts/lint-legal-mirror-drift-baseline.test.sh` (pinned assertion)

**Skills / agents**
`plugins/soleur/skills/legal-audit/SKILL.md`, `plugins/soleur/skills/legal-generate/SKILL.md`,
`plugins/soleur/agents/legal/clo.md` — the shared gate-discoverability block

## References

### Internal

- Issue #7349 and its four comments — including the 2026-08-10 **self-correction** withdrawing two
  of six claimed omissions
- `knowledge-base/project/learnings/2026-08-10-every-gate-i-built-passed-85-green-assertions-and-had-two-fail-opens.md`
- `knowledge-base/legal/tc-version-bump-policy.md` — tier rubric, semver scheme, CLO sign-off
- `apps/web-platform/scripts/check-tc-document-sha.sh` — the `BODY_EQUIVALENCE_DOCS` note that has
  been waiting for this remediation PR
- `scripts/lint-legal-scope-block-placement.sh`, `scripts/lint-legal-mirror-drift-baseline.sh`,
  `scripts/lib/legal-normalise.sh`
- Commit `bab29e651` (PR #7388, issue #7387) — the two write-time gates
- PR #7342 / issue #7331 — the controller/processor determination that surfaced these
