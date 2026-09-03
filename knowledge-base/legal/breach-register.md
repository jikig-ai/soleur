---
title: "Article 33(5) Breach Register — index of personal-data breach determinations"
type: breach-register
date: 2026-09-03
issue: 7717
status: draft-requires-counsel-review
controller: "Jikigai SARL, 25 rue de Ponthieu, 75008 Paris, France — RCS Paris 927 585 729"
related:
  - knowledge-base/legal/article-30-register.md
  - knowledge-base/legal/article-30-2-register.md
  - knowledge-base/legal/statutory-response-catalog.md
  - knowledge-base/legal/compliance-posture.md
  - knowledge-base/legal/audits/2026-06-29-inngest-prd-rls-reachability-gdpr-determination.md
  - knowledge-base/legal/audits/2026-08-06-alpha-tester-controller-processor-determination.md
  - knowledge-base/legal/audits/2026-08-17-clo-ruling-cla-evidence-admin-bypass-7597.md
  - knowledge-base/engineering/operations/post-mortems/sentry-phantom-ingest-destination-unreachable-postmortem.md
---

# Article 33(5) Breach Register — Jikigai SARL as controller

## Why this is a separate file

GDPR Art. 33(5) requires the controller to document personal-data breaches — the facts, the
effects, and the remedial action taken — so that the supervisory authority can verify
compliance with Art. 33. It is **not** an Art. 30(1) limb. Art. 30(1) enumerates a closed list
of limbs (a)–(g) and breach documentation is not among them, and CNIL practice keeps a
*registre des violations* distinct from the *registre des traitements*. Recording these
determinations inside `knowledge-base/legal/article-30-register.md` would invite the reading
that Jikigai treats Art. 33(5) documentation as an Art. 30 limb — an error that costs
credibility in an Art. 58(1)(a) exchange.

The corpus already carries this separation: `knowledge-base/legal/article-30-2-register.md`
exists as a distinct file for Art. 30(2) processor-capacity records. This file follows that
precedent. See ADR-200.

This register is kept in Jikigai's **controller** capacity, which is the capacity Art. 33(5)
binds. Where Jikigai acts as processor, its duty is the Art. 33(2) duty to notify the
controller without undue delay; processor-capacity records are kept in
`knowledge-base/legal/article-30-2-register.md`. The 2026-08-06 determination is indexed here
because its controller limb (PA-34, PA-35) is the limb the Art. 4(12) finding addresses.

**Not to be confused with #3686.** That issue proposes a durable `security_events` runtime
table citing the same article. That is a *runtime event* surface; this is an index of
*determinations*. They are complementary, and the corpus must not grow two things both called
"the Art. 33(5) register".

## What this register is, and is not

**It is an index, not a transcription.** Art. 33(5) is discharged by the per-incident
documentation itself, which already exists in the canonical files cited in the last column.
Duplicating those files here would mint a second copy that drifts, and this repository's gates
measure *agreement* rather than *truth* — two byte-identical copies of a stale sentence pass
everything. Rows are summaries with stable canonical pointers. **No fenced determination block
is reproduced, and no signed instrument is amended.**

Rows are nonetheless self-sufficient on notifiability: a reader must be able to see, without
opening the source, whether Art. 33 and Art. 34 were engaged and whether any evidentiary limb
came back inconclusive. Art. 33 (supervisory authority) and Art. 34 (data subject) are
**different tests** and are recorded in separate columns; neither is inferred from the other.

## Inclusion predicate

An event is indexed here when **both** limbs hold:

1. a **breach-shaped fact pattern** — an actual or suspected security event touching personal
   data — arose; **and**
2. it was **assessed against Art. 4(12)** and a determination was recorded.

The predicate is conjunctive, and stating it is what makes "every determination" falsifiable
rather than rhetorical.

**Expressly excluded — screening outputs.** A post-incident review generated from
`plugins/soleur/skills/incident/templates/pir.md` carries `art_33_triggered:` frontmatter.
Where that field reads `false` on an availability-only or credential-only incident, it is a
**screening output, not a determination**, and is not indexed. Measured 2026-09-03 on `main`:
**102** post-mortems under `knowledge-base/engineering/operations/post-mortems/` carry
`art_33_triggered`, unchanged at this PR's HEAD. (A repo-wide total is deliberately not quoted:
it counts plans, specs, this ADR and the guard's own source, so any PR discussing the field moves
it — including this one, which took it from 115 to 119. The post-mortem count is the figure the
predicate turns on, and it is stable.) Indexing screening outputs would bury four determinations in a hundred routine
negatives.

**Expressly excluded — prospective clearances.** A review concluding that a *planned change*
engages no Art. 33 or Art. 34 duty is not breach documentation: no fact pattern arose. If every
Art. 30 amendment review reciting "this change engages nothing" earned a row, the register
would become a log of routine change approvals and an Art. 58(1)(a) reader could no longer
distinguish incidents from housekeeping — defeating the verification purpose the register
exists to serve.

Files that are determination-shaped under the CI guard's pinned pattern but fall outside this
predicate are **not silently dropped**: each carries a committed `NOT_TRANSCRIBED` waiver with
a reason, listed under §Excluded records below and checked by
`scripts/lint-legal-registers.sh`, which is registered in `scripts/test-all.sh` and lands
**advisory for one merge cycle** (#7787): for that window a finding is reported as a warning and
does not block, while a fail-closed refusal still does. The control is real and its enforcement
level is stated rather than implied.

## Provenance — why this file is dated 2026-09-03

Each determination below was made and documented **at the time of its event**, in the canonical
file cited in its last column. Until this register was created they were discoverable only by
knowing which incident to look for — enumerable in principle, not in practice.

Creating this index is an **Art. 5(2) accountability improvement**. Accountability means being
able to *demonstrate* compliance, and documentation that cannot be enumerated cannot be
demonstrated on request. The delay in creating the index is recorded here rather than elided.

**It is not an Art. 33(5) breach.** That article prescribes no register form; per-incident
documentation discharges it, and that documentation existed throughout. It is not an Art. 30
gap either — the Art. 30(1) limbs are closed and breach documentation is not among them.

**This file alters, revisits and re-dates nothing.** Every determination stands exactly as
made and signed. Where a row records a correction, the correction is an annotation appended to
the canonical record under its own dated marker, never an edit to signed text.

## Index of determinations

| Date | Event | PA(s) touched | Awareness anchor (Art. 33(1) clock origin) | Determination | Art. 33 engaged? | Art. 34 engaged? | Evidentiary limbs inconclusive? | Canonical source |
|---|---|---|---|---|---|---|---|---|
| 2026-05-16 | Sentry phantom-ingest: prd runtime error/event envelopes POSTed for ~49 days to an org the operator could not, at the time, enumerate or administer | PA-8 | 2026-05-16T12:50:00Z — surfaced externally/manually during A2 brainstorm prereq verification, **not by any monitor**; MTTD ~49 days from DSN introduction 2026-03-28T18:03:00Z | Not a notifiable breach. Phase 9 (2026-05-19) reattributed the apparent non-ownership to an internal `SENTRY_AUTH_TOKEN` membership-scope defect: Sentry support confirmed in writing that **both** `jikigai` and `jikigai-eu` are owned by the operator's user and that all audit-log actions in both were performed by it. No third-party recipient, no cross-controller transfer, no sub-processor outside operator control | No | No | **Partially — and narrower than the pre-Phase-9 record suggests.** Phase 9 closed the ownership and enumeration questions; the affected population is enumerated as **10** operator-adjacent accounts (founders, team, bot, internal QA, and 2 friends-of-team test signups under operator instruction), matching Art. 30 PA-8 §(d). The source PIR's §Summary phrases this as "operator + 8 operator-adjacent accounts + 2 friends-of-team", which double-counts the 2 signups already inside the 10 — its §Authenticated app user paragraph and its frontmatter both say 10. The residual is the *granular causal* mechanism of the token-membership boundary, recorded as `NOT YET TESTED` at Theory state T3 with T0 falsification holding in every causal variant — an engineering residual, not an evidentiary limb bearing on the Art. 33 / Art. 34 conclusion | `knowledge-base/engineering/operations/post-mortems/sentry-phantom-ingest-destination-unreachable-postmortem.md` |
| 2026-06-29 | RLS disabled on 14 public tables of Supabase project `soleur-inngest-prd` (`pigsfuxruiopinouvjwy`); PostgREST public schema reachable in principle by any holder of the project anon key. Tables can embed event payloads, step I/O and tenant identifiers incl. `event_user` and `worker_ip`. Exposure window 2026-06-17 → 2026-06-29 (~12 days) | Not attributed to a Processing Activity in the source. PA-8 §(g) now carries the Art. 33 evidentiary-chain limitation this determination motivated | 2026-06-22 — Supabase security advisor flagged `rls_disabled_in_public` | REACHABILITY-ONLY, no notifiable breach. No Art. 4(12) breach arose. Rests **primarily on the absent exploitation precondition** — this project's anon key was never published in any client bundle or commit (clean tree + full git-history pickaxe) — not on absence of access evidence. DISCHARGED | No | No | **Yes** — the access-log dimension is INCONCLUSIVE and expressly **not certified clean** for 2026-06-17 → ~2026-06-27. Two annotations narrow it further: the 2026-08-26 addendum established `edge_logs` is uninstrumented on this project so its zero was never evidence; the 2026-09-03 addendum established that `auth_logs` is instrumented (weak positive value) and that `postgrest_logs`, the source that records REST traffic, was never queried, and that window is recorded as not established to be recoverable (no retrieval was attempted and no probe is cited; see the 2026-09-03 addendum at the canonical record) | `knowledge-base/legal/audits/2026-06-29-inngest-prd-rls-reachability-gdpr-determination.md` |
| 2026-08-06 | Operator ran Soleur agents against an alpha tester's repository content under a Jikigai Anthropic API key, at the tester's request, with no Art. 28(3) instrument in place | PA-34 and PA-35 (controller limb); record P-1 in the Art. 30(2) register (processor limb) | 2026-08-06 — same-day session-scope reconstruction of the run; the source records no separate awareness moment and states expressly that no notification clock is running | Not a personal-data breach under Art. 4(12): the finding fails on the **security** limb, being a lawfulness-and-documentation failure of a different defect class. **Contested, and recorded as such** — the source preserves the contrary argument that the processing can be argued into "unauthorised" within Art. 4(12) and records that argument as **not frivolous**, and states in terms that it does not conclude nothing happened | No — contested; see the preserved counter-argument in the source | No — contested, as above | **Yes** — the source's own status is internally divergent: frontmatter `status: draft-requires-counsel-review` and a `BLOCKED` disposition coexist with a performed CLO internal sign-off. Recorded here unresolved rather than laundered; see §Register maintenance | `knowledge-base/legal/audits/2026-08-06-alpha-tester-controller-processor-determination.md` |
| 2026-08-17 | `cla-evidence` required status check failed (exit 127, `bun: command not found`) blocking all PRs; an admin bypass was used to land the repair PR #7597 on a surface PA-7 §(c) confirms processes personal data | PA-7, expressly **unchanged** — purposes, categories, recipients, retention and TOMs are untouched by a transient CI outage | 2026-08-16T23:38Z — first failing run of the `Record allowlist-bypass` step. The source records the failure onset and states no separate awareness moment; the determination is dated 2026-08-17 | No Art. 33 notification duty. Art. 4(12) requires destruction, loss, alteration, unauthorised disclosure of or access to personal data processed; **a record that was never created is not a record that was lost**. Confidentiality and integrity of the existing R2 store were untouched throughout and Object Lock held. APPROVED / DISCHARGED | No | **Not stated in source** — the source makes no Art. 34 finding, and its Art. 33 finding is not read as covering one | No — exposure was **measured** NIL, not assumed | `knowledge-base/legal/audits/2026-08-17-clo-ruling-cla-evidence-admin-bypass-7597.md` |

**Two cells are load-bearing and must not be "tidied" by a later editor.** The Art. 34 cell on
the 2026-08-17 row reads *Not stated in source* because no Art. 34 text exists there; writing
"No" would mint a finding nobody made. And the 2026-08-06 row's Art. 33 / Art. 34 cells carry
the contest, because the register's evidentiary value depends on showing an authority the
argument that was preserved *against* the holding, not only the holding.

## Excluded records (`NOT_TRANSCRIBED`)

These files match the CI guard's determination-shaped pattern under
`knowledge-base/legal/audits/` and are **not indexed**. Each carries a committed reason, so
nothing is silently dropped.

**Two dispositions, and they are not the same claim.** Four rows are *assessed and outside* the
inclusion predicate. Two — the 2026-05-15 and 2026-05-17 Sentry audits, surfaced only when the
producer pattern was widened on 2026-09-03 — are **undetermined**, pending the CLO ruling
requested at #7791, and are marked as such in their reason cells. A preamble asserting all six
"fall outside the inclusion predicate" would state a determination that has not been made for
those two, which in a regulator-facing register is the thing this file exists not to do. The machine-readable waiver list
lives in `scripts/lint-legal-registers.sh`; this section is its human-readable mirror.

| File | Reason for exclusion |
|---|---|
| `knowledge-base/legal/audits/2026-05-12-gdpr-gate-plan-phase-2-7-outcome.md` | No Art. 4(12) assessment: the file never cites Art. 4(12), matched the pattern solely on one `Art. 33` occurrence, and its non-notifiable statement is expressly attributed to *the operator's framing* rather than recorded as a controller determination. Indexing it would launder a framing into a determination. The underlying matter is a disclosure-timing lag, not a security event (#7717) |
| `knowledge-base/legal/audits/2026-06-counsel-review-5103.md` | No event and no determination: the sole `Art. 33` occurrence verifies the accuracy of a statutory-deadline catalog entry, not a fact pattern. A regex false positive (#7717) |
| `knowledge-base/legal/audits/2026-08-counsel-review-7440.md` | Express Art. 4(12) assessment, but of a **prospective** PA-8 amendment with no fact pattern — nothing was destroyed, lost, altered or disclosed. There is no breach documentation to index, and a row would dilute the register with routine change approvals (#7717) |
| `knowledge-base/legal/audits/sentry-migration-audit-2026-05-15.md` | **Disposition pending CLO ruling (#7791).** Records an Art. 33 notifiability conclusion on a data-residency fact pattern ("No personal data left the EEA. Article 33 … does not trigger"), but states no Art. 4(12) assessment, so whether it satisfies the inclusion predicate's second limb is a legal call. Surfaced only when the producer pattern was widened at review to catch the spelled-out "Article 33" (#7717) |
| `knowledge-base/legal/audits/2026-05-17-sentry-ingest-window-auth-users-audit.md` | Matches the producer only on "CNIL Art 33 filing posture per brainstorm Decision #10" — a reference to filing posture, not a fact pattern assessed against Art. 4(12). Confirm alongside the row above at #7791 (#7717) |
| `knowledge-base/legal/audits/2026-09-03-implementation-record-7717-art-33-5-register.md` | Not a determination: an implementation record *about* this register. It necessarily quotes Art. 4(12) / Art. 33(5) and so matches the producer pattern, but it assesses no fact pattern and records no controller determination. Note it is **not** a CLO attestation — that artifact was not obtained and is tracked at #7791 (#7717) |

## Register maintenance

- **Custodian:** Soleur CLO role, per ADR-200. The `clo` agent maintains this register at ship
  time; `/soleur:incident` routes here for the `art_33_triggered: true` case.
- **Canonical-source column format (machine-readable — do not restyle).** The last column
  carries exactly one repo-relative path, backtick-delimited, and nothing else.
  `scripts/lint-legal-registers.sh` strips the backticks and resolves the path against the
  working tree; a row whose pointer does not resolve fails the gate. A determination register
  whose pointers rot is worse than none.
- **Review cadence:** on every new determination, and on the Art. 30 register's quarterly
  review.
- **Open item — 2026-08-06 source status.** That determination's own frontmatter says
  `draft-requires-counsel-review` with a `BLOCKED` disposition, while the same file records a
  performed CLO internal sign-off. The divergence is in the source, not introduced here; it
  needs its own attestation pass and is not resolved by this register.
- **Verified 2026-09-03 — the Sentry post-mortem's compliance item is discharged.** That file
  carries an unticked checkbox for "Update PA8 §5(2) … add a positive disclosure of the
  2026-03-28 → 2026-05-16 phantom-ingest window", while a later line reports it recorded via a
  PR-2 UPDATE block. The register entry is present: Art. 30 PA-8 §(d) carries a dated
  2026-05-19 UPDATE block disclosing and then superseding the window. The checkbox is stale;
  the obligation is met.

## Non-scope — the Supabase log surface carries no retention measure

**No retention technical-and-organisational measure is recorded for the Supabase log surface,
and this is deliberate.** What was measured on 2026-08-26 is revocable, vendor-controlled
retrievability through an instrument concurrently proven untrustworthy for this purpose: the
Management API log endpoint returns HTTP 200 with `error: null` over windows it silently
truncates non-monotonically, and it does not enforce its own documented 24-hour range cap.
Recording that as a technical measure would claim a control the controller does not hold.

What is recorded instead is the **limitation**, at Art. 30 PA-8 §(g), together with the
durable-sink remediation named as open at **#5697**. Recording a measured limitation is what
Art. 5(2) looks like when the news is bad, and it is a stronger posture than a measure that
would not survive scrutiny.

The 2026-06-29 determination's own FOLLOW-UP condition already reached this conclusion — it
asks for retention to be extended *or* logs shipped to durable storage, and a longer
vendor-side retained span satisfies neither limb. This register is not creating a new
judgement; it is recording one that was already made.

Evidence: `knowledge-base/engineering/operations/references/supabase-management-api-log-contract.md`;
ADR-197; `knowledge-base/project/specs/feat-one-shot-supabase-analytics-logs-endpoint-migration/archive/20260902-200523-session-state.md`.

---

> **DRAFT — This document was generated by AI and requires professional legal review before use. It does not constitute legal advice.**
