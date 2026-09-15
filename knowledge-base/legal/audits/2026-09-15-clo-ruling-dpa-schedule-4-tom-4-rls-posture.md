---
title: "CLO ruling — DPA template Schedule 4, TOM category 4: RLS posture misdescription corrected before first execution"
type: clo-ruling
date: 2026-09-15
issue: none — referred directly by the operator, not via a GitHub issue
attestation-authority: clo
status: APPROVED (CLO-agent-ruled, Soleur-as-tenant-zero v1)
disposition: DISCHARGED — defect confirmed and corrected before first execution. No Art. 33 duty, no Art. 34 duty, NO breach-register row. No counterparty notification owed, because the instrument has never been executed. One advisory Art. 30 register incompleteness recorded as an open item; it does not block.
signed_off_at: 2026-09-15
signed_off_by: "CLO agent (attestation authority for the Soleur-as-tenant-zero v1 posture; operator retains an optional veto)"
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "not due — no Art. 4(12) event occurred, so no clock started. The deployed control was at all times MORE restrictive than the text described; a misdescription in an unexecuted instrument is not a breach of security."
awareness_anchor: "2026-09-15 — the date the CLO measured the migration corpus against the template text. No earlier anchor is asserted, because no Art. 4(12) event is found; see §6."
execution_status: "UNEXECUTED. Five independent evidence lines at §5. The correction is therefore an edit, not an amendment to a live instrument."
tier_classification: "Internal control record with a knowledge-base-only document edit. The corrected document is `knowledge-base/legal/data-processing-agreement-template.md`, which is unpublished and unexecuted. No document under `docs/legal/**` changes, so none of the five gates (scope-block placement, mirror-drift ratchet, raw-file SHA pin, heading-sequence parity, EXPECTED_COUNT sentinel) are engaged. Those gates attach on promotion to `docs/legal/` plus the Eleventy mirror, not on this edit."
semver: "No TC_VERSION bump. The correction does not touch ToS §3b.4 or any document under the SHA pin."
brand_survival_threshold: single-user incident
written_against: "the committed migration corpus at `apps/web-platform/supabase/migrations/`, measured by the CLO on 2026-09-15 in the `fix-dpa-tom4-rls-posture` worktree — not against the engineering summary, and not against the live database (see §8)."
known_accepted_limits:
  - "The corrected scope sentence is deliberately bounded to tables the migration corpus CREATES in the `public` schema. It therefore does NOT reach `storage.objects`, which is provisioned by the Supabase platform rather than by our migrations. This is a KNOWN AND ACCEPTED limit of the sentence, not an oversight. See §7."
  - "Measured against the committed migration corpus, not against the live production database. See §8."
re_evaluation_triggers:
  - "A fifth RLS predicate shape entering the schema. The corrected text is written as an open enumeration precisely so this does not falsify it, but the Art. 30 register limb (g) for the new activity must record the shape, since the corrected text now defers to the register as authoritative."
  - "Promotion of the DPA template to `docs/legal/data-processing-agreement.md` and the Eleventy mirror. At that moment the five `docs/legal/**` CI gates attach, the document becomes a published surface, and Schedule 4 must be re-measured against the then-current corpus before publication."
  - "First execution with any counterparty. This ruling's entire materiality analysis rests on nobody having relied on the defective text. Once signed, any further inaccuracy in Schedule 4 is an Annex II defect in a live instrument and the analysis at §3 does not carry over."
  - "Any decision to add a storage-bucket TOM to Schedule 4, or to widen the scope sentence past the migration corpus. Either re-opens the accepted limit at §7 and requires `storage.objects` policies to be measured on the same footing as the corpus tables."
  - "Any out-of-band policy change applied to production without a migration. This would break the correspondence between the corpus and the live database that §8 relies on."
  - "First arms-length (non-Jikigai) Customer, EEA-out processing, or a regulated-industry counterparty — the standing triggers for EXTERNAL counsel re-review of this internal sign-off."
related:
  - knowledge-base/legal/data-processing-agreement-template.md
  - knowledge-base/legal/article-30-register.md
  - knowledge-base/legal/tenant-dpa-register.md
  - knowledge-base/legal/compliance-posture.md
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
| Tables created by the corpus, net of `DROP TABLE` | 51 |
| Of those, **missing** `ENABLE ROW LEVEL SECURITY` | **0** |

Positive controls, cumulative method: `conversations`=13, `api_keys`=1,
`users`=5, `scope_grants`=3, `action_sends`=2. All matched.

### The 15 zero-policy tables

`_schema_migrations`, `denied_jti`, `dsar_export_audit_pii`, `flag_flip_audit`,
`mint_rate_window`, `probe_tokens`, `processed_github_events`,
`processed_resend_events`, `processed_stripe_events`, `runtime_mint_intent`,
`statutory_repin_send`, `tc_acceptances`, `tenant_deploy_audit`, `tool_attempts`,
`workspace_member_actions`.

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
false`; `art_34_triggered: false`; NO row is added to
`knowledge-base/legal/breach-register.md`.** No supervisory-authority
notification. No threshold in the CLO downstream-specialist catalog at
`knowledge-base/legal/recommended-tools.md` is met.

Materiality is **prospective only**: the defect would have become material at
first execution, and it has been corrected before that point.

---

## 7. Reach of the correction, and the accepted `storage.objects` limit

### 7a. The defective claim existed at exactly one site

A sweep **by claim rather than by file** — for RLS-qualified `every table`,
`all tables`, `each table`, and for `predicate shape` — across
`knowledge-base/`, `docs/` and `plugins/` returns **one legal-corpus hit**: the
DPA template line now corrected. The only other `predicate shape` matches are
engineering brainstorms and specs, which make no counterparty representation.

| Site | Carries the claim | Action |
|---|---|---|
| `knowledge-base/legal/data-processing-agreement-template.md` Schedule 4 TOM 4 | **Yes — sole site** | **Corrected** |
| `docs/legal/*.md` | No. Every RLS reference is activity-scoped — the beta-CRM tables in `gdpr-policy.md`, `audit_byok_use` in `data-protection-disclosure.md`. No universal, no shape enumeration. | None |
| `plugins/soleur/docs/pages/legal/*.md` (published mirror) | No — mirrors the same scoped statements | None |
| `plugins/soleur/skills/legal-generate/references/templates/dpa-global/template.md` and `dpa-us/template.md` (vendored via #8120) | No. Generic boilerplate: *"Logical access controls designed to manage electronic access to data and system functionality based on authority levels and job functions."* No RLS claim, no Soleur schema claim. | **None — and these MUST NOT be amended.** They are generation inputs for *other companies'* documents. Injecting Soleur schema facts into them would produce a template asserting a third party's database posture: a defect in the opposite direction. |
| `knowledge-base/legal/article-30-register.md` | **Already correct** for `tenant_deploy_audit`, `tc_acceptances` and `workspace_member_actions` (*"RLS with zero policies"*, *"RLS-zero-policies + named-role REVOKE matrix"*) | None |
| `side-letter-template.md`, `delegation-consent-side-letter-template.md`, `2026-08-06-alpha-tester-processing-annex.md` | No RLS mentions at all | None |

**Self-contradiction check: negative.** The register was right and the DPA was
wrong. Correcting the DPA **removes** an existing corpus inconsistency rather
than creating one. No twin document is left stranded.

**CI gates: none engaged.** The corrected file is under `knowledge-base/legal/`,
not `docs/legal/**`. No SHA re-pin, no drift-baseline interaction, no
`BODY_EQUIVALENCE_DOCS` concern. The template's custodian metadata does commit
the document to the canonical/mirror pair **at publish**; those gates attach on
promotion, not on this edit.

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

### 7c. Advisory open item — Art. 30 register incompleteness

The register records the zero-policy TOM for three of the seven Tier A tables.
`dsar_export_audit_pii`, `denied_jti`, `mint_rate_window` and
`runtime_mint_intent` have **no** §(g) entry recording it. That is an
**incompleteness, not a falsity** — nothing in the register is wrong — and it
does **not** block this correction, which is why it is recorded as advisory. It
warrants its own issue. The dependency runs one way and is worth noting: the
corrected DPA text now designates the register as the authoritative per-activity
record, so register completeness matters more after this correction than it did
before.

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
