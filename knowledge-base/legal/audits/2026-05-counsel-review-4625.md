---
status: SIGNED-OFF (CLO-agent-attested, Soleur-as-tenant-zero v1)
date: 2026-05-29
issue: 4625
pr: 4627
adr: ADR-045
brand_survival_threshold: single-user incident
gate: AC10 (counsel-review attestation) — decides whether AC11 (flag flip dark→live) may proceed
attesting_authority: clo (CLO agent, Soleur-as-tenant-zero v1 internal sign-off; operator retains veto)
re_evaluation_triggers:
  - first arms-length (non-jikigai) user accepts a delegation under FLAG_BYOK_DELEGATIONS
  - any EEA-out processing path
  - regulated-industry tenant onboards to the delegation feature
  - any bump of BYOK_SIDE_LETTER_VERSION / current_byok_side_letter_version()
scope_reviewed:
  - knowledge-base/legal/delegation-consent-side-letter-template.md (v2.0.0)
  - apps/web-platform/supabase/migrations/074_byok_delegation_acceptances.sql
  - apps/web-platform/supabase/migrations/083_byok_delegation_consent_gate.sql
  - apps/web-platform/supabase/migrations/084_byok_delegation_withdrawals.sql
  - apps/web-platform/server/byok-side-letter.ts
  - apps/web-platform/app/api/workspace/delegations/accept/route.ts
  - docs/legal/data-protection-disclosure.md §2.3(w)
  - docs/legal/gdpr-policy.md §5.3
  - docs/legal/privacy-policy.md §4.11 / §5
  - knowledge-base/engineering/architecture/decisions/ADR-045-byok-delegation-consent-gate-and-in-flight-billing-boundary.md
---

# Counsel-Review Audit — #4625 BYOK Delegation Consent Enforcement (AC10 gate)

> **DRAFT counsel work product — CLO-agent attestation for the Soleur-as-tenant-zero v1
> posture. This is the internal v1 sign-off authority; the operator retains a veto.
> External counsel re-review is reserved for the re-evaluation triggers in the
> frontmatter (first arms-length user, EEA-out, regulated industry, version bump).**

## Question presented

Do the rewritten in-app consent text (template v2.0.0) and its enforcement
implementation (migrations 074/083/084 + the accept route + the server-owned
version constant) satisfy GDPR Art. 26 (joint controllership), Art. 6 (lawful
basis), and Art. 7 (consent + withdrawal) well enough to flip
`FLAG_BYOK_DELEGATIONS` from dark to live?

## Overall disposition: **BLOCKED**

One real, concrete legal defect remains: the **data-subject-facing Data
Protection Disclosure §2.3(w) body still states the pre-correction, conflated
lawful basis** (Art. 6(1)(b) as THE basis, consent demoted to "evidence"). This
is the exact conflation that #4625's own migration-074 header documents as the
defect being fixed. The corrected dual-basis position now lives in the migration
header, the side-letter template §2, and ADR-045 — but NOT in the canonical
transparency disclosure that data subjects actually read. That is a misstatement
of the implementation in the load-bearing Art. 13(1)(c)/Art. 26(2) document, and
it directly undercuts the Art. 7 demonstrability story (you cannot rely on consent
as the lawful basis while your public disclosure says the basis is contract).
Per the v1 attestation standard (BLOCK on a legal defect that misstates the
implementation or leaves a weak/incoherent lawful basis), the flag may not flip
until §2.3(w) is corrected.

The other three pillars (Art. 26 allocation, Art. 7 mechanics, paper-signature
retirement) are satisfied. The blocker is narrow and surgically fixable.

---

## Per-artifact verdicts

### 1. `delegation-consent-side-letter-template.md` (v2.0.0) — PASS

- **Art. 26 (§3):** Responsibility allocation is explicit AND bilateral —
  DSARs/data-subject rights, Art. 32 security, Arts. 13–14 transparency, and the
  Art. 26(1) single contact point are each allocated to Grantor with reciprocal
  Grantee duties; §3.4 preserves the Art. 26(3) right to proceed against either
  controller. §3.1 correctly states the bilateral allocation — not a unilateral
  click — IS the arrangement.
- **Same-version binding:** "How this document is used" + §5.3 bind BOTH parties
  to one server-pinned `side_letter_version`. The document correctly distinguishes
  the editorial `template_version` (2.0.0) from the system pin (`1.0.0`) and
  describes fail-closed re-consent on a bump. Matches the implementation.
- **Art. 6 (§2):** Dual basis stated correctly and WITHOUT conflation —
  6(1)(a) consent for the Grantee's prompt content + cost-telemetry visibility;
  6(1)(b) only for the `byok_delegations` funding records; §2.3 states they are
  not interchangeable. This is the correct position.
- **Art. 7 (§5, §6):** Acceptance row = Art. 7(1) demonstrability; withdrawal =
  single in-app action (§6.1), recorded in `byok_delegation_withdrawals` (§6.2),
  with the one-turn in-flight billing boundary accurately described.
- **Paper-signature retirement:** Cleanly retired and replaced by recorded in-app
  consent.

### 2. `074_byok_delegation_acceptances.sql` — PASS

- LAWFUL_BASIS header corrected for #4625: explicitly names the prior conflation
  ("Art. 6(1)(b) contract — grantee consents") as the defect and states the
  corrected split — this table evidences the Grantee's **Art. 6(1)(a)** consent
  (Art. 7(1) demonstrability), distinct from the mig-064 funding-contract basis.
- WORM table + append-only triggers + Art. 17 anonymise RPC + ON DELETE RESTRICT
  ordering are coherent and match the template's evidence/retention claims.

### 3. `083_byok_delegation_consent_gate.sql` — PASS

- `current_byok_side_letter_version()` is the single SQL source of truth
  (IMMUTABLE function-literal `'1.0.0'`), kept in lockstep with the TS constant
  `BYOK_SIDE_LETTER_VERSION` by the AC4 CI parity gate
  (`test/byok-side-letter-version-parity.test.ts`). Verified: TS constant = `"1.0.0"`,
  SQL literal = `'1.0.0'` — parity holds.
- The resolver gains `AND EXISTS(current-version acceptance)`; own-key
  short-circuit preserved (solo users unaffected). A version bump fail-closes
  stale acceptances. This is the load-bearing fix that makes recorded consent the
  source of truth gating the key lease — closes the "processing before consent"
  Art. 26 exposure ADR-045 §Context describes.

### 4. `084_byok_delegation_withdrawals.sql` — PASS

- **Art. 7(3) "as easy to withdraw as to give":** `withdraw_byok_delegation_consent`
  is a grantee-only RPC (derives `auth.uid()`, no `p_user_id` harvest vector),
  GRANT to `authenticated` — symmetric with the accept path. Single in-app action.
- **Blocks new leases:** resolver Gate 2 — `NOT EXISTS(withdrawal newer than the
  latest current-version acceptance)`, version-agnostic via
  `COALESCE(max(accepted_at), withdrawn_at)` + `>=` (correctly fails CLOSED after a
  version bump; equal-timestamp ties block). Sound.
- **Stops in-flight billing within one turn:** the per-turn re-gate in
  `check_and_record_byok_delegation_use` (row already `FOR UPDATE`) raises
  `consent_withdrawn` and DEBITS THE GRANTEE (`founder_id = p_caller_user_id`) —
  symmetric with `revoked_post_grace`/`expired`. The one-turn boundary matches
  ADR-045 §Decision 2 and the template §6. The `audit_byok_use` CHECK enum is
  extended with `consent_withdrawn`.
- WORM + NULLABLE `user_id` + no-UNIQUE design correctly support the non-terminal
  re-accept flow AND the Art. 17 anonymise-to-NULL path (AC14).

### 5. `byok-side-letter.ts` + accept route — PASS

- Version is server-owned and server-stamped; the accept route ignores any
  client-supplied version (closes the stale-version fail-OPEN). Grantee-identity
  checked; `ip_hash` is SHA-256 of the first XFF hop; UA truncated to 512.

### 6. `docs/legal/gdpr-policy.md` §5.3 — PASS (header)

- The #4625 `Last Updated` entry accurately discloses the withdrawal ledger,
  Art. 15+20 DSAR coverage, the Art. 17 cascade step 5.12, the consent gate as
  source of truth, and the one-turn in-flight billing stop. Accurate against code.

### 7. `docs/legal/privacy-policy.md` — PASS (header)

- The #4625 `Last Updated` entry accurately discloses the withdrawal ledger, DSAR
  coverage, the Art. 17 cascade, the gate, and the one-turn billing stop.

### 8. `docs/legal/data-protection-disclosure.md` §2.3(w) — **FAIL (the blocker)**

- The #4625 commit changed only the `Last Updated` header (2-line diff). The
  **§2.3(w) body** — the canonical Art. 13(1)(c)/Art. 26(2) processing-activity
  disclosure for "Delegated-credential prompt routing" — was NOT updated and still
  reads:

  > "**Legal basis:** contract performance (Article 6(1)(b) GDPR) — the delegation
  > IS the bilateral contract between Grantor and Grantee. Grantee consent is
  > captured via the Delegation Consent Side Letter acceptance stored in
  > `byok_delegation_acceptances` (Article 7 evidence...)."

- This states a SINGLE lawful basis (6(1)(b)) for the named processing activity
  (routing the Grantee's prompt content) and demotes the Grantee's consent to
  procedural "evidence." That is precisely the conflation the migration-074 header
  identifies as the bug being fixed. Post-correction, the lawful basis for routing
  the Grantee's prompt content under the Grantor's key is **Art. 6(1)(a) consent**;
  Art. 6(1)(b) covers ONLY the `byok_delegations` funding records.
- The §2.3(w) body also omits the new withdrawal path (Art. 7(3)) and the
  `byok_delegation_withdrawals` ledger from the activity description — present only
  in the header.
- **Why this blocks the flip:** §2.3(w) is the document a data subject reads to
  learn the lawful basis for this processing. Going live with a disclosure that
  names contract-necessity as the basis for consent-gated prompt-content processing
  (a) misstates the implementation, (b) contradicts the template/074/ADR-045
  corrected position, and (c) undermines Art. 7 — you cannot demonstrate consent as
  your basis while publicly disclosing the basis as contract. This is the
  legal-prose-vs-code drift class (cf. PR #4353/#4558) the CLO mandate requires
  blocking on.

---

## Required fix before AC11 may proceed

Amend `docs/legal/data-protection-disclosure.md` §2.3(w) **body** so the lawful
basis matches the corrected dual-basis position already in mig-074, the template
§2, and ADR-045. Specifically:

1. Replace the single-basis sentence with the dual split:
   - **Art. 6(1)(a) consent** = lawful basis for processing the Grantee's prompt
     content under the Grantor's key AND for the Grantor's itemised cost-telemetry
     visibility (recorded in-app per `byok_delegation_acceptances`, Art. 7(1)
     demonstrability).
   - **Art. 6(1)(b) contract** = lawful basis ONLY for the `byok_delegations`
     funding-relationship records; it does NOT substitute for the Grantee's
     consent. State they are not interchangeable.
2. Add the Art. 7(3) withdrawal path to the activity body: the
   `byok_delegation_withdrawals` WORM ledger (mig 084), the grantee-only
   `withdraw_byok_delegation_consent` RPC, that withdrawal blocks new leases and
   stops in-flight billing within one turn, and the Art. 17 cascade step 5.12
   (`anonymise_byok_delegation_withdrawals`).
3. Note that the recorded in-app acceptance replaces the retired paper-signature
   precondition (template 1.x → 2.0.0).

**Lockstep (the #4625 commit already exercised this machinery — replicate it):**
- Re-pin `apps/web-platform/lib/legal/legal-doc-shas.ts` for the DPD hash.
- Update the Eleventy mirror `plugins/soleur/docs/pages/legal/data-protection-disclosure.md`
  §2.3(w) body in lockstep (source↔mirror date + content), per the
  legal-doc-cross-document-gate.
- Re-run the cross-document gate.

This is the **legal-document-generator** task (regenerate/fix §2.3(w) body), then a
**legal-compliance-auditor** re-check of cross-document consistency, then re-attest
this gate. The fix is one processing-activity paragraph plus the two lockstep pins;
all other artifacts are sign-off-ready.

## What is NOT blocking (explicitly cleared)

- Art. 26 allocation (template §3) — bilateral, explicit, Art. 26(3) preserved.
- Same-version binding of both parties — enforced server-side; parity CI-gated.
- Art. 7(1) demonstrability + Art. 7(3) withdrawal mechanics — sound, including the
  one-turn in-flight billing boundary and the version-agnostic fail-closed predicate.
- Paper-signature retirement — coherent.
- GDPR §5.3 and Privacy Policy #4625 headers — accurate against the code.

Once §2.3(w) is corrected and the lockstep re-pinned, this audit flips to
`SIGNED-OFF (CLO-agent-attested, Soleur-as-tenant-zero v1)` and AC11 may proceed.

---

## Re-attestation — 2026-05-29 (blocker DISCHARGED)

The single named blocker (§8, "FAIL") is resolved. Verified in worktree
`/home/jean/git-repositories/jikig-ai/soleur/.worktrees/byok-postmerge-ac10-11/`:

1. **§2.3(w) body lawful basis — CORRECTED.** The body of
   `docs/legal/data-protection-disclosure.md` §2.3(w) ("Delegated-credential
   prompt routing") now states the dual, non-interchangeable split:
   **"Legal basis (dual, non-interchangeable)"** — Grantee's **Art. 6(1)(a)
   consent** is the basis for processing the Grantee's prompt content under the
   Grantor's key AND for the Grantor's cost-telemetry visibility (acceptance row
   = Art. 7(1) demonstrability); **Art. 6(1)(b) contract** covers **ONLY the
   funding records** in `byok_delegations` and explicitly "is NOT the basis for,
   and does not substitute for, the consent that authorises prompt-content
   processing." The pre-correction conflated sentence ("the delegation IS the
   bilateral contract… Grantee consent is captured… Article 7 evidence") is
   **gone** (0 matches in the file). Consent is also disclosed as *enforced, not
   merely evidenced* (mig 083 resolver `EXISTS` gate +
   `current_byok_side_letter_version()` fail-closed).

2. **Art. 7(3) withdrawal path — DISCLOSED in the body.** §2.3(w) now describes
   the grantee-only `withdraw_byok_delegation_consent` RPC, the
   `byok_delegation_withdrawals` WORM ledger (mig 084), that withdrawal "blocks
   new key leases at the resolver AND stops any in-flight run's billing within
   one turn" (remaining cost debited to the Grantee), non-terminal re-accept, and
   the Art. 17 cascade **step 5.12** (`anonymise_byok_delegation_withdrawals`).
   The retired paper-signature precondition is reflected via the recorded in-app
   acceptance model.

3. **Lockstep — RE-PINNED + GATES GREEN.**
   `apps/web-platform/lib/legal/legal-doc-shas.ts` "data-protection-disclosure"
   entry = `af5e09d6a75e5398d658d6e73a2ec82ae462cc4cb6d0089dedb79fd5ea367c93`,
   which matches the live `sha256sum` of the corrected file (recomputed —
   exact match). `npx vitest run test/legal-doc-shas-guard.test.ts
   test/legal-doc-consistency.test.ts` → **19/19 passed**.

4. **Eleventy mirror omission — ACCEPTED, not a blocker.** The mirror
   `plugins/soleur/docs/pages/legal/data-protection-disclosure.md` has **no
   §2.3(w) body item at all** (body items stop at `(v)`; the `(w)` text appears
   only in the mirror's Last-Updated changelog header). This is the pre-existing
   abbreviated drift predating the delegation disclosure — there was never any
   conflated `(w)` prose in the mirror to fix, so the original blocker's "mirror
   in lockstep" instruction is satisfied vacuously for the conflation defect. The
   canonical `docs/legal/` file is the document of record (Art. 13/26 disclosure
   data subjects read); body-equivalence for non-T&C docs is opt-in/deferred and
   the consistency gate enforces only source↔mirror **date** parity, which holds
   (both May 29, 2026). Not a blocker.

5. **Cross-document lockstep gate scope — CONFIRMED.** The DSAR/cross-document
   lockstep machinery keys on `dsar-export.ts`-class surfaces, which this
   pure DPD-body edit does not touch; it therefore does not fire for this change.
   The applicable gates that DO cover this edit (`legal-doc-shas-guard`,
   `legal-doc-consistency`) both pass.

**Disposition: DISCHARGED.** All four non-blocking pillars remain satisfied
(Art. 26 allocation, same-version binding, Art. 7(1)/(3) mechanics, paper-sig
retirement); the §8 blocker is closed; lawful-basis prose is now coherent with
mig-074/083/084, the side-letter template §2, and ADR-045, and verified against
the actual migration/RPC bodies. AC11 (`FLAG_BYOK_DELEGATIONS` dark→live) may
proceed. External counsel re-review remains reserved for the frontmatter
re-evaluation triggers.
