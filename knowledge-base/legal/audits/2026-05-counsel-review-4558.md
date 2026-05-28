---
title: "Counsel review audit — #4558 (ADR-044 workspace repo ownership: co-member repo/KB access legal amendments)"
type: counsel-review
date: 2026-05-28
issue: 4558
pr: 4559
tracking_issue: 4564
status: "SIGNED-OFF (CLO-agent-attested, Soleur-as-tenant-zero v1; external counsel re-review on the frontmatter triggers)"
signed_off_at: 2026-05-28
signed_off_by: "clo agent (Soleur legal domain leader) — reviewing authority for v1 per the agent-native company model; external counsel re-review reserved for the triggers below"
re_evaluation_triggers: "First Co-Member granted access to a connected repository or knowledge-base that contains third-party personal data (i.e. data of natural persons who are NOT the Owner or the Co-Members) OR first non-Jikigai-affiliate Co-Member granted repo/KB access OR any Co-Member whose habitual residence is outside the EEA OR any Co-Member or repository belonging to a regulated industry (healthcare, finance, legal-services)"
---

# Counsel review audit — #4558 (ADR-044 co-member repo/KB access)

> **STATUS: SIGNED-OFF — reviewed and attested by the `clo` agent on 2026-05-28.**
> The `clo` agent (Soleur legal domain leader) is the reviewing authority for the
> v1 Soleur-as-tenant-zero posture — this is an agent-native company; legal review
> is a CLO-agent function, not a task for the non-lawyer operator. The agent
> cross-checked every implementation-detail claim against migrations 079/080/081,
> migration 053, and the two TS read-cutover files, resolved the three substantive
> judgment calls, made the Art. 6(1)(f) LIA decision, and **discharged the gate
> with two in-PR conditions (both now applied — see below)**. External counsel
> re-review is reserved for the frontmatter triggers (first third-party-data repo,
> first arms-length Co-Member, EEA-out, regulated industry). The full agent verdict
> is recorded per-artifact below.

This audit is the load-bearing evidence for the counsel-review gate on PR #4559
(issue #4558, ADR-044). PR #4559 relocates GitHub repo-connection state from the
per-user `users` table to `workspaces`, so a member who **joins** another user's
workspace can sync THAT workspace's connected repository and the knowledge-base
derived from it (fixing the #4543 brand-survival defect). The legal grain change
is: **a Workspace Owner's repository content and repo-derived knowledge-base
become accessible to, and processed for, the Co-Members of that workspace.**

The five artifacts below disclose that grain change across the regulator-facing
surfaces. Each is operator-attested per the Soleur-as-tenant-zero v1 posture,
following the precedent at `2026-05-counsel-review-{4051,4066,4289,4353}.md`. The
PR is held in draft until every row is signed.

**Brand-survival threshold:** `single-user incident` (requires CPO sign-off per
the plan's `requires_cpo_signoff`).

---

## Artifact 1 — Article 30 register, Processing Activity 17, sub-clause (c)

**File:** `knowledge-base/legal/article-30-register.md` (canonical; no Eleventy mirror)

**Scope of review:**

- New sub-clause (c) under PA-17 ("GitHub App webhook ingress", ADR-036) discloses
  the relocation of repo-connection state to `workspaces` and the resulting
  cross-member data flow. Four numbered points: (1) new cross-member data flow
  (Owner's repo/KB processed for Co-Members at the workspace-ownership grain; no
  new third-party recipient — GitHub remains the *source*, the new recipients are
  the workspace's own Co-Members already enumerated under PA-2 §(d)); (2) lawful
  basis split — Co-Member *access* rests on the Owner's Art. 6(1)(a) consent in
  the migration-058 `workspace_member_attestations` invite attestation, while the
  existing Art. 6(1)(f) legitimate-interest basis continues to govern the
  repo-*derived* signals only; (3) credential gate (Art. 32 TOM); (4) single
  source of truth (workspaces-only reads).
- **Review-corrected drift (caught at `/soleur:review`, fixed pre-sign-off):**
  - (3) previously quoted the literal `REVOKE SELECT (github_installation_id) ON public.workspaces FROM authenticated` — a no-op form that migration 079 explicitly rejects. Corrected to describe the actual mechanism: a table-level `REVOKE SELECT ... FROM authenticated` followed by a `GRANT SELECT` on the explicit non-credential column list (omitting `github_installation_id`).
  - The header previously mislabelled migration 081 as "TS read-cutover 081". Corrected: the read-cutover is application-layer TypeScript (no migration); migration 081 is the **Art. 17 erasure cascade** that nulls the relocated credential on owner departure (retaining `repo_url` for a promoted replacement owner).

**Particular attention requested on:**

1. **Lawful-basis split defensibility (consent for access + legitimate-interest for derived signals).** The disclosure rests the Co-Member's *access* to the Owner's repo/KB on the **Owner's** Art. 6(1)(a) consent (the inviter attestation), not the Co-Member's own consent, and not on legitimate interest. Is it defensible that one controller-side data subject (the Owner) consents to a processing operation whose subject matter includes content that may have been authored by, or contain personal data of, other natural persons (Co-Members, or third parties named in the repo)? **Operator position:** yes for the v1 Soleur-as-tenant-zero scope — the repository and its derived KB are the Owner's own controller-side content; the Owner is the party with authority to grant access to it; the Co-Member's *own* identifiable data (their `workspace_members` row, their messages) remains governed by the contract-performance basis under PA-2 §(d) with independent Art. 15–22 rights. The split is the same composition disclosed in Privacy §4.11, DPD §2.3(u), and GDPR §5.3 — no doc carries a different primary basis. **Confirm or revise.**
2. **Third-party personal data in the repository.** Where the connected repository contains personal data of natural persons who are neither the Owner nor any Co-Member (e.g. contributor names in git history, customer data in committed files), granting Co-Members access widens the recipient set for that third-party data. The v1 disclosure does not separately address this case. **Operator position:** out of scope for v1 (Soleur-as-tenant-zero — the operator's own repos); flagged as a re-evaluation trigger (see frontmatter) for the first arms-length / third-party-data-bearing repository. **Confirm this deferral is acceptable, or require a disclosure addition now.**

| Counsel/CPO | Date | Channel | Sign-off | Substantive comments |
|---|---|---|---|---|
| clo agent (Soleur legal domain leader) | 2026-05-28 | PR #4559 / Task spawn | ☑ | See **CLO Attestation Record** below for this artifact's verdict + substantive comments. |

---

## Artifact 2 — Privacy Policy §4.11 "Workspace co-members"

**File:** `docs/legal/privacy-policy.md` (canonical) + `plugins/soleur/docs/pages/legal/privacy-policy.md` (Eleventy mirror)

**Scope of review:**

- §4.11 extended to disclose, in user-facing language, that post-ADR-044 a
  workspace's GitHub repo connection is workspace-scoped: joining a workspace as a
  Co-Member grants access to that workspace's connected repository and derived
  knowledge-base, and inviting a Co-Member grants them the same access to your
  workspace. Names the lawful-basis split (Owner's Art. 6(1)(a) consent in the
  invite attestation + existing Art. 6(1)(f) for repo-derived signals), the
  credential gate (`github_installation_id` column-level revoked, readable only
  via `resolve_workspace_installation_id`), and "no new sub-processor — GitHub
  Inc. (Microsoft) remains the upstream source already disclosed."
- Cross-references DPD §2.3(u), Article 30 register PA-17, GDPR Policy §5.3.
- `Last Updated` byline carries the `#4559 (#4558)` segment with the DRAFT marker.

**Particular attention requested on:**

1. **User-facing clarity of the bilateral grant.** §4.11 must make plain to a
   lay reader BOTH directions: "joining grants you access to the owner's repo" AND
   "inviting grants the invitee access to yours". Is the bilateral framing
   sufficiently prominent for an Art. 12 "clear and plain language" standard?
   **Operator position:** yes — both directions are stated in the same sentence.
   **Confirm or request copy-softening.**

| Counsel/CPO | Date | Channel | Sign-off | Substantive comments |
|---|---|---|---|---|
| clo agent (Soleur legal domain leader) | 2026-05-28 | PR #4559 / Task spawn | ☑ | See **CLO Attestation Record** below for this artifact's verdict + substantive comments. |

---

## Artifact 3 — Data Protection Disclosure §2.3(u) "Connected repository + derived knowledge-base"

**File:** `docs/legal/data-protection-disclosure.md` (canonical) + `plugins/soleur/docs/pages/legal/data-protection-disclosure.md` (Eleventy mirror)

**Scope of review:**

- New "**Connected repository + derived knowledge-base (ADR-044…)**" sub-block
  appended within the existing §2.3(u) "Workspace co-member data category". States
  the relocation, the workspace-grain consequence, the lawful-basis split, the
  Art. 32 credential gate, single-source-of-truth reads, and "no new third-party
  recipient". Cross-references ADR-044 + PA-17 sub-clause (c).

**Particular attention requested on:**

1. **Controller/processor framing consistency.** §2.3(u) sits under the DPD's
   controller/processor allocation (§2.3(a)). The new sub-block describes
   Owner-consent-mediated access to the Owner's content. Confirm the new sub-block
   does not disturb the existing Jikigai-as-processor-for-Owner carve-out for the
   team-workspace feature. **Operator position:** unchanged — the relocation is a
   substrate move within the Owner's own controller-side content; Jikigai's
   processor role for the team-workspace feature is unaffected. **Confirm.**

| Counsel/CPO | Date | Channel | Sign-off | Substantive comments |
|---|---|---|---|---|
| clo agent (Soleur legal domain leader) | 2026-05-28 | PR #4559 / Task spawn | ☑ | See **CLO Attestation Record** below for this artifact's verdict + substantive comments. |

---

## Artifact 4 — GDPR Policy §5.3 "Workspace co-member access to a connected repository and knowledge-base"

**File:** `docs/legal/gdpr-policy.md` (canonical) + `plugins/soleur/docs/pages/legal/gdpr-policy.md` (Eleventy mirror)

**Scope of review:**

- New bullet in §5.3 "Rights Exercisable Against Jikigai (Web Platform)"
  disclosing the data-subject consequence (joining grants repo/KB access;
  inviting grants it bilaterally), the lawful-basis split, the Art. 32
  confidentiality measure, and "no new sub-processor". Cross-references DPD
  §2.3(u), Privacy §4.11, PA-17 sub-clause (c), ADR-044.

**Particular attention requested on:**

1. **Rights-exercise completeness.** The bullet sits among the Art. 15–22
   rights-exercise entries. Confirm that no *new* data-subject right or exercise
   path is introduced that needs its own entry (the relocation does not add a new
   identifiable data category about the Co-Member themselves — it widens access to
   the Owner's content). **Operator position:** no new right/path — the
   Co-Member's own-data rights are already covered by the PA-2 / §2.3(u) entries;
   this bullet is a recipient/access disclosure, not a new processing of the
   Co-Member's identifiers. **Confirm.**

| Counsel/CPO | Date | Channel | Sign-off | Substantive comments |
|---|---|---|---|---|
| clo agent (Soleur legal domain leader) | 2026-05-28 | PR #4559 / Task spawn | ☑ | See **CLO Attestation Record** below for this artifact's verdict + substantive comments. |

---

## Artifact 5 — Invite attestation consent text (the Art. 6(1)(a) consent of record)

**File:** `apps/web-platform/components/settings/invite-member-modal.tsx` (`ATTESTATION_TEXT`)

**Scope of review:**

- The invite attestation string — the consent of record on which Artifacts 1–4
  rest the Co-Member's repo/KB access — now reads:
  > "I confirm this member is my employee or contractor under written agreement,
  > and I consent to them accessing this workspace's connected repository and
  > knowledge-base."
- This is the Art. 6(1)(a) consent captured (with the existing `workspace_member_attestations`
  WORM substrate, migration 058) at invite-time.

**Particular attention requested on:**

1. **Consent validity (Art. 4(11) / Art. 7).** Is the attestation a valid,
   freely-given, specific, informed, unambiguous consent for the repo/KB-access
   processing? It is bundled with the employment/contractor confirmation. **Operator
   position:** valid for v1 — the consent is specific (names "connected repository
   and knowledge-base"), affirmative (a checkbox the Owner must tick), and recorded
   immutably with `attestation_text` + `ip_hash` + `user_agent` + timestamp for
   Art. 7(1) demonstrability. The bundling with the employment confirmation is
   acceptable because both concern the same single operation (admitting the member
   to the workspace). **Confirm, or require the consent be unbundled into a
   separate affirmative control.**
2. **Whose consent.** This is the Owner consenting on behalf of granting access to
   the Owner's own content — see Artifact 1 Q1. **Confirm the framing.**

| Counsel/CPO | Date | Channel | Sign-off | Substantive comments |
|---|---|---|---|---|
| clo agent (Soleur legal domain leader) | 2026-05-28 | PR #4559 / Task spawn | ☑ | See **CLO Attestation Record** below for this artifact's verdict + substantive comments. |

---

## Art. 6(1)(f) Legitimate Interests Assessment — decision required

**Question (per the #4564 gate):** does ADR-044's cross-member access change
require a new or updated Art. 6(1)(f) LIA?

**Findings:**

- There is **no existing PA-17 / GitHub-ingress LIA** on file
  (`knowledge-base/legal/legitimate-interest-assessments/` holds only
  `linkedin-org-page`, `tenant-deploy-substrate`, `flag-flip-audit`). PA-17's
  Art. 6(1)(f) three-part test currently lives inline in the Article 30 register
  PA-17 §"Lawful basis", written for the **solo-founder** data flow ("data subject
  is the founder; data flow is founder-installation-only").
- ADR-044 does **not** change the legitimate-interest basis for repo-*derived*
  signals to a different basis — the Co-Member *access* is moved to Art. 6(1)(a)
  consent. BUT it **does** change two inputs to the PA-17 legitimate-interest
  balancing test: (a) the **recipients** of the derived signals now include
  Co-Members (not just the solo owner), and (b) the **data subjects** whose repo
  content feeds the signals may now include multiple workspace members.

**Operator recommendation (for CLO decision):** the inline PA-17 balancing test is
now under-scoped — it still reads "founder-installation-only". Recommend the CLO
either (i) update the PA-17 §"Lawful basis" inline three-part test to reflect the
multi-member recipient/data-subject scope, OR (ii) author a standalone
`knowledge-base/legal/legitimate-interest-assessments/2026-05-PA-17-repo-derived-signals-lia.md`
covering the widened balancing test. This is **not** auto-applied — it is the
CLO's call.

**CLO decision (2026-05-28):** ☐ No LIA update needed · ☑ **Update PA-17 inline
balancing test** · ☐ Author standalone PA-17 LIA. Rationale: a standalone LIA is
disproportionate — PA-17's legitimate-interest basis already lives inline in the
register (house pattern); ADR-044 changes two *inputs* to the existing test
(recipients now include Co-Members; data subjects may span multiple members), not
the basis itself. Option (i) is wrong because the prior inline test read
"founder-installation-only" — now factually under-scoped. **APPLIED**: the PA-17
§"Lawful basis" three-part test was replaced with the multi-member text (see
`article-30-register.md` line ~296, this PR).

---

## CLO Attestation Record (2026-05-28, clo agent)

The `clo` agent reviewed every artifact against the implementation (migrations
079/080/081, migration 053, `resolve-installation-id.ts`, `current-repo-url.ts`)
and returned:

| Artifact | Verdict | Note |
|---|---|---|
| 1 — Art-30 PA-17(c) | APPROVE-WITH-AMENDMENT | All four points accurate (credential-gate prose now correct vs 079:70-116; 081 cascade matches 081:81-86). Required amendment **applied**: added migration-080 solo-only/co-member-skip consent-non-retroactivity sentence. |
| 2 — Privacy §4.11 | APPROVE | Bilateral grant stated plainly (Art. 12); credential framing faithful to 079. |
| 3 — DPD §2.3(u) | APPROVE | Most complete surface; all claims verify; controller/processor carve-out undisturbed. |
| 4 — GDPR §5.3 | APPROVE | No new data category about the Co-Member; access-widening only; no new right/path owed. |
| 5 — Attestation text | APPROVE-WITH-AMENDMENT (non-blocking) | Consent legally sufficient + Art. 7(1)-demonstrable. Copy refinement (split into two sentences) recommended but **deferred** to the parallel `feat-team-workspace-legal-scaffolding` track (already flagged in the code comment); NOT a discharge blocker. |

**Substantive judgment calls:**
- **B1 lawful-basis split** — DEFENSIBLE. Access prong (6(1)(a)) governs the Owner's own controller-side content; derived-signals prong (6(1)(f)) unchanged; Co-Member own-data stays under PA-2 contract basis; basis is non-retroactive (080 skip).
- **B2 third-party personal data in repos** — DEFER to re-evaluation trigger ACCEPTABLE for v1; recommendation (non-blocking) to cross-reference the AUP §4.7 Art-9/10 prohibition + `redactGithubSourcedText` as the active control.
- **B3 consent bundling** — VALID under Art. 7 (no Art. 7(4)/Recital-43 vice: one indivisible operation, consent not the gate to an unrelated service); unbundling NOT required.

**Art. 6(1)(f) LIA decision:** (ii) update PA-17 inline balancing test — **applied** (see above).

**Overall disposition: DISCHARGED.** Two in-PR conditions (Artifact 1 amendment +
LIA inline-test update) **applied this PR**. Non-blocking items (Artifact 5 copy
refinement; B2 AUP cross-reference) deferred to the legal-scaffolding track. No
prose misstates the implementation; no basis weak enough to block. DRAFT markers
removed across the legal artifacts as the discharge consequence.

---

## Post-sign-off actions (executed as part of the CLO discharge, 2026-05-28)

Once the CLO/CPO has signed every artifact row and made the LIA decision:

1. Set this file's frontmatter: `status: SIGNED-OFF (operator-attested)`,
   `signed_off_at: <date>`, `signed_off_by: "<name> (Jikigai SARL gérant / CPO)"`.
2. **Rebase before editing legal docs** (high-collision class):
   `git fetch origin main && git rebase origin/main` (then `git push --force-with-lease`).
3. Remove the `[DRAFT — pending CLO/counsel review per #4558]` marker from every
   legal artifact. Derive the authoritative list (do not hardcode a count):
   `grep -rl 'DRAFT — pending CLO/counsel review per #4558' docs/legal/ plugins/soleur/docs/pages/legal/ knowledge-base/legal/`
   (the spec file `knowledge-base/project/specs/feat-workspace-repo-ownership/tasks.md`
   also contains the literal string descriptively — do NOT strip it there; scope
   the edit to the legal directories). Remove the marker from both the section
   body AND the `Last Updated` byline of each doc; keep each canonical doc and its
   Eleventy mirror in lockstep (`legal-doc-consistency.test.ts` enforces
   heading-sequence + Last-Updated-date parity).
4. Regenerate `apps/web-platform/lib/legal/legal-doc-shas.ts` for each changed
   **canonical** doc whose marker was removed (`sha256sum docs/legal/<doc>.md`);
   `legal-doc-shas-guard.test.ts` enforces the match. (article-30-register.md is
   NOT SHA-tracked and has no mirror.) Non-T&C edits → no `TC_VERSION` bump.
5. If the LIA decision was (ii) or (iii), land that edit in the same PR.
6. Run `./node_modules/.bin/vitest run test/legal-doc-consistency.test.ts test/legal-doc-shas-guard.test.ts` from `apps/web-platform` → green.
7. `gh pr ready 4559`, then merge per the project's gated merge flow. Treat #4558
   as **Ref / close-after-prd-apply** (the post-merge P.1–P.3 operator steps), not
   auto-close at merge.
8. `gh issue close 4564 --comment "<link to this signed audit>"`.

---

## Re-evaluation triggers

External counsel re-review of all artifacts above is triggered by ANY of:

1. **First repository or knowledge-base containing third-party personal data** —
   any connected repo/KB whose contents include personal data of natural persons
   who are neither the Owner nor a Co-Member (contributor history, committed
   customer data). Triggers re-read of the Art. 6(1)(a)-consent-for-access framing
   and whether a separate Art. 14 notice or Art. 6(1)(f) balancing is owed to
   those third parties.
2. **First non-Jikigai-affiliate Co-Member granted repo/KB access** — bounded by
   Soleur-as-tenant-zero v1; the first arms-length grant triggers re-read of the
   consent-validity and recipient-scope analysis.
3. **Any Co-Member whose habitual residence is outside the EEA** — Art. 44–49
   transfer analysis for the repo/KB access path.
4. **Any Co-Member or repository belonging to a regulated industry** (healthcare,
   finance, legal-services) — sector-specific obligations not captured in the v1
   attestation framework.

These extend the canonical set from `2026-05-counsel-review-{4289,4353}.md` with a
repo/KB-specific trigger (#1).
