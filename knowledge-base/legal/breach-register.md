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
it — including this one, which moved it too — measured 116 at the merge-base and 123 at HEAD; an earlier revision said 115 to 119, true only mid-branch and not re-measured after ADR-200, the guard and the spec docs landed. The post-mortem count is the figure the
predicate turns on, and it is stable.) Indexing screening outputs would bury five determinations in a hundred routine
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
| 2026-05-15 | Art. 5(2) accountability evidence for PA-8 was regenerated against the US shadow org `jikigai-us`: the audit script's region probe returned the first host to answer `/users/me/`, which was `sentry.io`, while the IaC tfstate stayed pinned to that US cluster. The artifact was then cited by PA-8 as the DE-residency evidence, raising a suspected unlawful third-country transfer | PA-8 | 2026-05-15 — surfaced by the audit artifact itself: its own `**API host:** sentry.io` line prompted the residency review recorded in the same file's §Correction (2026-05-15) | Not a notifiable breach. No personal data left the EEA: user-event ingest is DE-bound, anchored by the production DSN cluster substring `o4511123328466944.ingest.de.sentry.io` (the authoritative residency signal per learning `2026-05-15-sentry-dsn-cluster-substring-authoritative-residency.md`). What the US cluster held was monitor and alert-rule metadata, not personal data. Remediated in PR #3863: the `SENTRY_API_HOST` default flipped to `de.sentry.io`, the probe loop reversed, and a fail-closed residency-mismatch detector added that refuses to emit an artifact when the probed host disagrees with the DSN cluster | No | No | **Partially — on the accountability limb only, not on notifiability.** The Art. 33 determination is closed on its own facts. What remains open is the Art. 5(2) *evidence*: this artifact was generated from the wrong cluster and its replacement is pending at **#3861** (Phase A2 cluster surgery), after which a regenerated `sentry-migration-audit-<post-fix-date>.md` becomes the load-bearing §5(2) artifact and PA-8's pointer is updated | `knowledge-base/legal/audits/sentry-migration-audit-2026-05-15.md` |
| 2026-05-16 | Sentry phantom-ingest: prd runtime error/event envelopes POSTed for ~49 days to an org the operator could not, at the time, enumerate or administer | PA-8 | 2026-05-16T12:50:00Z — surfaced externally/manually during A2 brainstorm prereq verification, **not by any monitor**; MTTD ~49 days from DSN introduction 2026-03-28T18:03:00Z | Not a notifiable breach. Phase 9 (2026-05-19) reattributed the apparent non-ownership to an internal `SENTRY_AUTH_TOKEN` membership-scope defect: Sentry support confirmed in writing that **both** `jikigai` and `jikigai-eu` are owned by the operator's user and that all audit-log actions in both were performed by it. No third-party recipient, no cross-controller transfer, no sub-processor outside operator control | No | No | **Partially — and narrower than the pre-Phase-9 record suggests.** Phase 9 closed the ownership and enumeration questions; the affected population is enumerated as **10** operator-adjacent accounts (founders, team, bot, internal QA, and 2 friends-of-team test signups under operator instruction), matching Art. 30 PA-8 §(d). The source PIR's §Summary phrases this as "operator + 8 operator-adjacent accounts + 2 friends-of-team", which double-counts the 2 signups already inside the 10 — its §Authenticated app user paragraph and its frontmatter both say 10. **No — corrected twice, and the second correction was also wrong.** An earlier draft cited a pre-Phase-9 statement; the replacement cited a 2026-05-19 parenthetical *inside* Phase 9 that the same section supersedes 25 lines later: **T3 was RESOLVED 2026-05-21 and promoted to T4** (frontmatter `t3_resolved_at: 2026-05-21T07:00:00Z`, `t3_mechanism: T4-internal-integration-proxy-user-membership-boundary`; evidence at `knowledge-base/legal/audits/2026-05-21-sentry-token-t3-resolution.md`), with the mechanism named as the Internal Integration proxy-user membership scope in superposition with the `eu.sentry.io` `activeorg` slug-rewrite bug. Phase 9 closed ownership (Sentry support confirmed both orgs operator-owned, audit logs included) and enumeration. **No evidentiary limb remains open on this determination** | `knowledge-base/engineering/operations/post-mortems/sentry-phantom-ingest-destination-unreachable-postmortem.md` |
| 2026-06-29 | RLS disabled on 14 public tables of Supabase project `soleur-inngest-prd` (`pigsfuxruiopinouvjwy`); PostgREST public schema reachable in principle by any holder of the project anon key. Tables can embed event payloads, step I/O and tenant identifiers incl. `event_user` and `worker_ip`. Exposure window 2026-06-17 → 2026-06-29 (~12 days) | Not attributed to a Processing Activity in the source. PA-8 §(g) now carries the Art. 33 evidentiary-chain limitation this determination motivated | 2026-06-22 — Supabase security advisor flagged `rls_disabled_in_public` | REACHABILITY-ONLY, no notifiable breach. No Art. 4(12) breach arose. Rests **primarily on the absent exploitation precondition** — this project's anon key was never published in any client bundle or commit (clean tree + full git-history pickaxe) — not on absence of access evidence. DISCHARGED | No | No | **Yes** — the access-log dimension is INCONCLUSIVE and expressly **not certified clean** for 2026-06-17 → ~2026-06-27. Two annotations narrow it further: the 2026-08-26 addendum established `edge_logs` is uninstrumented on this project so its zero was never evidence; the 2026-09-03 addendum established that `auth_logs` is instrumented (weak positive value) and that `postgrest_logs`, the source that records REST traffic, was never queried, and that window is recorded as not established to be recoverable (no retrieval was attempted and no probe is cited; see the 2026-09-03 addendum at the canonical record) | `knowledge-base/legal/audits/2026-06-29-inngest-prd-rls-reachability-gdpr-determination.md` |
| 2026-08-06 | Operator ran Soleur agents against an alpha tester's repository content under a Jikigai Anthropic API key, at the tester's request, with no Art. 28(3) instrument in place | PA-34 and PA-35 (controller limb); record P-1 in the Art. 30(2) register (processor limb) | 2026-08-06 — same-day session-scope reconstruction of the run; the source gives no separate awareness moment and states expressly that no notification clock is running | Not a personal-data breach under Art. 4(12): the finding fails on the **security** limb, being a lawfulness-and-documentation failure of a different defect class. **Contested, and recorded as such** — the source preserves the contrary argument that the processing can be argued into "unauthorised" within Art. 4(12) and records that argument as **not frivolous**, and states in terms that it does not conclude nothing happened | No — contested; see the preserved counter-argument in the source | No — contested, as above | **Yes — and it is an evidentiary limb, not a workflow one.** The source records at §7 that a directory listing surfaced French business-register (RNE) *pouvoirs* sample data, which names **company officers — natural persons** (the source's own `data_subjects` frontmatter says so). The transcript shows these as a directory listing **with no evidence their contents were read, and it cannot positively exclude a partial read**; the source states that this does not convert into a clean bill of health and that the tester-facing message must not claim no personal data was involved. That is the material open limb. An earlier draft recorded a document-workflow point instead (frontmatter status vs `BLOCKED`), which is not an evidentiary limb — and which the source pre-empts at its header: v1 CLO attestation is *internal*, `draft-requires-counsel-review` refers to *external* counsel, and `BLOCKED` is a disposition on conditions C1-C9. The three are consistent by design | `knowledge-base/legal/audits/2026-08-06-alpha-tester-controller-processor-determination.md` |
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

**Two dispositions, and they are not the same claim.** Seven rows are *assessed and outside* the
inclusion predicate. Two — the 2026-05-15 and 2026-05-17 Sentry audits, surfaced only when the
producer pattern was widened on 2026-09-03 — are **undetermined**, pending the CLO ruling
requested at #7791, and are marked as such in their reason cells. A preamble asserting all nine
"fall outside the inclusion predicate" would state a determination that has not been made for
those two, which in a regulator-facing register is the thing this file exists not to do. The machine-readable waiver list
lives in `scripts/lint-legal-registers.sh`; this section is its human-readable mirror.

| File | Reason for exclusion |
|---|---|
| `knowledge-base/legal/audits/2026-05-12-gdpr-gate-plan-phase-2-7-outcome.md` | No Art. 4(12) assessment: the file never cites Art. 4(12), matched the pattern solely on one `Art. 33` occurrence, and its non-notifiable statement is expressly attributed to *the operator's framing* rather than recorded as a controller determination. Indexing it would launder a framing into a determination. The underlying matter is a disclosure-timing lag, not a security event (#7717) |
| `knowledge-base/legal/audits/2026-06-counsel-review-5103.md` | No event and no determination: the sole `Art. 33` occurrence verifies the accuracy of a statutory-deadline catalog entry, not a fact pattern. A regex false positive (#7717) |
| `knowledge-base/legal/audits/2026-08-counsel-review-7440.md` | Express Art. 4(12) assessment, but of a **prospective** PA-8 amendment with no fact pattern — nothing was destroyed, lost, altered or disclosed. There is no breach documentation to index, and a row would dilute the register with routine change approvals (#7717) |
| `knowledge-base/legal/audits/2026-05-17-sentry-ingest-window-auth-users-audit.md` | Matches the producer only on "CNIL Art 33 filing posture per brainstorm Decision #10" — a reference to filing posture, not a fact pattern assessed against Art. 4(12). Confirm alongside the row above at #7791 (#7717) |
| `knowledge-base/legal/audits/2026-09-03-implementation-record-7717-art-33-5-register.md` | Not a determination: an implementation record *about* this register. It necessarily quotes Art. 4(12) / Art. 33(5) and so matches the producer pattern, but it assesses no fact pattern and records no controller determination. Note it is **not** a CLO attestation — that artifact was not obtained and is tracked at #7791 (#7717) |
| `knowledge-base/legal/audits/2026-09-counsel-review-7717.md` | Not a determination: the **counsel review of this register**, added 2026-09-03 under the ship Phase 5.5 gate. It quotes Art. 4(12) and Art. 33(5) throughout in order to rule on the predicate, and so matches the producer pattern, but it assesses no fact pattern and records no controller determination. Every future counsel review of this register will need the same waiver — that is a known cost of scoping the producer to `audits/**`, not a defect (#7717) |
| `knowledge-base/legal/audits/2026-09-counsel-review-7625.md` | Not a determination: the **counsel review for the Art. 30 PA-7 amendment** (#7625), added 2026-09-04 under the ship Phase 5.5 gate. It cites Art. 4(12) only to record the *negative* — that an Art. 30(1) record-keeping incompleteness is not a personal-data breach and triggers no Art. 33/34 duty — and assesses no fact pattern: nothing was destroyed, lost, altered or disclosed. Same disposition as the #7440 row above: assessed and outside the inclusion predicate (#7717) |
| `knowledge-base/legal/audits/2026-09-03-clo-review-7622-pa7-r2-evidence-layer.md` | Not a determination: a **retrospective record**, written 2026-09-03, of the 2026-08-20 CLO review of PR #7622. It matches the producer because it transcribes that review's §(d) finding, which cites Art. 4(12) in order to conclude the omission was **not** a breach — Cloudflare was contractually covered throughout the omission window, so what was incomplete was the Art. 30 record of a lawfully-safeguarded transfer, not the safeguard. The citation is quoted history, not a determination made here (#7717) |
| `knowledge-base/legal/audits/2026-09-04-betterstack-source-split-7772.md` | Not a determination, and it matches the producer pattern only by **ruling one out**: the CLO ruling on the #7772 Better Stack Logs source split states in terms that no Art. 33/34 assessment arises. The split is a re-partitioning of one processor's storage — same recipient (Better Stack s.r.o.), same team `520508`, same cluster — and **no data has flowed to the new source**, because the `soleur-git-data` server has never been provisioned. A prospective PA-8 amendment with no fact pattern and no event: nothing was destroyed, lost, altered, disclosed or accessed. Same disposition and same reasoning as the `2026-08-counsel-review-7440.md` row above. Assessed and outside the inclusion predicate — not undetermined. Citing #7772. |

## Register maintenance

- **Custodian:** Soleur CLO role, per ADR-200. The `clo` agent maintains this register at ship
  time; `/soleur:incident` routes here for the `art_33_triggered: true` case.
- **Canonical-source column format (machine-readable — do not restyle).** The last column
  carries exactly one repo-relative path, backtick-delimited, and nothing else.
  `scripts/lint-legal-registers.sh` strips the backticks and resolves the path against the
  working tree; a row whose pointer does not resolve is an assertion failure — which, for the advisory window (#7787), is reported as a warning and does **not** block, while a fail-closed refusal blocks throughout. Stated precisely because this is the bullet a maintainer reads before restyling the column. A determination register
  whose pointers rot is worse than none.
- **Review cadence:** on every new determination, and on the Art. 30 register's quarterly
  review.
- **Withdrawn open item — the 2026-08-06 "status divergence" was not one.** An earlier revision
  of this register recorded that source as internally divergent and asserted "a performed CLO
  internal sign-off". The source contains **zero** occurrences of `signed.off` / `SIGNED-OFF` /
  `attested` and no `signed_off_at` / `signed_off_by` frontmatter — unlike the 2026-06-29 and
  2026-08-17 sources, which carry both. Its §Disposition says the CLO agent **performs** this v1
  internal sign-off, which allocates authority rather than recording that one occurred. The
  source's header already reconciles the apparent conflict: v1 attestation is *internal*,
  `draft-requires-counsel-review` refers to *external* counsel re-review, and `BLOCKED` is a
  disposition on conditions C1-C9. The register had invented a defect and attributed an
  unrecorded act to the CLO role.
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

## Counsel-review corrections — 2026-09-03 (#7717, PR #7782)

Appended by the CLO agent under the ship Phase 5.5 Counsel-Review CLO-Attestation Gate. The
review's audit is `knowledge-base/legal/audits/2026-09-counsel-review-7717.md` and its overall
disposition is **BLOCKED**. Nothing above is overwritten; each correction quotes the text it
supersedes, because a register that corrects itself by silent edit is a register a reader cannot
diff against a prior export.

> **Superseded 2026-09-03 (#7717):** in §Inclusion predicate, the sentence *"Measured 2026-09-03
> on `main`: **102** post-mortems under `knowledge-base/engineering/operations/post-mortems/`
> carry `art_33_triggered`, unchanged at this PR's HEAD"*, and its parenthetical *"measured 116 at
> the merge-base and 123 at HEAD"*. Re-measured at review against merge-base `9c9a485` and this
> branch's HEAD: **104** post-mortem files carry the field at the merge-base and **104** at HEAD
> (103 read `false`; one reads `"superseded-by-Phase-9"`). Repo-wide the figures are **118** at
> the merge-base and **126** at HEAD. The "unchanged at HEAD" observation stands; the four numbers
> do not. The argument is unaffected — the exclusion of screening outputs does not turn on the
> exact count — but a paragraph whose whole point is faulting an earlier revision for quoting
> unre-measured figures must not itself quote unre-measured figures. The same **102** also appears
> in ADR-200, in the header of `scripts/lint-legal-registers.sh`, and in Art. 30 counsel-review
> item 12; all four are wrong by the same two.

<!-- -->
> **Superseded 2026-09-03 (#7717):** in the 2026-05-16 row, the opening of the "Evidentiary limbs
> inconclusive?" cell reading *"**Partially — and narrower than the pre-Phase-9 record
> suggests.**"*. That cell answers its own column twice, in opposite directions: it opens
> **Partially**, then states *"**No — corrected twice, and the second correction was also
> wrong.**"*, then closes *"**No evidentiary limb remains open on this determination**"*. The
> correct headline answer is **No**. What the "Partially" clause actually carries is a discrepancy
> inside the source's own prose, which is not an open evidentiary limb, and it is retained below
> as that. A determination register must not hand a supervisory authority two answers to one
> question inside one cell — the half-applied replacement that leaves both drafts standing is a
> known defect class here (#7349).

<!-- -->
> **Superseded 2026-09-03 (#7717):** in the same cell, the clause *"which double-counts the 2
> signups already inside the 10"*. The observation that the source disagrees with itself is
> correct; the arithmetic names the wrong element. The post-mortem's §Summary (L150) reads
> "operator + 8 operator-adjacent accounts (founders, team, bot, internal QA / test) plus 2
> friends-of-team test signups" — eleven — against the ten its L144 paragraph and its L29
> frontmatter both give. 8 + 2 = 10 exactly, so the surplus of one is the **operator**, counted
> separately from the founders who already contain him. The 2 signups are counted once.

<!-- -->
> **Superseded 2026-09-03 (#7717):** the §Excluded records preamble reading *"Four rows are
> *assessed and outside* the inclusion predicate. Two — the 2026-05-15 and 2026-05-17 Sentry
> audits ... are **undetermined**, pending the CLO ruling requested at #7791, and are marked as
> such in their reason cells."* Two things moved under it. The counts are now **five assessed
> and outside, one ruled into the index and not yet moved there** — the table gained a seventh
> row for this review's own audit file, which is determination-shaped to the producer and is
> not a determination. And the pendency is discharged: the rulings are immediately below, so no
> row is undetermined any more. The preamble's *principle* — that a register must not assert a
> disposition it has not reached — is exactly right and is why the pendency was recorded rather
> than guessed.

### Rulings on the two waivers recorded as pending

Two §Excluded records rows read **"Disposition pending CLO ruling (#7791)"**. That pendency is
discharged here. #7791 stays open for the attestation itself.

**`audits/2026-05-17-sentry-ingest-window-auth-users-audit.md` — WAIVER UPHELD, on a stronger
ground than the one recorded.** The recorded reason — a filing-posture reference, not a fact
pattern — is true but thin, and thin reasons are what get re-litigated. The operative ground is
that the file is *evidence inside an already-indexed determination*: its frontmatter classifies it
`art-30-5-accountability-evidence`, its `incident_pir` names the very post-mortem the 2026-05-16
row indexes, and what it records is a population count, not a determination of its own. Indexing
it would enter one incident twice.

**`audits/sentry-migration-audit-2026-05-15.md` — WAIVER NOT SUSTAINED. This is the blocking
finding.** Its recorded reason is that the file "states no Art. 4(12) assessment, so whether it
satisfies the inclusion predicate's second limb is a legal call". The call is made here: **limb 2
is substantive, not citational.** A determination is an assessment of whether a personal-data
breach within the meaning of Art. 4(12) occurred. It does not become one by quoting the article
number and it does not stop being one by omitting it. Making a register's completeness a function
of a drafter's citation habit is the failure mode Art. 33(5) exists to prevent.

That reading is already load-bearing in this register, which is what makes the present allocation
inconsistent rather than merely arguable: **the 2026-05-16 row's own canonical source never cites
Art. 4(12) either** — verified at review, the post-mortem contains no occurrence of `4(12)`,
`Art. 4` or `Article 4` — yet it is indexed, and `scripts/lint-legal-registers.sh` pins it by
literal path so that nothing can remove it. One predicate cannot admit that file and exclude
`sentry-migration-audit-2026-05-15.md`, which records a controller-voice notifiability
determination in terms — *"No personal data left the EEA. Article 33 (72-hour breach
notification) does not trigger"* — on a suspected unlawful third-country transfer, which is a
fact pattern limb 1 expressly reaches ("an actual **or suspected** security event touching
personal data"), and which carries the remedial action Art. 33(5)'s triad asks for (the three
fixes shipped in PR #3863).

**The remediation is not applied here, deliberately.** That file must be indexed as its own row,
or excluded on a ground that is *held* rather than pending — and either change has to land in the
index table and in the guard's `NOT_TRANSCRIBED` array in the same commit, or assertion (d) reds
on the very parity it exists to protect. Rewriting a live gate's declared set inside a counsel
annotation is how the two copies drift; it is left to the PR. Whether the file earns its own row
or is recorded as subsumed by the 2026-05-16 row is a drafting call the reviewer does not make for
the author — the two matters share a root cause (the `jikigai-us` shadow org) but differ in
surface, and either treatment is defensible. Silence is not. **Until that lands, this register is
incomplete against its own stated predicate, and this paragraph is the record of it.**

---

> **DRAFT — This document was generated by AI and requires professional legal review before use. It does not constitute legal advice.**
