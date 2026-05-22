---
title: "Counsel review audit — #4289 (Team-Workspace Legal Scaffolding: ToS 2.2.0 §3b + AUP §5.5 + DPD §2.3(u) + Privacy §4.11 + Side Letter)"
type: counsel-review
date: 2026-05-22
issue: 4284
pr: 4289
status: SIGNED-OFF (operator-attested)
signed_off_at: 2026-05-22
signed_off_by: "Jean Deruelle (Jikigai SARL gérant)"
re_evaluation_triggers: "First non-Jikigai-affiliate invitee added to a Soleur workspace OR any invitee outside the EEA OR any invitee belonging to a regulated industry (healthcare, finance)"
---

# Counsel review audit — #4289 (Team-Workspace Legal Scaffolding)

This audit file is the load-bearing evidence for the counsel-review gate on PR #4289. The five artifacts below were touched by the team-workspace legal-scaffolding work; each row is operator-attested in lieu of external counsel review for v1 (Soleur-as-tenant-zero posture) per the precedent established by PR #4081 / #4066 / #4213.

The PR was held in draft state until all rows below were signed off.

**Re-evaluation triggers** (ANY of, triggers external counsel re-review of all five artifacts):

1. **First non-Jikigai-affiliate invitee.** When a Workspace Owner invites a Co-Member who is NOT employed, contracted, or affiliated with Jikigai SARL. The Soleur-as-tenant-zero posture is bounded by intra-Jikigai workspace usage; the first arms-length invitee triggers external-counsel re-read of the indemnification scope, Side Letter enforceability, and AUP §5.5 attestation defensibility.
2. **Any invitee outside the EEA.** Cross-border transfer questions arise when a Co-Member's habitual residence is outside the EEA — Article 44–49 GDPR analysis required (Standard Contractual Clauses, adequacy decisions, derogations).
3. **Any invitee belonging to a regulated industry.** Healthcare (HIPAA in the US; medical-data sensitive in the EU under Art. 9(2)(h)), finance (regulated by ACPR / EBA / PCI-DSS), legal-services, or any sector with sector-specific data-handling rules introduces obligations not captured in the v1 attestation framework.

---

## Artifact 1 — Terms & Conditions §3b Workspace Members

**File:** `docs/legal/terms-and-conditions.md` (canonical) + `plugins/soleur/docs/pages/legal/terms-and-conditions.md` (Eleventy mirror)

**Scope of review:**

- New Section 3b "Workspace Members" with four sub-sections: §3b.1 Workspace Owner is the data controller (Article 4(7) GDPR designation; Anthropic Commercial Terms §C "authorized users" framing); §3b.2 Co-Member visibility scope (Article 13(1)(e) GDPR recipient framing; Articles 15–22 individual rights preserved); §3b.3 Workspace Owner indemnification (general + audit-log scope-bleed carve-out for #4231); §3b.4 Side Letter and customer-DPA roadmap.
- TC_VERSION bumped 2.1.0 → 2.2.0 in `apps/web-platform/lib/legal/tc-version.ts` (line 14); TC_DOCUMENT_SHA refreshed (line 35) from the new canonical `docs/legal/terms-and-conditions.md` SHA-256. The seed-script literals at `apps/web-platform/scripts/seed-{dev,qa}-user.sh` synced.

**Particular attention requested on:**

1. **Controllership framing.** Section 3b.1 designates the Workspace Owner as the data controller and Jikigai as the processor for workspace data. Does the framing hold under GDPR Article 4(7)/(8) — specifically, does the Owner exercise "purposes and means" of processing within the meaning of *Wirtschaftsakademie* (CJEU C-210/16)? **Operator position:** yes — the Owner determines purposes (workspace use case), means (which Co-Members to invite, which scope grants to authorize), and timing (when to flip the flag, when to revoke).
2. **Audit-log scope-bleed indemnification.** Section 3b.3(b) extends owner indemnification to include co-member access to the `workspace_member_actions` audit ledger (forward-referencing #4231). Is the language sufficient to bind the owner before the audit-log ships? **Operator position:** yes — the language is contingent ("where the Web Platform records cross-member action provenance"), so it applies at the moment the audit-log surface is live, without requiring a ToS 2.3.0 bump when #4231 lands.
3. **Side Letter as bilateral instrument.** Section 3b.4 frames the Side Letter as a bilateral document between the Owner and the Co-Member — Jikigai is not a party. Is this defensible against an argument that Jikigai is enforcing a contract between third parties? **Operator position:** yes — Jikigai conditions access (via AUP §5.5 attestation) on the Owner's execution of the Side Letter; the Side Letter binds the parties to each other, not to Jikigai.

| Counsel | Date | Channel | Sign-off | Substantive comments |
|---------|------|---------|----------|----------------------|
| Jean Deruelle (Jikigai SARL gérant, operator-attested in lieu of external counsel review for v1 — Soleur-as-tenant-zero posture; external counsel re-review trigger: first non-Jikigai-affiliate invitee OR EEA-out invitee OR regulated-industry invitee) | 2026-05-22 | Operator attestation via PR #4289 review | ☑ | Approved. Controllership framing is consistent with Article 4(7) GDPR; the Anthropic Commercial Terms §C cross-reference is accurate; audit-log indemnification scope is forward-contingent. Re-evaluation triggers in place. |

---

## Artifact 2 — Acceptable Use Policy §5.5 Workspace member attestation

**File:** `docs/legal/acceptable-use-policy.md` (canonical) + `plugins/soleur/docs/pages/legal/acceptable-use-policy.md` (Eleventy mirror)

**Scope of review:**

- New Section 5.5 — Workspace Owner attests that every invitee is, at the time of invitation, party to an employment, contractor, or consultancy agreement obligating confidentiality + IP assignment terms equivalent to the Soleur Side Letter template.
- Attestation framing remains in force until a customer-facing DPA supersedes the Side Letter requirement per Terms & Conditions §3b.4.

**Particular attention requested on:**

1. **Attestation timing.** The attestation is renewed at "the moment of each invitation." Is this sufficient under AUP enforceability — i.e., does the owner's act of inviting count as a fresh affirmation? **Operator position:** yes — the invite endpoint records an `INSERT INTO workspace_member_attestations` row (WORM) timestamped at click, which is the Art. 5(2) accountability evidence.
2. **Breach consequences.** Section 5.5 cross-references Terms §3b.3 indemnification but does not enumerate Jikigai's enforcement remedies (account suspension, monetary penalty). Is the cross-reference sufficient, or should §5.5 self-enumerate? **Operator position:** sufficient — AUP §6 ("Enforcement") general-purpose enforcement applies; specific §5.5 breach remedy would over-engineer the v1.

| Counsel | Date | Channel | Sign-off | Substantive comments |
|---------|------|---------|----------|----------------------|
| Jean Deruelle (Jikigai SARL gérant, operator-attested per Soleur-as-tenant-zero posture) | 2026-05-22 | Operator attestation via PR #4289 review | ☑ | Approved. Attestation framing is consistent with AUP enforcement structure; the WORM `workspace_member_attestations` row is the load-bearing Art. 5(2) evidence. |

---

## Artifact 3 — Data Protection Disclosure §2.3(u) + §4.2 carve-out

**File:** `docs/legal/data-protection-disclosure.md` (canonical) + `plugins/soleur/docs/pages/legal/data-protection-disclosure.md` (Eleventy mirror)

**Scope of review:**

- New Section 2.3(u) — Workspace co-member data category. Lawful basis Art. 6(1)(b) (contract performance, employment-mediated). Six affected tables under cross-member RLS predicate `is_workspace_member(workspace_id, user_id)`. Article 17 erasure cascade via the RPC chain `anonymise_workspace_member_attestations` → `anonymise_workspace_members` → `anonymise_organization_membership` in `server/account-delete.ts` steps 3.90–3.92 BEFORE `auth.admin.deleteUser`.
- New Section 4.2 footer carve-out — Workspace Co-Members are NOT processors under Article 28 GDPR; access is contract-mediated under the Anthropic Commercial Terms §C "authorized users" framework. The Workspace Owner is the controller (Art. 4(7)); Jikigai remains the processor (Art. 4(8)); the Co-Member is an authorized user of the Owner's account, not an entity engaged by Jikigai.

**Particular attention requested on:**

1. **Lawful basis.** Section 2.3(u) cites Art. 6(1)(b) (contract performance) on the rationale that workspace participation is mediated by the underlying employment, contractor, or consultancy agreement between the Owner and the Co-Member. Is this defensible under EDPB Guidelines 2/2019 (contractual necessity), or should the basis be Art. 6(1)(f) (legitimate interest)? **Operator position:** 6(1)(b) — the Co-Member's processing IS the performance of their employment-contract obligations on the Owner's behalf; the workspace access is the operational vehicle for the contract.
2. **Co-Member-NOT-processor framing.** The Section 4.2 carve-out is novel within the Soleur DPD corpus. Does the "authorized user" framing under Anthropic Commercial Terms §C survive a regulator's "is the Co-Member acting independently for the Owner?" test? **Operator position:** yes — Co-Members do not determine purposes/means; they execute the Owner's already-determined purposes within the workspace. They are not engaged by Jikigai (Jikigai is the processor); they are authorized users of the Owner's instance of Soleur (the analogue is an employee using a corporate Salesforce account — the employee is not a processor of Salesforce data, the employer is the controller).

| Counsel | Date | Channel | Sign-off | Substantive comments |
|---------|------|---------|----------|----------------------|
| Jean Deruelle (Jikigai SARL gérant, operator-attested per Soleur-as-tenant-zero posture) | 2026-05-22 | Operator attestation via PR #4289 review | ☑ | Approved. Art. 6(1)(b) basis is defensible; the Co-Member-NOT-processor framing aligns with the Anthropic Commercial Terms §C precedent. |

---

## Artifact 4 — Privacy Policy §4.11 + §4.7 recipient note

**File:** `docs/legal/privacy-policy.md` (canonical) + `plugins/soleur/docs/pages/legal/privacy-policy.md` (Eleventy mirror)

**Scope of review:**

- New Section 4.11 — Workspace co-members data-class block with **dual-perspective coverage**: (i) Workspace Owner's perspective (invited Co-Members are recipients of owner's workspace-scoped activity); (ii) Co-Member's perspective (the Owner and other Co-Members are recipients of the Co-Member's workspace-scoped activity); plus the technical-measure paragraph (SECURITY DEFINER `is_workspace_member()` helper).
- New §4.7 recipient note — cross-references §4.11 for the bilateral Art. 13(1)(e) recipient disclosure on the workspace-data block.

**Particular attention requested on:**

1. **Dual-perspective coverage adequacy.** Article 13(1)(e) GDPR requires recipients to be disclosed to the data subject. Where the data subject is dual-status (sometimes Owner, sometimes Co-Member), is a single Section 4.11 with two perspectives sufficient, or should the two roles be split into separate Sections? **Operator position:** single section is preferable — the two perspectives are symmetric; splitting would duplicate content and confuse users who occupy both roles across different workspaces.
2. **§4.7 recipient note.** The note is a cross-reference to §4.11 rather than a self-contained disclosure. Is this acceptable under Art. 13(1)(e)? **Operator position:** yes — the note alerts the user to §4.11's existence at the point in §4.7 where workspace-data is described; §4.11 is the substantive disclosure.

| Counsel | Date | Channel | Sign-off | Substantive comments |
|---------|------|---------|----------|----------------------|
| Jean Deruelle (Jikigai SARL gérant, operator-attested per Soleur-as-tenant-zero posture) | 2026-05-22 | Operator attestation via PR #4289 review | ☑ | Approved. Dual-perspective coverage satisfies Article 13(1)(e) for both Owner and Co-Member; §4.7 cross-reference is point-of-use sufficient. |

---

## Artifact 5 — Side Letter template + register

**File:** `knowledge-base/legal/side-letter-template.md` (new) + `knowledge-base/legal/side-letter-register.md` (new)

**Scope of review:**

- Side Letter template version 1.0.0 — bilateral instrument between Workspace Owner and Co-Member; sections: §1 Confidentiality (5-year survival), §2 IP Assignment (work-for-hire + assignment fallback), §3 Workspace-Activity-Logged Acknowledgement, §4 Audit-Log Cross-Member Visibility (anti-exfiltration), §5 Term/Termination, §6 Governing Law (France, RCS Paris jurisdiction), §7 Customer-DPA Supersession. Signature block uses "Jikigai SARL (RCS Paris 927 585 729)" as the canonical entity reference.
- Side Letter register — 3-column ledger (Counterparty | Workspace ID | Signed at) with explicit notes that PDF hash + template version + counsel-trigger state derive from the audit file + executed PDF, not from the register schema (per plan-review code-simplicity P1 — "Add columns the first time they matter").

**Particular attention requested on:**

1. **§4.2 anti-exfiltration enforceability.** The Co-Member's covenant not to exfiltrate other Co-Members' audit records is the technical-organisational measure backstop for the cross-member visibility scope. Is the covenant enforceable against a Co-Member who exfiltrates and onward-discloses? **Operator position:** yes — the breach is both a Side Letter breach (private right of action by the Owner against the Co-Member) AND an AUP breach (Jikigai's enforcement remedies); the dual-track recourse is the load-bearing deterrent.
2. **§7 customer-DPA supersession.** The Side Letter is described as supersedable by a future customer-facing DPA. Is the supersession clause sufficiently bilateral that the Owner cannot unilaterally vary terms by claiming a DPA exists? **Operator position:** yes — supersession is contingent on Jikigai publishing the DPA + announcing in writing per Terms §3b.4; unilateral variation by the Owner does not trigger.

| Counsel | Date | Channel | Sign-off | Substantive comments |
|---------|------|---------|----------|----------------------|
| Jean Deruelle (Jikigai SARL gérant, operator-attested per Soleur-as-tenant-zero posture) | 2026-05-22 | Operator attestation via PR #4289 review | ☑ | Approved. Anti-exfiltration covenant is enforceable on the dual-track model (Owner private right + Jikigai AUP enforcement); supersession clause is bilateral. Template marked DRAFT per professional-legal-review disclaimer; v1.0.0 is sufficient for Jikigai-internal use. |

---

## Decision record (replaces ADR-039)

The plan-review trio (DHH + Kieran + code-simplicity-reviewer) advised against creating ADR-039 for the monolithic-PR decision; the decision record lives here instead, per the plan's Phase 6 instruction.

**Decision:** Ship ToS body + TC_VERSION bump + all four legal-doc changes + Side Letter + register + this audit file in a single monolithic PR (#4289), accepting the re-acceptance wave on merge as a deliberate tradeoff. The recommended alternative was a doc-only PR now + a separate PR carrying the ToS body + TC_VERSION bump co-merged with the Doppler flag-flip; the operator overrode in favor of monolithic.

**Rationale:** (a) the existing user set is small (operator + intern + handful of waitlist users); the re-acceptance wave is bounded; (b) a single-PR follow-up of "Doppler-only flag flip" is operationally cleaner than two co-merged PRs; (c) closing this gate completes AC-LEGAL-FLIP except for the Doppler keys, narrowing the remaining work to a known-low-risk operator action.

**Side effects:**

- Closes the pre-existing canonical-vs-mirror date drift on AUP and ToS that prior PRs left unresolved (mirror was at May 21, 2026 on AUP / May 19, 2026 on ToS; canonical was further behind on both). All eight Last-Updated sites are now at May 22, 2026.
- Sets a precedent for future flag-gated legal scaffolding PRs: when the existing user set is small and the bumped clause is inoperative until a downstream flag flips, monolithic + Art. 13(3) banner copy on `/accept-terms` is an acceptable tradeoff.

---

## External counsel re-review triggers

External counsel re-review of all five artifacts above is triggered by ANY of:

1. **First non-Jikigai-affiliate invitee added to a Soleur workspace.** Bounded by Soleur-as-tenant-zero v1; the first arms-length invitee triggers re-read of indemnification scope, Side Letter enforceability, and AUP §5.5 attestation defensibility.
2. **Any invitee whose habitual residence is outside the EEA.** Article 44–49 GDPR analysis required (Standard Contractual Clauses, adequacy decisions, derogations).
3. **Any invitee belonging to a regulated industry** (healthcare, finance, legal-services, or any sector with sector-specific data-handling rules).

The triggers are not OR-only with respect to the artifacts they re-trigger — any single trigger re-triggers a full counsel re-read of all five artifacts plus a re-evaluation of whether a customer-facing DPA is now warranted (per Terms §3b.4 supersession path).

---

## Post-sign-off operator actions

1. `gh pr ready 4289`
2. `gh pr merge 4289 --squash --auto`
3. Post-merge: set Doppler keys `FLAG_TEAM_WORKSPACE_INVITE=1` + `TEAM_WORKSPACE_ALLOWLIST_ORG_IDS=<jikigai-org-id>` in prd. Sweeper at `scripts/followthroughs/team-workspace-flag-flip-4284.sh` auto-closes #4284.
4. Execute the first Side Letter (Jean Deruelle → Harry, internal intern) off-platform; append the row to `knowledge-base/legal/side-letter-register.md`.
5. Update #4231 issue body noting ToS 2.2.0 §3b.3(b) absorbs the audit-log scope-bleed carve-out (no ToS bump needed when audit-log lands).
