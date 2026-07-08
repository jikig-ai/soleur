---
title: "Legitimate Interest Assessment — Owner-private beta-tester / prospect CRM capture store"
type: legitimate-interest-assessment
date: 2026-07-07
plan: knowledge-base/project/plans/2026-07-07-feat-beta-conversation-capture-plan.md
adr: knowledge-base/engineering/architecture/decisions/ADR-102-beta-crm-capture-store-per-tenant-owner-private-agent-native.md
issue: 6165
status: draft-requires-counsel-review
controller: "The Web Platform user (operator) is the controller for the third-party personal data recorded; Jikigai SARL (France; 25 rue de Ponthieu, 75008 Paris) is the processor operating the store"
processing_activity: "Owner-private beta-tester / prospect CRM capture store — Article 30 register Processing Activity 30"
lawful_basis: "Art. 6(1)(f) GDPR — legitimate interest"
data_subjects: "Beta testers / prospects the operator converses with (involuntary third-party data subjects); the operator (owner)"
related:
  - knowledge-base/legal/article-30-register.md (PA-30)
  - docs/legal/data-protection-disclosure.md (§2.3(ad), §5.3)
  - docs/legal/privacy-policy.md (§4.7)
  - docs/legal/gdpr-policy.md (§3.13, §6)
---

# Legitimate Interest Assessment — Owner-private beta-tester / prospect CRM

**Draft — requires professional legal review.** This LIA records the Art. 6(1)(f) three-part balancing test for the owner-private beta-tester / prospect CRM capture store (feat-beta-conversation-capture #6165, ADR-102, migration 126). It is the companion to Article 30 Processing Activity 30 and is referenced by the migration's per-column `LAWFUL_BASIS` annotations.

**Controller / processor posture.** The store holds personal data about **third parties** (the people and teams the operator converses with). The **operator is the controller** for that data; **Jikigai is the processor** operating the store on the operator's behalf. This LIA documents the legitimate-interest basis on which that third-party data is processed.

---

## Purpose

The operator is onboarding Soleur's first beta testers and is having many sales and product conversations. These carry both **sales** signal (interest, objections, deal potential) and **product** signal (pain points, feature requests) and today have no private, structured home. The purpose of the processing is to give the operator:

- a **private, structured record** of each contact/opportunity and the conversations held with them (one dual-lens record per conversation), and
- an **agent-reachable** capability so the `cro`/`cpo` agents can read AND write the records (create a contact, append a note, move a stage) rather than the records being dead documents, and
- **pipeline fields** (stage, stage-transition timestamps, amount/currency) that feed `pipeline-analyst` for weighted-pipeline reasoning.

This is ordinary **business-relationship management** — the electronic equivalent of the notes a founder keeps about the people they are selling to and learning from. It is a per-tenant Soleur capability every future workspace inherits, so the compliance scaffolding (this LIA, PA-30, retention, DSAR) is part of the capability.

**Not pursued under this LIA:** any outbound send authority to the contacts (that is covered separately by the outbound-email LIA, 2026-06-15); any tester-visible surface / agent-user parity for the third-party subject (deferred); any special-category (Art. 9) processing.

---

## Necessity

The processing is necessary for the purpose, and the chosen architecture is the **least intrusive** that achieves it:

1. **A database boundary, not git.** Third-party PII is stored in per-tenant Supabase Postgres tables under owner-only RLS — **never committed to git**. Git-committed third-party PII would be an Art. 17 erasure impossibility (git history is permanent) and is invisible to the commit secret-scanner. The DB boundary is load-bearing, not incidental.
2. **Owner-only access.** Row-Level Security scopes every read to `user_id = auth.uid()`; no other tenant can read the store. There is no owner-write RLS policy — writes go only through `auth.uid()`-pinned SECURITY DEFINER functions, so the authorization gate cannot be bypassed.
3. **Data minimisation.** The schema captures only relationship-relevant fields the operator would otherwise keep in ad-hoc notes (contact identity, pipeline state, conversation notes). No special-category field exists; the free-text `body` is an incidental ingress the operator is instructed to keep free of Art. 9 data. `amount` is nullable with an `amount_basis` discriminator so directional beta figures are not conflated with committed pipeline.
4. **Agent path minimised and gated.** The `cro`/`cpo` agents reach the store through a narrow tool surface; **write tools are human-gated** (the operator approves each agent write). Record content is transmitted to Anthropic (US) only to enable that reasoning, under the existing Anthropic DPA.
5. **Bounded retention.** A 24-month `pg_cron` sweep from `last_contact` (or `created_at` for never-contacted rows) enforces storage limitation (Art. 5(1)(e)).

No less-intrusive alternative achieves the purpose: a git-markdown store fails the erasure and confidentiality tests; an external SaaS CRM adds a new sub-processor + US residency + a separate erasure path; a self-hosted OSS CRM is a whole second app with weaker app-layer scoping (see ADR-102 §Alternatives). Extending the app DB with owner-only RLS is the minimal footprint.

**Conclusion:** the processing is necessary and proportionate to the purpose; the architecture is the least-intrusive option that delivers a private, agent-reachable, compliance-bounded store.

---

## Balancing

### (i) Nature of the controller's interests

The operator's interest in keeping structured, actionable records of their own sales/product conversations is a routine, legitimate commercial interest (business-relationship management; Recital 47 recognises relationship management and direct marketing-adjacent purposes as capable of being legitimate interests). The interest is real and present — the operator is actively onboarding beta testers this week.

### (ii) Nature of the data and data subjects

The data is **business-context personal data** about professionals in their professional capacity (name, employer, role, and the substance of a business conversation). It is **not** special-category data (Art. 9): no health, political, biometric, or similar data is sought, and the free-text `body` is guarded by operator guidance + the tool envelope. The data subjects are the beta testers / prospects — **involuntary third parties** whose data is recorded in the course of a conversation, so the balance must be earned by safeguards rather than assumed, and Art. 14 transparency applies (below).

### (iii) Reasonable expectations of the data subject

A professional who has a sales or product conversation with a founder reasonably expects the founder to keep notes of that conversation for follow-up — this is ordinary business practice. The impact is within the reasonable expectation of a business relationship, provided the notes are (a) not shared beyond the controller, (b) retained no longer than necessary, and (c) the subject is informed and can object. All three are provided.

### (iv) Impact on the data subject

The impact is **low and bounded**: the records are owner-private (no other tenant can read them); there is no profiling, scoring, or automated decision-making about the subject (Art. 22 negative determination); retention is capped at 24 months; and the subject has an implementable erasure path. The principal residual risk — within-tenant prompt-injection over an untrusted conversation `body` driving the agent to overwrite a real contact's record — is mitigated by the human-approval gate on every agent write (the operator reviews each write in-session at single-user scale).

### (v) Safeguards (TOMs — Art. 32 cross-reference, full list in PA-30 §(g))

- Owner-only RLS SELECT; no owner-write RLS policy; table-level INSERT/UPDATE/DELETE REVOKEd from all client roles **and** `service_role`.
- Writes RPC-only through `auth.uid()`-pinned SECURITY DEFINER functions (`search_path` pinned) that re-check ownership under `SELECT … FOR UPDATE` and reject missing/foreign rows with the same error (no existence oracle).
- Composite FK `(contact_id, user_id)` makes a cross-tenant child mis-stamp a DB error.
- RESTRICTIVE `<table>_jti_not_denied` policy: a revoked/stolen founder JWT used directly against PostgREST is rejected at the policy boundary.
- Append-only history (notes + transitions) by RLS shape; a migration-body guard test asserts the RPCs never UPDATE/DELETE history.
- PII-safe observability: the agent tools mirror only `{op, userId, code}` via a synthetic error — the raw Postgres error (whose DETAIL carries `name`/`company`/`body`) is never forwarded to error-monitoring.
- Human-gated agent write tools (the within-tenant-injection mitigation).
- No third-party PII in git; 24-month retention sweep.

### Art. 14 transparency for involuntary data subjects

Because the contact details and conversation content are **not obtained from the data subject via a form they submitted**, Art. 14 applies. Unlike the inbound operational-mail LIA (2026-06-11), which relies on the Art. 14(5)(b) disproportionate-effort posture for anonymous inbound senders, here **notice is feasible**: the operator is in direct, identified contact with the subject. The Art. 14 notice mechanism is therefore: the operator informs the beta tester, at or shortly after first contact, that they keep private notes of the conversation for follow-up, on a legitimate-interest basis, retained for up to 24 months, and that the tester may object or request erasure at `legal@jikigai.com`. (A short standard notice line the operator can paste into a first-contact message satisfies this.) The required Art. 14(1) information — controller identity, purpose, legitimate-interest legal basis, categories/source of data, retention, and rights including objection and erasure — is carried by this notice together with the Privacy Policy §4.7 and Data Protection Disclosure §2.3(ad) references.

### Art. 17 path for involuntary data subjects

An individual beta tester's Art. 17 erasure request is fulfilled via the auditable, service_role-only `crm_erase_contact(p_contact_id)` function, which deletes the contact and CASCADEs its notes and stage transitions — a concrete, implementable path keyed on contact identity, distinct from the owner's whole-store `ON DELETE CASCADE` on account deletion. There is **no** statutory-retention obligation on this data, so no Art. 17(3) override is claimed — erasure is a hard delete.

### Conclusion

**Balancing outcome: legitimate interest prevails.** Art. 6(1)(f) is the appropriate lawful basis for the operator (as controller) to process third-party contact and conversation data in the owner-private CRM, given the routine business-relationship-management purpose, the least-intrusive owner-only-RLS + human-gated-write architecture, the bounded low impact, the Art. 14 notice, and the implementable erasure path. The processing does not override the fundamental rights and freedoms of the data subject.

---

## Outstanding counsel-review items

1. **Channel / notice-mechanism confirmation.** The Art. 14 notice is delivered operationally by the operator at first contact rather than by an automated send; counsel to confirm the standard notice wording and that operator-delivered notice satisfies Art. 14(3) timing for this relationship type.
2. **Anthropic Chapter-V transfer scope.** Confirm the existing Anthropic DPA's purpose scope covers surfacing third-party CRM record content for `cro`/`cpo` reasoning (Zero-Retention amendment tracked in `knowledge-base/legal/data-processing-agreements/anthropic.md`).
3. **Controller/processor allocation at multi-tenant GA.** At v1 (single operator) the controller/processor split is clean; counsel to confirm the processor-terms posture when non-Soleur tenants onboard.

---

## Re-evaluation triggers

- Any tester-visible surface / agent-user parity for the third-party subject ships (currently deferred — would change the transparency + access posture).
- Any special-category (Art. 9) field is added, or the free-text `body` is found in practice to routinely carry Art. 9 data.
- Any outbound send authority to the CRM contacts is added (defer to / merge with the outbound-email LIA).
- Retention horizon changes, or the store gains a non-owner (workspace-shared) visibility mode.
- The agent write path is de-gated (auto-approve) — the human-approval gate is a load-bearing safeguard in this balancing.

---

*Draft — requires professional legal review.*
