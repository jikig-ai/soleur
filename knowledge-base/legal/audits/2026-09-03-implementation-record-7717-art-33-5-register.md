---
title: "Implementation record — Art. 33(5) breach register (#7717). NOT a CLO attestation."
type: implementation-record
date: 2026-09-03
issue: 7717
status: clo-attestation-outstanding
disposition: IMPLEMENTATION VERIFIED / CLO PER-ARTIFACT ATTESTATION NOT OBTAINED
attested_by: "NOBODY — see §What this document is not"
clo_rulings_obtained: [instrument-and-scope, frontmatter-identity-field]
clo_attestation_tracked_at: 7791
re_evaluation_triggers:
  - "On CLO attestation being obtained — this file is then superseded by it and should be deleted, not annotated."
  - "On any new determination being indexed, which requires its own per-artifact verdict."
  - "On counsel review of knowledge-base/legal/breach-register.md (Art. 30 register counsel-review item 12)."
---

# Implementation record — Art. 33(5) breach register (#7717)

## What this document is not

**It is not a CLO attestation, and it must not be cited as one.** The plan's task 1.13 called for
a CLO attestation at `knowledge-base/legal/audits/2026-09-03-clo-attestation-7717-art-33-5-register.md`.
That file was not written, and that path is deliberately left absent so nothing can mistake this
for it. Acceptance criterion **AC14 is NOT met**.

The reason is mundane and non-substantive: the `clo` agent was invoked to produce the attestation
and terminated on an API 529 (server-side overload) three times — request ids
`req_011CegcTbK6bQXipPMqhFHVS`, `req_011CegcmkyX9kXDsZxkqP2fn`, `req_011Cegd6WcbnQP2vaVHPMcTW`.
An attestation is an act of authority. Writing one and signing it `signed_off_by: CLO agent`
would fabricate a signature, which is precisely the defect class this issue exists to close — a
record asserting an authority it does not hold. So the gap is recorded instead of papered over,
and is tracked at **#7791**.

`knowledge-base/legal/breach-register.md` therefore remains `status: draft-requires-counsel-review`,
unchanged.

## What the CLO did rule

Two **binding** rulings were obtained from the `clo` agent before implementation and were applied
as given. These are the CLO's, not mine.

> **Superseded 2026-09-03 (#7717), same day, by the Phase 5.5 counsel review.** Ruling 1's METHOD
> was confirmed and each of its three original waivers holds line-by-line against its source, but its
> SET was revised: `audits/sentry-migration-audit-2026-05-15.md` satisfies both limbs on the
> substantive reading of limb 2 that the indexed 2026-05-16 row already relies on, and was moved from
> waived to indexed. The set is now **5 indexed / 6 waived** (the waived count also grew by the
> counsel-review audit itself, which is determination-shaped to the producer). See
> `knowledge-base/legal/audits/2026-09-counsel-review-7717.md` §B1. The paragraph below is retained
> as the record of what was ruled at the time.

**Ruling 1 — the determination set is 4 indexed / 3 waived, not the 7 the plan specified.** The
plan derived its set from the pinned regex `4\(12\)|33\(5\)|Art\. 33`, two paragraphs after
warning that "the discriminator is semantic and no regex makes a legal judgement". Applying the
conjunctive inclusion predicate — a breach-shaped fact pattern **and** an Art. 4(12) assessment
with a determination recorded — three of the six `audits/` matches fail the first limb:

| File | Ruling | Ground |
|---|---|---|
| `audits/2026-06-counsel-review-5103.md` | WAIVE | Regex false positive: the sole `Art. 33` occurrence verifies the accuracy of a statutory-deadline catalog entry. No event, no determination. |
| `audits/2026-08-counsel-review-7440.md` | WAIVE | Express Art. 4(12) assessment, but of a **prospective** PA-8 amendment. Indexing prospective clearances would turn the register into a log of routine change approvals, and an Art. 58(1)(a) reader could no longer distinguish incidents from housekeeping. |
| `audits/2026-05-12-gdpr-gate-plan-phase-2-7-outcome.md` | WAIVE | Never cites Art. 4(12); its non-notifiable statement is expressly attributed to *the operator's framing*, and indexing it would launder a framing into a controller determination. |
| `audits/2026-06-29-inngest-prd-rls-reachability-gdpr-determination.md` | INDEX | Both limbs; self-describes as the Art. 33(5) record. |
| `audits/2026-08-06-alpha-tester-controller-processor-determination.md` | INDEX | The close call, and it goes in: the source preserves the contrary Art. 4(12) argument as "not frivolous", and Art. 33(5) exists so an authority can verify determinations concluding *no* notification. Omitting the closest-run call in the corpus is the omission that costs credibility. |
| `audits/2026-08-17-clo-ruling-cla-evidence-admin-bypass-7597.md` | INDEX | A real security-control bypass on a surface PA-7 §(c) confirms processes personal data; exposure measured NIL rather than assumed. |
| `post-mortems/sentry-phantom-ingest-destination-unreachable-postmortem.md` | INDEX | The most breach-shaped pattern in the corpus (~49-day live window). Outside the guard's producer scope, so it needs no waiver. |

Exclusions are committed with reasons in `scripts/lint-legal-registers.sh` and mirrored
human-readably in the register's §Excluded records. That is the CLO's structural answer to the
objection that a semantic predicate lets a real determination be dropped silently.

**Ruling 2 — `controller:`, not `processor:`; AC1's field list overruled.** The Art. 30(2)
register carries `processor:` because that field names *the capacity in which the register is
kept*, and Art. 30(2) records are processor-capacity records. Art. 33(1) and 33(5) both bind "the
controller" on their face; a processor's duty is the Art. 33(2) duty to notify the controller,
which carries no register of its own. AC1 forbade the correct field because its list was derived
by diffing the two existing registers rather than from the principle. AC1's other prohibitions
(`version`, `last_reviewed`, `dpo`, `contact`) stand.

## What I verified, and what that is worth

The verdicts below are **implementation verification by the engineering agent**, not legal
attestation. Each is a statement that the artifact exists and has the asserted shape — nothing in
this section is a judgement that the artifact is legally adequate.

| Artifact | Verified | Method |
|---|---|---|
| `knowledge-base/legal/breach-register.md` | Present; 4 rows; frontmatter per Ruling 2 with 0 forbidden fields; scope paragraph disclaims #3686 | AC1-AC4 literal commands |
| PA-8 §(f) effective time-retention -> `NOT RECORDED` | Present with mechanism, the one API-available emission figure, and its three caveats | AC8; PA-8 read |
| PA-8 §(f) Better Stack retention -> `NOT RECORDED` | Present with reason + unblocking condition (`verify_by=2026-09-16`; #7529); the stale free-tier `~3 days` figure named as unusable | AC8 |
| Vendor Mapping DPA status -> `NOT EXECUTED` | "signed" removed; cites #7529; carries 2026-11-13 | AC9 literal command |
| `compliance-posture.md` `__TBD_DPA_DATE__` | Resolved; 0 standalone markers across all four register files | AC8 |
| `compliance-posture.md` AC15 narrowing | Stale "has never been filed" gone; substantive execute-or-record limb retained | AC10 |
| Second 2026-06-29 addendum | Present in all three siblings, each naming `auth_logs` and `postgrest_logs` and stating the verdict unaffected; no fence transcribed | AC5, AC7 |
| PA-8 §(g) — Art. 33 evidentiary-chain limitation | Present, citing the log contract and ADR-197 | AC11 |
| PA-8 §(g) — durable-sink item | Present, named OPEN, citing #5697 | AC11 |
| Non-scope: no retention TOM for the Supabase log surface | Stated in both PA-8 and the register | AC12 |
| Three pointer legs | Canonical record, Art. 30 §Register Maintenance, and `statutory-response-catalog.md` (both its accountability-pack step and its `related:` frontmatter) | grep per leg |
| No new Processing Activity | 35, unchanged | AC13 literal command |
| ADR-200 | Present; governs instrument, predicate and maintaining surface; all three maintaining-surface claims made true | grep per claim |

**One CLO-supplied table cell was corrected against its source before it landed**, because AC4
requires every cell grep-validated. The Sentry row's "evidentiary limbs inconclusive" cell as
drafted cited "no arms-length external-party exposure positively confirmed" — a statement from
L150 of the post-mortem, which **predates Phase 9**. Phase 9 closed both questions the cell
turned on: Sentry support confirmed in writing on 2026-05-19 that both `jikigai` and `jikigai-eu`
are owned by the operator's user and that every audit-log action in both was performed by it, and
the affected population is enumerated as operator + 8 operator-adjacent accounts + 2
friends-of-team signups. The cell now reads **Partially** and names the actual residual: the
granular causal mechanism of the token-membership boundary at Theory state T3, `NOT YET TESTED`,
with T0 falsification holding in every causal variant — an engineering residual, not an
evidentiary limb bearing on the Art. 33 / Art. 34 conclusion. **This correction has not been
ratified by the CLO** and is one of the specific things #7791 must review.

## Two open items carried forward

**The 2026-08-06 source's status is internally divergent** — frontmatter
`status: draft-requires-counsel-review` and a `BLOCKED` disposition coexist with a performed CLO
internal sign-off in the same file. The register **records the divergence rather than resolving
it**, in the row's evidentiary-limbs cell. It needs its own attestation pass; it is not resolved
by this work.

**The Sentry post-mortem's L110 compliance checkbox is stale, verified.** It carries an unticked
`- [ ] Update PA8 §5(2) … add a positive disclosure of the 2026-03-28 → 2026-05-16
phantom-ingest window`, while a later line in the same file reports it recorded via a PR-2 UPDATE
block. Art. 30 PA-8 §(d) does carry a dated **2026-05-19 UPDATE** block disclosing and then
superseding that window, so the obligation is met and the checkbox is stale. Recorded in the
register's §Register maintenance so the next reader does not re-derive it. The checkbox itself is
left unticked — it sits in a dated post-mortem, and ticking a box in one is a claim about that
record rather than about the register.

## Disposition

**Implementation: VERIFIED.** AC1-AC13 all pass against their literal commands.

**Attestation: NOT OBTAINED.** AC14 unmet. Tracked at **#7791**. The register stays
`draft-requires-counsel-review`, and Art. 30 counsel-review item 12 remains open for the
instrument choice and the inclusion predicate.

Nothing in this document discharges an Art. 33(5) obligation. The per-incident determinations in
the canonical records do that, and they did so before this register existed.

## Counsel-review supersessions — 2026-09-03 (#7717, PR #7782)

Appended by the CLO agent under the ship Phase 5.5 Counsel-Review CLO-Attestation Gate; audit at
`knowledge-base/legal/audits/2026-09-counsel-review-7717.md`, overall disposition **BLOCKED**.
This file's `attested_by: "NOBODY"` frontmatter was the right call and is undisturbed — refusing
to sign an attestation that was not performed is the behaviour #7717 exists to institutionalise.
What is corrected below is two statements this record makes *about the implementation*: both
describe a draft that did not ship.

> **Superseded 2026-09-03 (#7717):** §Two open items carried forward, first item, reading *"The
> 2026-08-06 source's status is internally divergent — frontmatter
> `status: draft-requires-counsel-review` and a `BLOCKED` disposition coexist with a performed CLO
> internal sign-off in the same file. The register **records the divergence rather than resolving
> it**, in the row's evidentiary-limbs cell."* Both halves are false against what shipped. The
> register does not record that divergence — it **withdraws** it, in the §Register maintenance
> bullet headed "Withdrawn open item". And there was no divergence to record: the 2026-08-06
> source contains zero occurrences of `signed off` / `SIGNED-OFF` / `attested` and carries no
> `signed_off_at` or `signed_off_by` frontmatter (verified at review), while its
> attestation-authority paragraph reads "The CLO agent **performs** this v1 *internal* sign-off" —
> a sentence allocating authority, not one recording that an act occurred. The row's
> evidentiary-limbs cell records the RNE *pouvoirs* directory-listing limb instead, and says
> expressly that the document-workflow point it replaced was not an evidentiary limb.

<!-- -->
> **Superseded 2026-09-03 (#7717):** §What I verified, the paragraph reading *"The cell now reads
> **Partially** and names the actual residual: the granular causal mechanism of the
> token-membership boundary at Theory state T3, `NOT YET TESTED`, with T0 falsification holding in
> every causal variant — an engineering residual, not an evidentiary limb"*. The cell that landed
> says the opposite of its central fact: T3 was **RESOLVED 2026-05-21 and promoted to T4**
> (post-mortem frontmatter `t3_resolved_at: "2026-05-21T07:00:00Z"` and `t3_mechanism:
> "T4-internal-integration-proxy-user-membership-boundary"`; evidence at
> `knowledge-base/legal/audits/2026-05-21-sentry-token-t3-resolution.md`), and the cell closes
> "No evidentiary limb remains open on this determination". The unresolved-T3 phrasing is the
> post-mortem's own 2026-05-19 Phase 9 text, which that file's later line supersedes. This record
> described the draft it had corrected rather than the cell it shipped — which is the same defect
> in miniature that the whole PR is about.

**Neither supersession disturbs the disposition.** Implementation remains VERIFIED against
AC1-AC13 as this record states, and the attestation gap it refuses to paper over remains real. The
counsel review's own blocking finding is separate and is recorded in the register's
§Counsel-review corrections: the inclusion predicate is applied inconsistently, and
`audits/sentry-migration-audit-2026-05-15.md` — a controller-voice notifiability determination —
is outside the index on a ground that does not hold.

---

> **DRAFT — This document was generated by AI and requires professional legal review before use. It does not constitute legal advice.**
