---
title: "CLO ruling — DPA template Schedule 4, TOM category 4: RLS posture misdescription corrected before first execution"
type: clo-ruling
date: 2026-09-15
issue: none — referred directly by the operator, not via a GitHub issue
pr: 8197
attestation-authority: clo
status: APPROVED (CLO-agent-ruled, Soleur-as-tenant-zero v1)
disposition: DISCHARGED — defect confirmed and corrected before first execution. No Art. 33 duty, no Art. 34 duty, NO breach-register row. No counterparty notification owed, because the instrument has never been executed. One Art. 30(1)(c) gap found and closed in the same change (PA-1 §(c), `denied_jti.reason`); the limb-(g) incompleteness alleged in an earlier draft was withdrawn as mischaracterised — see §7c. Scope widened 2026-09-15 on review: the same false universal was found live in §9 of the same instrument (a token-anchored sweep had missed it past the interposed word `database`), four further stale RLS assertions were found in `article-30-register.md` (Cross-Cutting TOMs, PA-14 §(g)(2), PA-14 §(d), and one limb asserting the dropped `scope_grants_owner_select` as live), and the correction falsified two downstream grounds that are corrected here — the `denied_jti` / `mint_rate_window` / `runtime_mint_intent` "not personal data" rationale at `apps/web-platform/server/dsar-export-allowlist.ts`, and the same ground in the PUBLISHED `docs/legal/data-protection-disclosure.md` and its Eleventy mirror, which carry a raw-file SHA pin re-pinned in this PR. An anti-recurrence gate is added at `scripts/check-tom4-rls-posture.sh`, asserting against the migration corpus rather than against any wording. Open items recorded for SEPARATE work, not resolved here: whether the DSAR-export machinery needs its own Processing Activity; the DPD §2.3 founder-filter framing; a `denied_jti.reason` CHECK constraint, `REDACT_PATHS` entry and Art. 16 rectification path; and `tenant_deploy_audit`'s occupancy-based exclusion ground, which expires at the second tenant.
signed_off_at: 2026-09-15
signed_off_by: "CLO agent (attestation authority for the Soleur-as-tenant-zero v1 posture; operator retains an optional veto)"
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "not due — no Art. 4(12) event occurred, so no clock started. The deployed control was at all times MORE restrictive than the text described; a misdescription in an unexecuted instrument is not a breach of security."
awareness_anchor: "2026-09-15 — the date the CLO measured the migration corpus against the template text. No earlier anchor is asserted, because no Art. 4(12) event is found; see §6."
execution_status: "UNEXECUTED. Five independent evidence lines at §5. The correction is therefore an edit, not an amendment to a live instrument."
tier_classification: "Internal control record that ALSO edits a published surface — reclassified 2026-09-15, after the §4 ruling brought `docs/legal/data-protection-disclosure.md` and its Eleventy mirror `plugins/soleur/docs/pages/legal/data-protection-disclosure.md` into scope. The earlier value asserted a knowledge-base-only edit and that none of the five `docs/legal/**` gates engaged; three of its four sentences became false when §4 was ruled, and it is replaced rather than amended. GATES THAT NOW ENGAGE: (1) raw-file SHA pin — `data-protection-disclosure` is pinned at `apps/web-platform/lib/legal/legal-doc-shas.ts`, so its entry MUST be re-pinned in this PR; (2) mirror-drift ratchet — canonical and mirror must be edited identically in one commit, which holds drift constant rather than growing it. GATES THAT RUN BUT PASS UNCHANGED: (3) scope-block placement — the edit adds no scope block, only a parenthetical change of ground; (4) heading-sequence parity — no heading is added, removed or reordered; (5) EXPECTED_COUNT sentinel — no legal document is added or removed. NOT APPLICABLE: the normalised body-equivalence check, whose `BODY_EQUIVALENCE_DOCS` roster is `terms-and-conditions`, `acceptable-use-policy` and `disclaimer`; `data-protection-disclosure` is not enrolled, so the raw SHA pin alone guards its canonical/mirror agreement. No numeral is asserted for this field, and the reason is now better than 'the siblings disagree': the siblings do disagree (Tier 3 at `2026-08-17-clo-ruling-cla-evidence-admin-bypass-7597.md` against Tier 1 at `2026-09-08-clo-attestation-7500-zot-last-err-redaction.md` for the same predicate), AND the Tier numerals defined at `knowledge-base/legal/tc-version-bump-policy.md` grade document-change materiality for version-bumping — a different axis from an attestation's own classification, which is what explains the divergence. The bump-policy axis is addressed at `semver:`."
semver: "No TC_VERSION bump: `TC_VERSION` and `TC_DOCUMENT_SHA` pin `docs/legal/terms-and-conditions.md`, which this PR does not touch, and bumping it would invalidate standing T&C acceptances over a change to a different document. Corrected 2026-09-15: the earlier value also claimed the correction touches no 'document under the SHA pin', which the §4 ruling falsified — `data-protection-disclosure` is pinned at `apps/web-platform/lib/legal/legal-doc-shas.ts` and its entry must be re-pinned in this PR. Verified against `knowledge-base/legal/tc-version-bump-policy.md` § 'Non-T&C legal docs': those eight documents are notice/disclosure documents with no version constant and no WORM acceptance ledger, their per-doc SHA serves drift-detection only, and the SHA refresh is UNCONDITIONAL on every canonical edit with no TC_VERSION-bump bypass. That section also requires CLO sign-off for Tier 1 and Tier 2 changes; the DPD edit reads as Tier 2 (clarifying — no new processing, no narrowed right, but the reader's understanding shifts), and this attestation is that sign-off."
brand_survival_threshold: single-user incident
written_against: "the committed migration corpus at `apps/web-platform/supabase/migrations/`, measured by the CLO on 2026-09-15 in the `fix-dpa-tom4-rls-posture` worktree — not against the engineering summary, and not against the live database (see §8)."
carve_outs:
  - "The corrected scope sentence is bounded to tables the migration corpus CREATES in the `public` schema, so that sentence alone does not reach `storage.objects`. Shape (v) of the corrected TOM 4 now states the object-store measure expressly, so this is a bound on one sentence rather than a gap in the Schedule. Corrected 2026-09-15: an earlier draft of this entry recorded the object store as an accepted GAP."
  - "Measured against the committed migration corpus, not against the live production database. See §8."
re_evaluation_triggers:
  - "A fifth RLS predicate shape entering the schema. The corrected text is written as an open enumeration precisely so this does not falsify it, but the Art. 30 register limb (g) for the new activity must record the shape, since the corrected text now defers to the register as authoritative."
  - "Promotion of the DPA template to `docs/legal/data-processing-agreement.md` and the Eleventy mirror. At that moment the five `docs/legal/**` CI gates attach, the document becomes a published surface, and Schedule 4 must be re-measured against the then-current corpus before publication."
  - "First execution with any counterparty. This ruling's entire materiality analysis rests on nobody having relied on the defective text. Once signed, any further inaccuracy in Schedule 4 is an Annex II defect in a live instrument and the analysis at §3 does not carry over."
  - "Any decision to add a storage-bucket TOM to Schedule 4, or to widen the scope sentence past the migration corpus. Either re-opens the accepted limit at §7 and requires `storage.objects` policies to be measured on the same footing as the corpus tables."
  - "Any out-of-band policy change applied to production without a migration. This would break the correspondence between the corpus and the live database that §8 relies on."
  - "Any widening of `denied_jti.reason` beyond an operator-authored revocation note — a length bound, a structured shape, or a second writer. PA-1 §(c) describes it as free text authored through `revoke_jti`; a different write path is a different category."
  - "First arms-length (non-Jikigai) Customer, EEA-out processing, or a regulated-industry counterparty — the standing triggers for EXTERNAL counsel re-review of this internal sign-off."
related:
  - knowledge-base/legal/data-processing-agreement-template.md
  - knowledge-base/legal/article-30-register.md
  - knowledge-base/legal/breach-register.md
  - knowledge-base/legal/tenant-dpa-register.md
  - knowledge-base/legal/compliance-posture.md
  - knowledge-base/legal/tc-version-bump-policy.md
  - docs/legal/data-protection-disclosure.md
  - plugins/soleur/docs/pages/legal/data-protection-disclosure.md
  - apps/web-platform/lib/legal/legal-doc-shas.ts
  - apps/web-platform/server/dsar-export-allowlist.ts
  - scripts/check-tom4-rls-posture.sh
  - scripts/lint-legal-registers.sh
---

# CLO ruling — DPA Schedule 4, TOM category 4

## Disposition: DISCHARGED. Defect confirmed; corrected before first execution; no notification owed.

This is the v1 internal counsel-review sign-off for the Soleur-as-tenant-zero
posture. It is performed by the CLO agent, not by the operator, per the
recurring-bug record at
`knowledge-base/project/learnings/workflow-patterns/2026-05-18-clo-attestation-auto-route-instead-of-human-task.md`.
It is an **internal** sign-off. External counsel re-review is reserved for the
re-evaluation triggers in the frontmatter.

---

## 1. What was referred, and what the text said

The operator referred a measured discrepancy between Schedule 4 TOM category 4 of
the customer-facing DPA template and the actual RLS posture of the Web Platform
schema, and asked for a binding characterisation, a scope determination, a reach
sweep, an execution-status finding, and replacement wording.

The text as it stood read, in relevant part:

> Per-tenant Row Level Security (RLS) policies on every table holding Customer
> Data. Three predicate shapes apply across the schema: (i) workspace-keyed
> tables ... (ii) per-founder ledgers (`scope_grants`, `template_authorizations`,
> `audit_byok_use`) use `auth.uid() = founder_id`; (iii) per-user surfaces
> (`action_sends`, `tc_acceptances`) use `auth.uid() = user_id`.

Two components are defective, and they are defective for different reasons.

---

## 2. Verification actually performed

Everything in this section was run by the CLO on 2026-09-15 in the
`fix-dpa-tom4-rls-posture` worktree. Figures are from those runs. The referral
carried its own measurement; it was **re-derived independently** rather than
accepted, because a prior instrument in this same referral chain had been found
to overstate (an earlier regex missed quoted policy names containing spaces).

### Method

All 257 files under `apps/web-platform/supabase/migrations/` were parsed with
SQL line-comments stripped and whitespace flattened, matching
`CREATE POLICY <bare-or-quoted-name> ON [public.]<table>` and the corresponding
`ALTER TABLE ... ENABLE ROW LEVEL SECURITY`.

**Two counting methods were run, and their agreement is the load-bearing
evidence.**

- **Cumulative** — every `CREATE POLICY` statement across the corpus.
- **Net live-state** — a sequential simulation over up-migrations only, adding on
  `CREATE POLICY` and removing on `DROP POLICY`, keyed by policy name.

The two methods disagree on per-table counts wherever a policy was later dropped
and recreated (`conversations` is 13 cumulative but 5 net; `scope_grants` is 3
cumulative but 1 net). **They return the identical 15-table zero-policy set**,
because none of the 15 appears in any `DROP POLICY` statement anywhere in the
corpus. A table that reads as zero-policy under both a cumulative and a
net-of-drops count was never policied at any point in the schema's history.

### Results

| Measure | Result |
|---|---|
| Migration files parsed | 257 |
| Tables with `ENABLE ROW LEVEL SECURITY` | **53** |
| Of those, with zero policies (both methods) | **15** |
| Tables created by the corpus, net of `DROP TABLE` | **52** (corrected 2026-09-15 from 51 — see below) |
| Of those, **missing** `ENABLE ROW LEVEL SECURITY` | **0** |

Positive controls, cumulative method: `conversations`=13, `api_keys`=1,
`users`=5, `scope_grants`=3, `action_sends`=2. All matched.

### The 15 zero-policy tables

`_schema_migrations`, `denied_jti`, `dsar_export_audit_pii`, `flag_flip_audit`,
`mint_rate_window`, `probe_tokens`, `processed_github_events`,
`processed_resend_events`, `processed_stripe_events`, `runtime_mint_intent`,
`statutory_repin_send`, `tc_acceptances`, `tenant_deploy_audit`, `tool_attempts`,
`workspace_member_actions`.

**Correction to the created-table count, 2026-09-15.** This table first recorded
**51** tables created net of `DROP TABLE`. The figure is **52**. The cause is the
same class as the defect under ruling: an unanchored `DROP TABLE` pattern matched
`ALTER PUBLICATION supabase_realtime DROP TABLE public.messages;` at migration
`039_drop_messages_from_realtime_publication.sql`, which changes a publication's
membership and drops no table. `messages` was therefore deleted from the model,
along with its two live policies, and the resulting count looked plausible enough
that two independent readers accepted it. **Nothing downstream moves.** The
`53` RLS-enabled and `15` zero-policy figures are unaffected (they are measured
over `ENABLE ROW LEVEL SECURITY`, not over creation), the zero-policy enumeration
is unchanged, and the scope sentence in TOM 4 and §9 is a universal rather than a
count — it holds at 52/52 exactly as it held at the misread 51/51. Found by
`scripts/check-tom4-rls-posture.sh`, which anchors `DROP TABLE` at statement
start; the anchored form is assertion 1's parser and is commented there.

### Per-claim verification of the text under review

| Claim in the text | Source read | Finding |
|---|---|---|
| `tc_acceptances` uses `auth.uid() = user_id` | `044_add_tc_acceptances_ledger.sql:73` | **FALSE.** `ENABLE ROW LEVEL SECURITY` is followed immediately by the migration's own comment: *"Zero policies: service-role-only via accept_terms / anonymise RPCs."* The migration contradicts the DPA in the same file. |
| `action_sends` uses `auth.uid() = user_id` | `051_action_class_widening_and_action_sends.sql:161-168` | **TRUE.** `USING (user_id = auth.uid())` / `WITH CHECK (user_id = auth.uid())`. |
| `scope_grants` uses `founder_id` | `048_scope_grants.sql:36` | TRUE. |
| `template_authorizations` uses `founder_id` | `053_template_authorizations.sql:208` | TRUE. |
| `audit_byok_use` uses `founder_id` | `037_audit_byok_use.sql:47` | TRUE. |
| `is_workspace_member` citation and `search_path` | `053_organizations_and_workspace_members.sql:116-121` | TRUE. `SECURITY DEFINER`, `LANGUAGE plpgsql`, `SET search_path = public, pg_temp`. The `plpgsql` choice is itself security-relevant and was added to the corrected text: the migration records that a `sql STABLE` function would be planner-inlined, dissolving the SECURITY DEFINER boundary back into the caller's tenant-JWT RLS context. |
| "policies on every table holding Customer Data" | the 15-table set, intersected with §1.2 | **FALSE.** Seven tables holding Customer Data carry no policy (§4). |
| "Three predicate shapes" | the corpus | **INCOMPLETE.** A fourth shape exists and governs seven Customer-Data tables. |

---

## 3. Characterisation of the defect

### (a) The false specific — `tc_acceptances`

**A notice defect under Art. 28(3)(c), and a misrepresentation in the
contractual instrument itself.**

Schedule 4 is not merely descriptive prose. Schedule 3 of this same template
provides that *"Annex II (Technical and Organisational Measures) cross-references
Schedule 4."* Schedule 4 therefore **becomes** Annex II to the Module 2 and
Module 3 SCCs on execution. SCC Clause 8.6(c) requires the Annex II description
to be specific and expressly *not generic*; Clause 14(a) requires the parties'
transfer-impact assessment to be conducted against it.

Stating that `tc_acceptances` enforces `auth.uid() = user_id` asserts a control
that does not exist. That is a false statement of fact about a technical measure
in a warranted annex.

### (b) The false universal and the incomplete closed enumeration

**RULED: (b) is a notice defect in its own right. The actual posture being
STRICTER than described does NOT cure it.** Three independent grounds.

**(i) Specificity failure.** Art. 28(1) requires the controller to engage only
processors offering *"sufficient guarantees"*; Art. 28(3)(c) requires the
processor to take Art. 32 measures; Art. 32(1) requires those measures to be
*"appropriate"*. The controller's own Art. 24 duty is to **verify**
appropriateness. It cannot perform that verification against a description that
does not correspond to the architecture. A description naming three shapes where
four exist fails SCC Clause 8.6(c) not through vagueness but through inaccuracy.

**(ii) The universal is false in its own terms.** *"RLS policies on every table
holding Customer Data"* asserts that a policy exists on each such table. Seven do
not have one. The assertion is about **mechanism**, and the asserted mechanism is
absent. A controller reading the text would conclude that a Web Platform user can
read their own row in `tc_acceptances` under an `authenticated` JWT. That is
wrong, and it is precisely the kind of inference a controller acts on — for
instance, telling a data subject that their consent records are visible to them
in-product, or scoping an Art. 15 response around a self-service read path that
does not exist.

**(iii) Understating by mis-describing still breaches the accuracy obligation.**
There is **no GDPR safe harbour for erring toward greater security in a
description.** Art. 5(1)(a) transparency and Art. 28(3) accuracy are
direction-neutral. Three concrete harms flow even where the deployed control is
stronger than the described one:

- **Contamination of the controller's own register.** The Customer's Art. 30(2)
  processor record and its Art. 30(1)(g) TOM entry inherit the wrong mechanism.
  We would be the proximate cause of a third party's defective statutory record.
- **Audit-right failure under Art. 28(3)(h).** An auditor instructed to test the
  stated control — verify the RLS predicate on `tc_acceptances` — finds no such
  control and records a **control failure**. The stronger real control does not
  rescue the finding, because the audited assertion is the one in Annex II, not
  the one in the database.
- **Tainted TIA.** Clause 14(a) transfer-impact assessment runs against Annex II.
  A wrong Annex II taints the assessment for every Module 3 sub-processor row.

### (c) The defect class, and the anti-recurrence measure

The structural fault was a **closed count** ("Three") plus a **universal**
("every") in a document that ages against a schema which does not. The correction
does not replace "Three" with "Four". It **removes the count entirely**, states
that the shapes are *"given by example and not as a closed enumeration"*, and
designates limb (g) of each Processing Activity in
`knowledge-base/legal/article-30-register.md` as the authoritative per-activity
record. A fifth shape arriving in a future migration will therefore not falsify
the paragraph.

---

## 4. Scope determination — which of the 15 hold Customer Data

DPA §1.2 defines Customer Data as *"All Personal Data that Customer (or a
Co-Member on Customer's behalf) submits to, or generates in, the Web Platform
under Customer's Web Platform subscription."* Two limbs: Art. 4(1) personal data,
**and** generated under the Customer's subscription.

### Tier A — Customer Data. Seven tables. Covered by the corrected text.

| Table | Personal data | Basis |
|---|---|---|
| `tc_acceptances` | `user_id`, `ip_hash`, `user_agent` | Art. 30 PA-11; generated on the Customer's user's ToS acceptance |
| `workspace_member_actions` | `actor_user_id`, `target_user_id`, roles | Art. 30 PA-20, whose §(c) limb names the subjects as *"workspace members (controllers' employees / contractors / collaborators)"* — squarely Customer Data |
| `dsar_export_audit_pii` | `user_id`, `requester_ip`, `user_agent` | Generated by rights-exercise under the subscription |
| `tenant_deploy_audit` | `founder_id`, `target_repo`, `oidc_jti` | Art. 30 register §(g) already records its zero-policy posture; generated by the Customer's deploys |
| `denied_jti` | `founder_id`, `reason` | Authentication-lifecycle state keyed to the data subject |
| `mint_rate_window` | `founder_id`, counters | Same |
| `runtime_mint_intent` | `user_id` | Same |

### The three ruled IN that the referral had placed as infrastructure

`denied_jti`, `mint_rate_window` and `runtime_mint_intent` were referred as
plausibly infrastructural. **They are ruled IN, with an express reservation
recorded here rather than left silent.**

A narrower commercial reading of §1.2 would call these "service operational data"
rather than Customer Data, on the basis that they carry no Customer-authored
content. That reading is available but is not the one §1.2 supports. Three
reasons:

1. Each row is keyed by a `user_id` or `founder_id` foreign key to a real account
   holder. A pseudonymous identifier resolvable by the controller is personal
   data within Art. 4(1); Recital 26 settles this. Being infrastructural does not
   remove it from Art. 4(1).
2. §1.2 as drafted is **content-agnostic**. It says "Personal Data ... generates
   in the Web Platform", not "content submitted by the Customer". Reading a
   content requirement into it would be re-drafting the definition inside a TOM
   schedule, which is the wrong instrument for that.
3. **Decisive:** the defect being corrected *is* under-inclusion. Resolving a
   genuine ambiguity toward exclusion, in the very act of fixing an
   under-inclusive description, would re-create the fault in a subtler form. When
   a scope question is close, the direction that does not repeat the defect is
   the correct one.

### Tier B — personal data, but NOT Customer Data. One table.

`flag_flip_audit`. Its `actor` column is CHECK-constrained to an email shape, and
the actor is a **Jikigai operator**, not a Customer data subject. This is
Jikigai's own staff-accountability data, processed by Jikigai **as controller**,
not as processor. It fails the second limb of §1.2. Naming it in a
processor-facing TOM as Customer Data would be an error in the opposite
direction, and it is deliberately absent from the corrected text.

### Tier C — not Customer Data; indirection only. One table.

`statutory_repin_send`. Columns are `item_id` (FK to `email_triage_items`),
`tick_key`, `created_at`; the migration states *"No user_id by design."* Its
parent `email_triage_items` is the inbound operational-email triage store
disclosed at DPD §2.3(aa), which is **Jikigai's own controller-side** processing
and not a Web Platform Customer surface. It fails both limbs: it holds no
personal data itself, and its parent activity is not under any Customer
subscription.

### Tier D — no personal data. Six tables.

`_schema_migrations` (schema version ledger); `probe_tokens` (token plus
timestamp); `tool_attempts` — the migration is explicit: *"NO
session/user/conversation column (anonymous per CRITICAL-2); NO tool_input
(NO-ECHO)"*; and the three webhook idempotency gates
`processed_github_events` (`delivery_id`), `processed_resend_events` (`svix_id`)
and `processed_stripe_events` (`event_id`, `event_type`), which hold opaque
vendor delivery identifiers with **no in-table link** to a data subject.

### The three ruled OUT that the referral had placed as plausibly personal

`flag_flip_audit`, `statutory_repin_send` and `tool_attempts` were referred as
plausibly holding personal data. Each is ruled out on a distinct ground, and none
of the three grounds is "it is small" or "it is internal":

- `flag_flip_audit` **does** hold personal data — an operator's email address —
  but Jikigai is the **controller** of it. The exclusion is a
  controller/processor boundary, not a personal-data finding.
- `statutory_repin_send` holds **no** personal data, and its parent activity is
  controller-side. Two independent exclusions; either alone would suffice.
- `tool_attempts` is **architecturally anonymous by construction**, not merely
  unlinked in practice. There is no user, session, or conversation column to
  join on.

Recording the grounds separately matters: if any of the three later acquires a
data-subject key, only the ground stated for that table needs re-testing.

---

## 5. Execution status — UNEXECUTED

**DETERMINED: this template has never been executed with any counterparty.**
Five independent evidence lines, each sufficient on its own and jointly
conclusive:

1. Frontmatter carries `not_yet_executed: true` and `status:
   draft-pending-trigger`.
2. `docs/legal/data-processing-agreement.md` **does not exist**. The template has
   never been published, and so was never even offered to a counterparty.
3. `knowledge-base/legal/data-processing-agreements/` contains only
   `anthropic.md` and `flagsmith.md`. Both are **inbound vendor DPAs in which
   Jikigai is the customer**. Neither is an outbound execution of this template.
4. `knowledge-base/legal/tenant-dpa-register.md` carries `status:
   draft-empty-template`; its Rows table reads `_(none yet)_`; and its §6.1
   baseline states that the rows table is empty.
5. `knowledge-base/legal/customer-dpa-register.md` **does not exist** — and the
   template's own custodian metadata directs that it be created *at first
   counter-signature*. Its absence is affirmative evidence of zero executions,
   not merely absence of evidence.

**Consequence.** The correction is an **edit**, not an amendment to a live
instrument. No Art. 28(3) amendment procedure, no counterparty re-consent, no
re-execution, and no §6.1 30-day sub-processor notification clock is engaged.

---

## 6. No Art. 33 and no Art. 34 duty; no breach-register row

**No Art. 4(12) personal-data breach occurred.** Art. 4(12) requires a breach of
security leading to accidental or unlawful destruction, loss, alteration,
unauthorised disclosure of, or access to, personal data. None of those limbs is
engaged:

- **Confidentiality:** not engaged. The deployed control (RLS enabled, zero
  policies, `service_role`-only, client access mediated by SECURITY DEFINER RPCs
  applying their own authorisation check) is **more restrictive** than the
  control the text described. No data was reachable by anyone who should not have
  reached it. Had the text been *true*, more parties would have had read access,
  not fewer.
- **Integrity:** not engaged. No alteration.
- **Availability:** not engaged. No loss or destruction.

A misdescription of a technical measure, in an instrument no counterparty has
signed, is a **notice defect**, not a security breach. **`art_33_triggered:
false`; `art_34_triggered: false`; NO BREACH ROW is added to
`knowledge-base/legal/breach-register.md`.** No supervisory-authority
notification. No threshold in the CLO downstream-specialist catalog at
`knowledge-base/legal/recommended-tools.md` is met.

Materiality is **prospective only**: the defect would have become material at
first execution, and it has been corrected before that point.

**Corrected 2026-09-15.** An earlier draft of the sentence above read *"NO row
is added to `knowledge-base/legal/breach-register.md`"*, which is false as
written: a single row **is** added to that file's `## Excluded records` waiver
table, recording why this ruling — which quotes Art. 33 and Art. 34 language — is
not a determination and carries no register row. The identical row is added to
the `NOT_TRANSCRIBED` array in `scripts/lint-legal-registers.sh`, because that
lint's assertion (d) checks the two halves for parity. The on-point precedent is
`2026-09-counsel-review-7625.md` (*"an Art. 30(1) record-keeping incompleteness
is not a personal-data breach"*); the 7786 and 7500 attestations are adjacent but
turn on different facts. The substantive holding is unchanged: no Art. 4(12)
event, and **no breach row**.

---

## 7. Reach of the correction, and the accepted `storage.objects` limit

### 7a. The defective claim existed at TWO sites, and the first sweep found only one

A sweep **by claim rather than by file** was run for RLS-qualified `every table`,
`all tables`, `each table`, and for `predicate shape`. It returned one hit and
**it was wrong**. A re-sweep tolerant of an interposed word
(`every [a-z]* ?table`) returns a second: §9 "Security TOMs", which reads *"RLS on
every **database** table holding Customer Data"* — the same false universal, about
the same tables, under the same heading name, in body text rather than an annex.
The single interposed word defeated all three phrase tokens.

**The methodological lesson is recorded because it cost a real defect.** A sweep
that tokenises on an exact phrase is a file-based sweep wearing a claim-based
disguise. Sweeping by claim means sweeping for the *proposition* — here, any
universal quantifier within a few words of a table noun — not for a remembered
wording of it. Left unfixed, §9 and Annex II would have contradicted each other
inside one signed instrument.

**A third phrasing, found on the same re-sweep.** `article-30-register.md`
Cross-Cutting TOMs read *"Row-Level Security on every **multi-tenant** table;
per-`user_id` isolation"* — the same proposition under a third qualifier, in the
very document the corrected TOM 4 originally designated authoritative. Three
sites, three wordings, one proposition: `every table` (found), `every database
table` (missed), `every multi-tenant table` (missed). Re-running the sweep by
**policy name** rather than by universal then found three further register limbs
citing `scope_grants_owner_select`, a policy dropped at migration
`059_workspace_keyed_rls_sweep`. All six sites are corrected in this PR, and the
mechanical successor to this sweep is `scripts/check-tom4-rls-posture.sh`, whose
assertion 21 resolves every policy name cited anywhere in the legal corpus against
a net-of-drops replay — the check that no wording can defeat. Running that
assertion by hand, before writing it, found the fifth stale site (PA-16 §(g)(6))
that ten review agents and two CLO passes had all missed.

| Site | Carries the claim | Action |
|---|---|---|
| `data-processing-agreement-template.md` Schedule 4 TOM 4 | **Yes** | **Corrected** |
| `data-processing-agreement-template.md` §9 "Security TOMs" | **Yes — missed by the first sweep** | **Corrected**, and recast as a summary that expressly creates no independent representation, so Schedule 4 governs alone |
| `knowledge-base/legal/article-30-register.md` Cross-Cutting TOMs | **Yes.** *"per-`user_id` isolation"* asserted unqualified as a corpus-wide Art. 32 measure — false for the seven zero-policy Customer-Data tables, and for the workspace-keyed and founder-keyed ones | **Corrected** — predicates now recorded per activity at limb (g) rather than asserted globally |
| `knowledge-base/legal/article-30-register.md` PA-14 §(g)(2) and §(d), and PA-16 §(g)(6) | **Yes, by naming a dropped policy.** All three asserted `scope_grants_owner_select` (`auth.uid() = founder_id`) as live; migration `059_workspace_keyed_rls_sweep` dropped it and replaced it with `scope_grants_workspace_member_select` | **Corrected** — each now names the live workspace-keyed policy and records that the readability dates from 059 |
| `docs/legal/*.md` | No RLS universal. But `data-protection-disclosure.md` carried the **ground** this correction falsifies: the Art. 15 exclusion for the revocation / rate-limit / mint tables rested on *"not personal data"*, which this PR's own Tier A classification and PA-1 §(c) amendment contradict | **Corrected** — the ground is changed, the exclusion is not. Published surface: SHA re-pinned, mirror edited identically |
| `plugins/soleur/docs/pages/legal/*.md` (published mirror) | Same — carries the identical fragment | **Corrected** — byte-identical edit in the same commit, per the mirror-drift ratchet |
| `apps/web-platform/server/dsar-export-allowlist.ts` | Not an RLS claim, but the same falsified ground: `denied_jti`, `mint_rate_window` and `runtime_mint_intent` were excluded from the Art. 15 bundle on the stated basis that they are *"not personal data"* | **Corrected** — the exclusions stand; their rationale now states the real ground (a dedicated route, not impersonality), matching the DPD wording |
| `plugins/soleur/skills/legal-generate/references/templates/dpa-global/template.md` and `dpa-us/template.md` (vendored via #8120) | No. Generic boilerplate: *"Logical access controls designed to manage electronic access to data and system functionality based on authority levels and job functions."* No RLS claim, no Soleur schema claim. | **None — and these MUST NOT be amended.** They are generation inputs for *other companies'* documents. Injecting Soleur schema facts into them would produce a template asserting a third party's database posture: a defect in the opposite direction. |
| `knowledge-base/legal/article-30-register.md` per-activity limb (g), zero-policy tables | **Already correct** for `tenant_deploy_audit`, `tc_acceptances` and `workspace_member_actions` (*"RLS with zero policies"*, *"RLS-zero-policies + named-role REVOKE matrix"*). Corrected 2026-09-15: an earlier draft marked the register **as a whole** "Already correct". That assessment was made only against these three per-activity limbs; the Cross-Cutting section and PA-14 were never reached, and both were stale — see the rows above | None for these three |
| `side-letter-template.md`, `delegation-consent-side-letter-template.md` | No RLS mentions | None |
| `2026-08-06-alpha-tester-processing-annex.md` | **Mentions RLS** — line 26 describes Schedule 4 as covering *"Supabase row-level security"* — but only to **disclaim** Schedule 4's applicability to the plugin-local flow. It restates no universal and asserts no predicate. (An earlier draft of this table recorded "no RLS mentions at all": the conclusion was right, the stated evidence was wrong.) | None |

**Self-contradiction check — corrected 2026-09-15: it was NOT negative.** An
earlier draft recorded *"the register was right and the DPA was wrong"*, so that
correcting the DPA removed an inconsistency without creating one. Measured
against the migration corpus, the register was right in three per-activity limbs
and wrong in four other places, and the DPA was wrong in two. Correcting only the
DPA would have left `article-30-register.md` asserting `per-user_id` isolation
corpus-wide and naming a policy dropped at migration 059 — while the corrected
Schedule 4 designates that same register **authoritative** for the per-activity
predicates. That is a twin document left stranded, and the corrigendum's claim to
resolve a corpus inconsistency would have been false for a second time. All six
sites are corrected in this PR, which is why its scope is wider than a
single-line fix.

**CI gates: two engage, three run and pass unchanged.** The DPA template is under
`knowledge-base/legal/`, so none of this PR's DPA edits touch a gated path. The §4
ruling, however, brings `docs/legal/data-protection-disclosure.md` and its Eleventy
mirror into scope. **Engaging:** the raw-file SHA pin (`data-protection-disclosure`
is pinned in `apps/web-platform/lib/legal/legal-doc-shas.ts` and must be re-pinned
here) and the mirror-drift ratchet (both copies edited identically, in one commit).
**Running but unchanged:** scope-block placement (no scope block added),
heading-sequence parity (no heading touched), and the EXPECTED_COUNT sentinel (no
document added or removed). `data-protection-disclosure` is not in
`BODY_EQUIVALENCE_DOCS`, so the normalised body-equivalence check does not reach it.
The DPA template's own promotion to `docs/legal/` remains future work, and the gates
attach to *that* document at that point — see the re-evaluation triggers.

**Scope note added 2026-09-15.** The "None" cells above record that those documents
do not carry the RLS universal, which remains true. They are **not** a statement
that this PR leaves every published document untouched: the §4 ruling edits
`docs/legal/data-protection-disclosure.md` and its mirror on a different ground —
the Art. 15 exclusion's "not personal data" rationale, falsified by this PR's own
Tier A classification. Two propositions share one table; keep them apart.

### 7a-bis. A sixth site, found by running the gate rather than by reading

**Assertion 21 of `scripts/check-tom4-rls-posture.sh` — every policy name cited
anywhere in the legal corpus must resolve to the net-of-drops live set — was run
against the corrected tree and failed on a site nobody had looked at.**
`article-30-register.md` PA-18 §(d) recorded *"cookie-scoped writes via
`template_authorizations_owner_insert` policy"* — a policy that was **dropped**
and never created. Migration `053_template_authorizations.sql:214` drops it,
with a comment saying it survived only in earlier drafts of that migration and
is dropped so that a re-run lands at the intended posture. There is no INSERT, UPDATE or
DELETE policy on `template_authorizations` at all; every mutation routes through
the SECURITY DEFINER `authorize_template` RPC.

**Direction matters and is recorded.** As with the shape-(iv) tables, the stated
posture was **weaker** than the deployed one — the register described a
client-held write path where none exists — so this is a notice defect of the
same class and not a security finding. It is corrected in this PR.

**This is the second time the gate's logic found what review did not.** Running
assertion 21 by hand, before writing it, found PA-16 §(g)(6); running the written
gate found PA-18 §(d). Ten review agents and three CLO passes read this corpus
and reached neither. That is the evidence for the CLO's ruling that the
enumeration should stay in the instrument and be **gated** rather than removed:
the mechanism catches what attention does not.

### 7b. The `storage.objects` limit is KNOWN AND ACCEPTED, not an oversight

**Stated explicitly, so it is not left to inference.**

The corrected scope sentence reads: *"Row Level Security (RLS) is enabled on
every table the Web Platform's migration corpus creates in the `public` schema."*

That bound is **deliberate**. `storage.objects` is provisioned by the Supabase
platform, not created by our migrations. It is RLS-enabled and carries policies
that our migrations amend, and Customer Data does live behind it — chat
attachments and workspace logos among them. But it falls **outside** the sentence
as written.

The corrected text therefore **does not misdescribe** `storage.objects`. It
simply does not reach it. This is the distinction that matters for Annex II
accuracy: a scoped statement that is true within its stated scope is not a
defect; an unscoped statement that is false outside its real scope is exactly the
defect this ruling corrects. Replacing one over-broad universal with a narrower
over-broad universal would have been no improvement.

**This limit is accepted for the present correction and recorded as a known
boundary, not as an oversight.** Whether Schedule 4 should additionally carry a
storage-bucket TOM describing `storage.objects` policies is a **separate
question that this ruling does not decide**. It is registered as a
re-evaluation trigger in the frontmatter, and it must be answered before the
template is promoted to `docs/legal/`.

### 7c. Art. 30 register — ruled correct-as-is on limb (g); one limb-(c) gap closed in this PR

**This section replaces an earlier draft that mischaracterised the register. The
correction is recorded rather than made silently, because a legal record that
misstates another legal record is the defect class this ruling exists to correct.**

The earlier draft asserted that `dsar_export_audit_pii`, `denied_jti`,
`mint_rate_window` and `runtime_mint_intent` lacked a §(g) entry recording their
zero-policy posture. **That framing was wrong and is withdrawn.** It imported a
table-enumeration standard that Art. 30 does not impose. Art. 30(1) records
processing *activities*; limb (c) requires *categories of personal data* and limb
(g) requires, *"where possible, a general description"* of the Art. 32 measures.
Neither requires a table inventory.

**On limb (g), all four tables are correct as they stand, and nothing is added:**

- `mint_rate_window` and `runtime_mint_intent` — the activity is recorded at
  **PA-1 §(g)(5)** (per-user JWT mint via `getFreshTenantClient(userId)`). The
  identifiers they hold are already within PA-1 §(c). No new category, no new
  measure.
- `denied_jti` — the measure is recorded by name at **PA-13 §(g)(4)**: *"the
  `is_jti_denied` deny-list (PR-D #3883) gates the mint."*
- `dsar_export_audit_pii` — its only §(g) mention is inside PA-2's limb, whose
  RLS sentence is scoped to `public.messages`, `public.conversations`,
  `public.team_names` and `public.user_concurrency_slots`. It asserts nothing
  about `dsar_export_audit_pii`. **No falsity.**

**One genuine gap exists, on limb (c) rather than (g), and is closed in this PR.**
`denied_jti.reason` is free text authored by the operator through the
service-role-only `revoke_jti(jti, founder_id, reason)` RPC (migration
`068_jti_deny_rls_predicate_and_revoke_rpc`), attributed to an identified account
holder, and **readable back by that data subject** through `my_revocation_status()`.
It is a category of personal data described nowhere in the register. PA-14 §(c)
already records `scope_grants.revoked_reason` on exactly that footing, so the
omission is an inconsistency with the register's own settled practice as well as a
limb-(c) gap. One clause is appended to PA-1 §(c). No §(g) item is added anywhere:
PA-13 §(g)(4) already carries the measure, and duplicating a measure across
activities is the drift mechanism this register records at PA-14 §(e) (corrected
2026-09-03, #7695).

**Deliberately NOT resolved here, and not folded into this PR.** No Processing
Activity appears to record the **DSAR-export machinery itself** as an activity —
`dsar_export_audit_pii` collects `requester_ip` and `user_agent` at download time,
and the register's per-activity `(h) DSAR` limbs record *reachability*, which is a
different thing. **This is not asserted as a finding:** the check was a targeted
grep, not a read of all 36 activities, and settling it requires a dedicated pass
over the whole register. It is registered as an open item for separate work.

---

## 8. Limits of this ruling

Two things were **not** verified, and are **not** asserted:

1. **The committed migration corpus was measured, not the live production
   database.** If any policy was created or dropped out-of-band against
   production without a migration, the measurement is wrong. Two mitigations are
   recorded rather than assumed: the corrected text is scoped to *what the corpus
   creates*, which is what was actually measured; and any out-of-band policy
   change is registered as a re-evaluation trigger, because it would break the
   corpus-to-database correspondence this ruling relies on.
2. **`storage.objects` is outside this analysis.** It was not measured on the
   same footing as the corpus tables, and no finding about it is made. See §7b
   for why this is an accepted limit of the corrected sentence rather than a gap
   in it.

---

## 9. What was corrected

Schedule 4 TOM category 4 was replaced in full, and a dated corrigendum was
appended to Schedule 4 recording the prior text, why it was wrong, that no
Customer relied on it, and that no Art. 33 or Art. 34 trigger arises. The
corrected text: states the fourth (service-role-only, zero-policy) shape;
replaces the false universal with a scope sentence bounded to the migration
corpus; removes `tc_acceptances` from shape (iii), leaving `action_sends`, which
was verified correct; names the Tier A tables governed by the fourth shape;
states expressly that the fourth shape is **more restrictive** than shapes
(i)-(iii) rather than an absence of them; and preserves the existing citation
style along with the `is_workspace_member` load-bearing sentence, extended to
name the fourth shape as equally load-bearing for the accountability ledgers.

No operational detail was introduced that is not already present in the committed
migration corpus. Every table name, RPC name, migration filename and predicate in
the corrected text was read from a committed migration during the verification at
§2.

---

> **DRAFT — This document was generated by AI and requires professional legal
> review before use. It does not constitute legal advice.** This is the v1
> internal sign-off for the Soleur-as-tenant-zero posture; external counsel
> re-review is reserved for the re-evaluation triggers in the frontmatter.
