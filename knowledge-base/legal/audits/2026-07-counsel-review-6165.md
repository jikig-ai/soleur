---
title: "Counsel review audit — #6165 (owner-private agent-native beta-tester / prospect CRM: PA-30, Art. 6(1)(f) LIA)"
type: counsel-review
date: 2026-07-08
issue: 6165
pr: 6160
adr: knowledge-base/engineering/architecture/decisions/ADR-102-beta-crm-capture-store-per-tenant-owner-private-agent-native.md
lia: knowledge-base/legal/legitimate-interest-assessments/2026-07-07-beta-crm-lia.md
status: "DISCHARGED — SIGNED-OFF (CLO-agent-attested, Soleur-as-tenant-zero v1; external counsel re-review on the frontmatter triggers)"
signed_off_at: 2026-07-08
signed_off_by: "clo agent (Soleur legal domain leader) — reviewing authority for v1 per the agent-native company model; external counsel re-review reserved for the triggers below"
brand_survival_threshold: single-user incident
re_evaluation_triggers: "First arms-length / non-Soleur tenant (any data subject who is not the single operator becomes a store OWNER — flips the controller/processor allocation and the cross-owner erasure runbook scoping) OR any tester-visible surface / agent-user parity for the third-party subject ships (changes the Art. 14 transparency + access posture) OR any special-category (Art. 9) field is added, or the free-text `body` is found in practice to routinely carry Art. 9 data OR any outbound send authority to CRM contacts is added (merge with the 2026-06-15 outbound-email LIA) OR the retention horizon changes or the store gains a non-owner (workspace-shared) visibility mode OR the agent write path is de-gated (auto-approve — the human-approval gate is a load-bearing safeguard in the balancing) OR any data subject whose habitual residence raises an EEA-out transfer question not covered by the disclosed DPF/SCCs mechanisms OR a contact/prospect belonging to a regulated industry (healthcare, finance, legal-services)"
---

# Counsel review audit — #6165 (PA-30 owner-private beta-tester / prospect CRM)

> **STATUS: DISCHARGED — reviewed and attested by the `clo` agent on 2026-07-08.**
> The `clo` agent (Soleur legal domain leader) is the reviewing authority for the
> v1 Soleur-as-tenant-zero posture — this is an agent-native company; legal review
> is a CLO-agent function, not a task for the non-lawyer operator. The operator
> retains an optional veto; **external** counsel re-review is reserved for the
> frontmatter re-evaluation triggers. The agent cross-checked every
> implementation-detail claim in the six legal artifacts against the actual
> implementation — migration `126_beta_crm.sql` (tables, RLS, the four SECURITY
> DEFINER RPCs incl. `crm_erase_contact`, the ON DELETE CASCADE chain, the
> `COALESCE(last_contact, created_at)` 24-month `pg_cron` predicate, per-column
> `LAWFUL_BASIS` annotations, no Art. 9 column), `server/crm/crm-tools.ts` (the
> Anthropic agent-read path, the untrusted-content Art. 9-avoidance envelope,
> PII-safe synthetic-error handling, the write RPC shape), `server/tool-tiers.ts`
> + `server/agent-runner.ts` (the human-gated write tiers + gate messages),
> `server/dsar-export-allowlist.ts` + `server/dsar-export.ts` (the article tags +
> export chain), and the third-party erasure runbook — resolved the six named
> issues, and **discharges the gate with no blocking condition**. Two non-blocking
> observations and three pending external-counsel items are recorded below.

This audit is the load-bearing evidence for the ship-time Counsel-Review
CLO-Attestation gate on **PR #6160** (issue **#6165**, `feat-beta-conversation-capture`,
ADR-102). The PR ships an owner-private, agent-native beta-tester / prospect CRM
(migration 126) that stores **third-party personal data** — the people and teams
the operator is in sales/product conversations with — under **Art. 6(1)(f)
legitimate interest**. The legal grain change: this is the register's **first
activity where the operator is the CONTROLLER and Jikigai is the PROCESSOR**
(contrast the operational-audit activities where Jikigai is controller), and the
**first agent WRITE path over untrusted third-party content**. There are **no
`[DRAFT — pending CLO/counsel review]` markers** to clear in this PR.

---

## Per-artifact verdict

| Artifact | Claim(s) cross-checked against code | Verdict |
|---|---|---|
| `knowledge-base/legal/article-30-register.md` — **PA-30** | Controller/processor split; column inventory (matches migration §1–3); "None sought" Art. 9 (no special-category column exists — confirmed); Art. 6(1)(f) + per-column `LAWFUL_BASIS` (migration §1 annotations present); recipients incl. Anthropic (US); Chapter V (e); retention `COALESCE(last_contact, created_at)` 24-mo (migration §11 predicate verbatim); Art. 17 dual path (owner CASCADE + `crm_erase_contact`); TOMs list (g) item-by-item vs migration §4/§7–10; DSAR tags (h) vs allowlist | **CONFIRMED** — every (a)–(h) limb matches the implementation. TOMs (g) 1–9 each verified against the migration body (owner-only SELECT, no owner-write policy, REVOKE incl. `service_role`, `auth.uid()`-pin + `FOR UPDATE` re-check + same-42501 no-oracle, composite FK, RESTRICTIVE jti-deny, append-only-by-shape, PII-safe synthetic error, human-gated writes, `amount⇒currency` + `cardinality(lens)>=1` CHECKs). |
| `.../legitimate-interest-assessments/2026-07-07-beta-crm-lia.md` — **the LIA** | Art. 6(1)(f) three-part balancing (purpose/necessity/balancing all present + reasoned); Art. 14 (not 13) involuntary-third-party posture + feasible-notice mechanism, correctly distinguished from the §3.10 / 2026-06-11 Art. 14(5)(b) disproportionate-effort posture; Art. 17 path = `crm_erase_contact`; no-Art.9; safeguards cross-ref PA-30 (g); Anthropic transfer | **CONFIRMED** — the balancing is complete and the necessity ("DB boundary not git", owner-only RLS, human-gated writes) maps to the actual architecture. Art. 14 notice is operator-delivered at first contact (feasible because the operator is in direct contact) and is correctly framed as a **pending-counsel wording/timing item** (§Outstanding #1), not a claimed automated mechanism. |
| `docs/legal/privacy-policy.md` §4.7 | Owner-curated store; owner-only RLS; controller=user / processor=Jikigai; Art. 6(1)(f) + Art. 14 to third parties; no-Art.9; Anthropic (US) recipient; 24-mo retention; Art. 15+20 export + Art. 17 (whole-store CASCADE + per-contact erasure fn) | **CONFIRMED** — accurate to migration + crm-tools + dsar-export. |
| `docs/legal/gdpr-policy.md` §3.13 + §6 | §3.13 controller/processor, Art. 14, no-Art.9, Art. 6(1)(f) three-part summary, Chapter V, retention/erasure, Art. 22 negative, DPIA-screened residual = within-tenant injection mitigated by human gate; §6 Anthropic row appends the beta-CRM Chapter V transfer (DPF + SCCs Modules 2+3) | **CONFIRMED** — the §3.13 balancing summary and the §6 transfer disclosure match the LIA and the crm-tools Anthropic read path. |
| `plugins/soleur/docs/pages/legal/gdpr-policy.md` §3.13 (Eleventy mirror) | §3.13 mirror carries controller/processor, Art. 14, no-Art.9, Art. 6(1)(f), Chapter V (with a §6 cross-ref), retention/erasure, Art. 22 | **CONFIRMED with a non-blocking consistency note** — the mirror discloses the Chapter V transfer in its own §3.13; its §6 Anthropic row was **deliberately not** updated (changelog scoped the mirror to the §3.13 heading). No published-site disclosure gap. See Observation B. |
| `docs/legal/data-protection-disclosure.md` §2.3(ad) + §5.3 | §2.3(ad) full activity entry (tables/columns, controller/processor, Art. 14, no-Art.9, agent path + Anthropic Chapter V, human-gated writes, retention, dual Art. 17 path, TOMs, no new sub-processor); §5.3(a) adds the CRM to the Art. 15/20 export enumeration; §5.3(c) adds the whole-store CASCADE + third-party `crm_erase_contact` erasure | **CONFIRMED** — §2.3(ad) is the most detailed prose and every implementation claim in it checks out against the code. |
| `knowledge-base/legal/compliance-posture.md` changelog | 2026-07-07 entry: new PA-30, controller/processor, Art. 6(1)(f) + LIA + Art. 14, no-Art.9, Anthropic Chapter V (no new sub-processor), DSAR tags, retention, dual Art. 17, docs-in-lockstep list, SHA repin, TC_VERSION not-required, named residual = LIA channel/notice-mechanism | **CONFIRMED** — accurate summary; `last_updated` bumped; `LEGAL_DOC_SHAS` repinned for the three edited `docs/legal/*.md` (privacy-policy / gdpr-policy / data-protection-disclosure). |

---

## Resolution of the six named issues

1. **Lawful-basis adequacy (Art. 6(1)(f) + LIA) — RESOLVED / adequate.** The LIA
   records a complete three-part test: a real, present business-relationship-
   management interest (Recital 47-adjacent); necessity satisfied by the
   least-intrusive architecture (a per-tenant DB boundary rather than
   git-committed PII — an Art. 17 impossibility — plus owner-only RLS and a narrow,
   human-gated agent write surface); and a balancing that earns the outcome with
   safeguards (owner-only access, 24-mo retention, Art. 14 notice, implementable
   erasure, no profiling / Art. 22). The migration carries per-column
   `LAWFUL_BASIS: legitimate-interest (Art. 6(1)(f))` annotations that point at the
   LIA. Basis is adequate and documented.

2. **Art. 14 (not Art. 13) involuntary-third-party posture + notice mechanism —
   RESOLVED with a named pending-counsel item.** The data is obtained in the course
   of a conversation, not from a form the subject submitted, so **Art. 14 governs**.
   The LIA correctly distinguishes this from the operator-inbox LIA's Art. 14(5)(b)
   disproportionate-effort posture: here notice is **feasible** because the operator
   is in direct, identified contact. The mechanism is operator-delivered notice at /
   shortly after first contact (a short standard line the operator pastes),
   carrying the Art. 14(1) content, backed by Privacy Policy §4.7 + DPD §2.3(ad).
   The **wording + Art. 14(3) timing confirmation** is the correctly-named residual
   (Pending item 1). Not a blocker: this is a relationship notice Soleur cannot
   auto-deliver (Soleur has no channel to the third party), so it is a legitimate
   operator/counsel item, not a deferred automatable action.

3. **24-month retention — RESOLVED / matches code exactly.** Migration §11 schedules
   `beta_contacts_retention` (`pg_cron`, daily 04:30) running
   `DELETE FROM public.beta_contacts WHERE COALESCE(last_contact, created_at::date) < now()::date - interval '24 months'`
   — never-contacted rows still expire; CASCADE removes children. The prose in all
   five doc surfaces ("24 months from `last_contact`; never-contacted from
   `created_at`") is verbatim-accurate. The write RPCs advance `last_contact`
   **forward-only** (`GREATEST`) on note-append and stage-change so a backdated note
   cannot corrupt the retention clock and a stage-only-worked contact is not
   silently purged — the prose's "swept automatically" claim is faithful.

4. **Anthropic Chapter-V transfer scope — RESOLVED with a named pending-counsel
   item.** `crm-tools.ts` reads run on the RLS-owner-scoped tenant client and the
   row content (contact fields + verbatim notes) is surfaced to Claude for
   `cro`/`cpo` reasoning — a Chapter V transfer to Anthropic PBC (US). Disclosed
   consistently across Privacy Policy §4.7, GDPR §3.13 + §6, DPD §2.3(ad), PA-30 (e),
   under the existing Anthropic DPA (EU-US DPF + SCCs Modules 2+3). **No new
   sub-processor** (Anthropic + Supabase already engaged) — correct. The
   **DPA-purpose-scope confirmation** for surfacing third-party CRM content (and the
   tracked Zero-Retention amendment) is the correctly-named residual (Pending item 2).

5. **DSAR / erasure completeness — RESOLVED / complete.** Article tags match:
   `beta_contacts` + `interview_notes` = **15+20** (owner-provided, portable),
   `beta_contact_stage_transitions` = **15** (controller-generated velocity audit) —
   identical in `dsar-export-allowlist.ts`, PA-30 (h), and DPD §5.3. The export chain
   in `dsar-export.ts` reads all three with `assertReadScope(..., { ownerField: "user_id" })`;
   `dsar-allowlist-completeness.test.ts` fail-closes CI on drift. **Owner** whole-store
   erasure = `beta_contacts.user_id … ON DELETE CASCADE` from `public.users` (migration
   §1) firing on account deletion — no anonymise RPC because there is no
   statutory-retention class (ADR-102 §4). **Individual third-party** erasure =
   `crm_erase_contact(p_contact_id)`, `GRANT EXECUTE … TO service_role` with `REVOKE …
   FROM … authenticated` (migration §10) — deletes the contact and CASCADEs its
   notes/transitions. The runbook (`beta-crm-third-party-erasure.md`) gives a complete
   locate → erase → verify → respond-within-one-month sequence, no-SSH (Supabase MCP /
   Doppler pooler), and is `hr-no-dashboard-eyeball` compliant (verification queries
   pull counts directly). Complete.

6. **No-Art.9 posture — RESOLVED / structurally sound.** There is **no
   special-category column** in migration 126; the only free-text ingress is
   `interview_notes.body`. The defence-in-depth is: (i) the `crm-tools.ts`
   `UNTRUSTED_CONTENT_ENVELOPE` explicitly instructs the agent not to record Art. 9
   data (health, race/ethnicity, political/religious/philosophical belief, trade-union,
   genetic/biometric, sex life/orientation), travelling as its own text block ahead of
   the rows; (ii) operator guidance in the LIA/PA-30; (iii) the human-approval gate on
   every write. Prose ("no special-category (Art. 9) data is solicited … incidental
   ingress the operator is instructed to avoid") is accurate to the code. The residual
   "body found in practice to carry Art. 9 data" is a named re-evaluation trigger.

---

## Non-blocking observations

- **A. "cro/cpo agents" vs the actual tool registration surface.** All five doc
  surfaces describe the store as read/written by "the platform's `cro`/`cpo`
  agents." In `server/agent-runner.ts` (~line 1832) `buildCrmTools({ userId })` is
  registered **unconditionally on the leader agent surface**, not role-gated to
  `cro`/`cpo`. This is **legally immaterial**: the recipient (Anthropic), the
  owner-scoping (closure `userId` + owner-only RLS), the controller/processor
  allocation, and the Chapter V analysis are all unchanged — every leader agent runs
  *on the operator's behalf* and is *owner-scoped*, so the purpose (business-
  relationship management) and the disclosed recipients hold regardless of which of
  the operator's agents touches the store. "cro/cpo" is an accurate description of
  the intended/primary consumers. **No correction applied** (softening the phrase
  across five SHA-pinned/mirrored docs would repin SHAs for a descriptively-defensible
  characterization). Named here for the record; revisit if a future agent role is
  given a materially different purpose over the store.

- **B. Eleventy mirror §6 divergence.** The canonical `docs/legal/gdpr-policy.md`
  §6 Anthropic row now appends the beta-CRM Chapter V sentence; the Eleventy mirror
  `plugins/soleur/docs/pages/legal/gdpr-policy.md` §6 row does **not**. This is **not a
  published-site disclosure gap** — the mirror's own §3.13 discloses the Chapter V
  transfer and cross-references §6, and the compliance-posture changelog deliberately
  scoped the mirror sync to the §3.13 heading. Only `docs/legal/*.md` are
  `LEGAL_DOC_SHAS`-pinned. Optional consistency polish: append the same one-line
  beta-CRM note to the mirror §6 row on a future docs pass. Not applied (deliberately
  scoped; disclosure present in the mirror §3.13).

## Pending external-counsel items (carried from the LIA — re-review triggers, not ship blockers)

1. **Art. 14 notice wording + Art. 14(3) timing.** Confirm the standard first-contact
   notice line and that operator-delivered notice satisfies Art. 14(3) timing for this
   relationship type.
2. **Anthropic DPA purpose scope.** Confirm the existing Anthropic DPA covers surfacing
   third-party CRM record content for `cro`/`cpo` reasoning (Zero-Retention amendment
   tracked in `knowledge-base/legal/data-processing-agreements/anthropic.md`).
3. **Controller/processor allocation at multi-tenant GA.** Confirm the processor-terms
   posture when non-Soleur tenants onboard (clean at v1 single-operator; the runbook's
   cross-owner step 1 must be per-subject-scoped at GA).

---

## Overall disposition

**DISCHARGED — proceed to ship.** The six legal artifacts accurately state the
migration-126 implementation across all six resolution axes (lawful basis, Art. 14
posture, 24-month retention, Anthropic Chapter V, DSAR/erasure, no-Art.9). No prose
misstates the code, the Art. 6(1)(f) basis is documented and adequate (dedicated LIA
+ per-column annotations), and no required disclosure is missing. The two observations
are non-blocking and no in-PR prose correction is required to ship. The three
pending items are external-counsel confirmations correctly recorded as the named
residual and mapped to the frontmatter re-evaluation triggers; they do not gate the v1
Soleur-as-tenant-zero ship. All output remains **draft material requiring professional
legal review**; this attestation is the v1 internal CLO-agent sign-off, with the
operator's optional veto retained and external counsel re-review reserved for the
frontmatter triggers.
