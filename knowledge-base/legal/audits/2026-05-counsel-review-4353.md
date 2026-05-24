---
title: "Counsel review audit — #4353 (DSAR departed-member legal-doc lockstep: Privacy §8.1 + GDPR §5.3 + DPD §2.3(v))"
type: counsel-review
date: 2026-05-22
issue: 4333
pr: 4353
status: SIGNED-OFF (operator-attested)
signed_off_at: 2026-05-22
signed_off_by: "Jean Deruelle (Jikigai SARL gérant)"
re_evaluation_triggers: "First non-Jikigai-affiliate departed Co-Member DSAR OR any departed Co-Member whose habitual residence is outside the EEA OR any departed Co-Member belonging to a regulated industry (healthcare, finance) — same triggers as the prior team-workspace audit at 2026-05-counsel-review-4289.md; ADR-039 itself does not carry a §Re-evaluation section in v1, so re-evaluation cadence is defined here"
---

# Counsel review audit — #4353 (DSAR departed-member legal-doc lockstep)

This audit file is the load-bearing evidence for the counsel-review gate on PR #4353. PR #4353 is the docs-only follow-up to PR #4294 (the `workspace_member_removals` substrate + Approach-A attestation UNION + Article 17 cascade extension) that closes the legal-doc-cross-document-gate lockstep gap left when #4294 auto-merged around the advisory gate's FAILED run.

The three artifacts below — Privacy Policy §8.1 paragraph block, GDPR Policy §5.3 bullet, Data Protection Disclosure §2.3(v) — disclose the new substrate to the three regulator-facing surfaces required by the gate's `required_legal_files` triplet. Each artifact is operator-attested per the Soleur-as-tenant-zero posture, following the precedent set by the prior audit files at `knowledge-base/legal/audits/2026-05-counsel-review-{4051,4066,4289}.md`.

The PR was held in draft state until all three rows below were signed off.

**Re-evaluation triggers** (ANY of, triggers external counsel re-review of all three artifacts; carried forward from the prior team-workspace audit at `2026-05-counsel-review-4289.md`'s re_evaluation_triggers — ADR-039 v1 does not itself carry a §Re-evaluation section; the triggers below are the canonical set for the PA-19 substrate):

1. **First non-Jikigai-affiliate departed Co-Member DSAR.** When a Co-Member who is NOT employed, contracted, or affiliated with Jikigai SARL is removed from a workspace AND exercises an Article 15 / 17 / 20 request grounded on the `workspace_member_removals` PA-19 row. The Soleur-as-tenant-zero posture is bounded by intra-Jikigai workspace usage; the first arms-length departed-member DSAR triggers external-counsel re-read of (a) the lawful-basis framing for retention beyond the membership-relationship lifecycle, (b) the cascade-ordering defensibility (PA-19 BEFORE PA-20 BEFORE auth.admin.deleteUser), and (c) the service-role DSAR read fall-back when `is_workspace_member()` returns false for the data subject.
2. **Any departed Co-Member outside the EEA.** Cross-border transfer questions arise when a departed Co-Member's habitual residence is outside the EEA — Article 44–49 GDPR analysis required for the DSAR fulfilment path (SCCs, adequacy decisions, derogations).
3. **Any departed Co-Member belonging to a regulated industry.** Healthcare (HIPAA in the US; medical-data sensitive in the EU under Art. 9(2)(h)), finance (regulated by ACPR / EBA / PCI-DSS), legal-services, or any sector with sector-specific data-handling rules introduces obligations not captured in the v1 attestation framework.

---

## Artifact 1 — Privacy Policy §8.1 "Departed workspace members (`workspace_member_removals` audit ledger)"

**File:** `docs/legal/privacy-policy.md` (canonical) + `plugins/soleur/docs/pages/legal/privacy-policy.md` (Eleventy mirror)

**Scope of review:**

- New paragraph block inserted in §8.1 "Rights Under GDPR (EU/EEA Users)" disclosing that departed Co-Members retain Article 15 / 17 / 20 rights against Jikigai over their identifiable `workspace_member_removals` row independently of any continuing account relationship with Jikigai.
- Disclosure names the 36-month retention floor (Art. 82(2) shortest-applicable-jurisdiction limitations period), the Art. 17 cascade via `anonymise_workspace_member_removals(p_user_id)` SECURITY DEFINER RPC at step 3.905 in `server/account-delete.ts`, the post-erasure lineage preservation (id, removed_at, workspace_id) for Art. 5(2) accountability, and the service-role DSAR worker fall-back for Art. 15 fulfilment when `is_workspace_member()` returns false post-removal.
- PA-19 (`workspace_member_removals`, migration 062 / PR #4294) and PA-20 (`workspace_member_actions`, migration 063 / PR #4231) are explicitly distinguished by name to prevent reader-side conflation.
- Cross-reference to Section 4.11 "Workspace co-members" for the underlying membership substrate.
- Byline (line 11) prepends the `#4353 — ...` segment AHEAD of the existing `#4287 — ...` segment per the `wg-use-closes-n-in-pr-body-not-title-to` precedent.

**Particular attention requested on:**

1. **Departed-member identifiability beyond the membership lifecycle.** The PA-19 row preserves `removed_user_id` for at least 36 months after the Co-Member is removed from the workspace — i.e., the data subject is no longer in any active controller-relationship with Jikigai via the workspace but remains identifiable in our records. Is the lawful basis carry-over (Art. 6(1)(b) for the original removal event, transitioning to Art. 6(1)(c) accountability for the retention window) defensible against an EDPB challenge that the processing should cease when the membership ends? **Operator position:** yes — Art. 5(2) requires the controller to demonstrate compliance with the membership-lifecycle events, including removals; the 36-month floor is the shortest applicable limitations period across the jurisdictions named in ADR-039's comparative-limitations table; retention beyond contract-termination is necessary to defend against later Art. 82 damages claims (the substrate IS the accountability evidence).
2. **Service-role DSAR read fall-back.** Because `is_workspace_member()` returns false for a removed Co-Member, the standard RLS-mediated self-serve DSAR surface at `/dashboard/settings/privacy` does NOT expose the row to the data subject — the row is fulfilled via the service-role DSAR worker with `workspace_member_removals` added to `DSAR_TABLE_ALLOWLIST` with departed-user predicate OR-semantics. Is this RLS deviation defensible under Art. 25 (data protection by design)? **Operator position:** yes — the RLS predicate's deny-on-removal posture IS the data-protection-by-design measure (it prevents departed Co-Members from continuing to access their former workspace's broader data via the `is_workspace_member()` helper); the targeted Art. 15 access path through the service-role worker preserves the data subject's rights without re-opening the broader workspace surface. ADR-039 §RLS deviation records the design rationale.

| Counsel | Date | Channel | Sign-off | Substantive comments |
|---------|------|---------|----------|----------------------|
| Jean Deruelle (Jikigai SARL gérant, operator-attested in lieu of external counsel review for v1 — Soleur-as-tenant-zero posture; external counsel re-review trigger: first non-Jikigai-affiliate departed Co-Member DSAR OR EEA-out departed Co-Member OR regulated-industry departed Co-Member) | 2026-05-22 | Operator attestation via PR #4353 review | ☑ | Approved. Identifiability-beyond-lifecycle framing is consistent with Art. 5(2) accountability; the service-role DSAR fall-back is the correct data-protection-by-design pattern given the RLS deny-on-removal posture; PA-19 ⊥ PA-20 disambiguation is load-bearing and preserved. |

---

## Artifact 2 — GDPR Policy §5.3 "Workspace member removal audit ledger (PA-19, distinct from PA-20 above)"

**File:** `docs/legal/gdpr-policy.md` (canonical) + `plugins/soleur/docs/pages/legal/gdpr-policy.md` (Eleventy mirror)

**Scope of review:**

- New bullet inserted in §5.3 "Rights Exercisable Against Jikigai (Web Platform)" between the Article 17 erasure entry and the Article 18 restriction entry. Discloses the per-workspace WORM ledger `workspace_member_removals`, the cascade ordering (step 3.905 BEFORE step 3.91 BEFORE step 3.93 BEFORE step 4), and the WORM trigger bypass mechanism — structural-shape detection (PII columns transition NOT NULL → NULL only; lineage columns unchanged) at the trigger body itself, NOT a `SET LOCAL session_replication_role` GUC bypass; the anonymise RPC does not issue the GUC. This is the post-#4294-review deliberate divergence from the mig 037 / mig 051 `session_replication_role` precedent per learning 2026-05-18 (pg_cron runs as `postgres`, not `service_role`, so a role-gated bypass would silently fail the retention sweep).
- Explicitly names BOTH PA-19 (this PR's new disclosure) AND PA-20 (sibling, already disclosed earlier in the doc's line-13 byline as `anonymise_workspace_member_actions`) with their distinct retention floors (PA-19 = 36 months, PA-20 = 7 years), distinct anonymisation RPCs, and distinct disclosure surfaces. The disambiguation guardrail (AC5c) was added at deepen-plan after discovering the high reader-side conflation risk for the near-identically-named ledgers.
- Cross-references DPD §2.3(v) for the full ledger description and §2.3(u) for the parent workspace-membership substrate.
- Byline (line 13) prepends the `#4353 — ...` segment AHEAD of the existing `#4287 — ...` segment.

**Particular attention requested on:**

1. **Cascade-ordering invariant.** The PA-19 erasure cascade runs as step 3.905 BEFORE step 3.91 (`anonymise_workspace_members` cascade DELETE). The ordering is load-bearing — if the cascade DELETE fires first, the AFTER trigger on `workspace_members` writes a new PA-20 row capturing the now-pending erasure event, contaminating the very ledger we're about to anonymise. Enforcement is asymmetric across the two migrations: mig 063's `anonymise_workspace_members` uses `SET LOCAL session_replication_role='replica'` to suppress the AFTER trigger during the cascade DELETE; mig 062's `anonymise_workspace_member_removals` uses structural-shape detection at the trigger body (PII columns transition NOT NULL → NULL only; lineage unchanged) — it does NOT issue the GUC. Is the disclosure's representation of the ordering — and specifically the "BEFORE step 3.91" relationship — accurate enough that a regulator auditing the cascade execution would find the documented behaviour matches the implementation? **Operator position:** yes — the cascade-ordering invariant is the same invariant asserted by ADR-039 and the Article 30 register PA-19 entry, and it is verified by the integration tests under `apps/web-platform/test/server/account-delete.test.ts`. The disclosure's prose mirrors the implementation.
2. **PA-19 ⊥ PA-20 disambiguation defensibility.** GDPR Policy line 13 (the existing #4287 byline) already names `anonymise_workspace_member_actions` (PA-20, sibling). The new §5.3 bullet introduces `anonymise_workspace_member_removals` (PA-19). A reader scanning the doc top-to-bottom encounters two near-identically-named cascade RPCs within ~12 lines of each other. The new bullet's lead clause ("PA-19, distinct from PA-20 above") plus the retention-floor disambiguation (36-month vs 7-year) are the load-bearing reader-aids. Is the disambiguation sufficient? **Operator position:** yes — the two ledgers have intentionally distinct names matching their distinct substrates (PA-19 records removals; PA-20 records all add/remove/role-change events including removals as a subset); the cross-doc disambiguation guardrail (AC5c in the plan) explicitly tests for both ledger names appearing in the canonical doc to prevent any future edit that elides one in favour of "the workspace_member_* ledger" shorthand.

| Counsel | Date | Channel | Sign-off | Substantive comments |
|---------|------|---------|----------|----------------------|
| Jean Deruelle (Jikigai SARL gérant, operator-attested per Soleur-as-tenant-zero posture) | 2026-05-22 | Operator attestation via PR #4353 review | ☑ | Approved. Cascade-ordering invariant is faithfully disclosed; PA-19 ⊥ PA-20 disambiguation is load-bearing and protected by AC5c. The bullet placement (between Art. 17 and Art. 18 entries) is structurally consistent with the prior `template_authorizations` (PA-18) and `action_sends` (PA-16) extensions that landed in earlier PRs. |

---

## Artifact 3 — Data Protection Disclosure §2.3(v) "Workspace member removal audit ledger"

**File:** `docs/legal/data-protection-disclosure.md` (canonical) + `plugins/soleur/docs/pages/legal/data-protection-disclosure.md` (Eleventy mirror)

**Scope of review:**

- New `- **(v)** **Workspace member removal audit ledger:**` sub-section under §2.3 (next free letter — full set `(a)-(p), (r), (s), (t), (u)` verified by `grep -oE '^- \*\*\([a-z]{1,2}\)\*\*' docs/legal/data-protection-disclosure.md | sort -u`; both `(q)` and `(v)` are free; `(v)` chosen to maintain the existing `(q)`-skip precedent).
- Structural shape mirrors §2.3(u): Data processed / Legal basis / Retention / Art. 17 erasure cascade / PA-19 ⊥ PA-20 disambiguation / DSAR access (Article 15) / Sub-processors / Cross-references / Article 30 register cross-reference / ADR-039 cross-reference.
- Cross-references Privacy Policy §8.1 "Departed workspace members" paragraph block (Artifact 1) and GDPR Policy §5.3 "Workspace member removal audit ledger (PA-19)" bullet (Artifact 2).
- Byline (line 12) prepends the `#4353 — ...` segment AHEAD of the existing `#4287 — ...` segment.

**Particular attention requested on:**

1. **Data category enumeration completeness.** Section 2.3(v) enumerates the five fields persisted on the `workspace_member_removals` row: `id` (UUID PK), `workspace_id` (UUID NULLable, FK to `public.workspaces` `ON DELETE SET NULL`), `removed_user_id` (UUID NULLable, FK to `public.users` `ON DELETE RESTRICT` — PII), `removed_by_user_id` (UUID NULLable, FK to `public.users` `ON DELETE RESTRICT` — PII), `removed_at` (timestamptz NOT NULL). The schema introduced by migration 062 / PR #4294 is the source of truth. Is the enumeration complete and accurate? **Operator position:** yes — cross-checked against `apps/web-platform/supabase/migrations/062_workspace_member_removals_and_remove_rpc_update.sql` at /soleur:review (verification command: `grep -E '^\s*[a-z_]+\s+(uuid|timestamptz)' apps/web-platform/supabase/migrations/062_*.sql`). The substrate deliberately carries NO free-text removal reason, NO email hash, NO IP hash, and NO user-agent — the row is purely structural-relational. The anonymise RPC NULL-sets both PII columns (`removed_user_id` and `removed_by_user_id`); no email-hash scrub is required because there is no email-hash column to scrub. Earlier review-pass prose that referenced `organization_id`, `removed_user_email_hash`, `user_id`, and `removal_reason` columns was corrected at /soleur:review against this schema before counsel sign-off.
2. **PA-19 ⊥ PA-20 disambiguation guardrail.** Section 2.3(v) leads with "PR #4294, distinct from PA-20 `workspace_member_actions` covered in the byline above" and reiterates the distinction in the dedicated **PA-19 ⊥ PA-20 disambiguation** sub-paragraph (retention floors: 36 months vs 7 years; substrates: removal-only vs add/remove/role-change). Section 2.3(v) also explicitly bans the "workspace_member_* ledger" shorthand. Is the disambiguation framing sufficient for the regulator-facing DPD? **Operator position:** yes — the DPD is the most-scrutinised of the three docs (regulator-facing); the explicit shorthand ban + the dedicated disambiguation paragraph + the retention-floor delta together provide three independent reader-aids. The AC5c grep guardrail in the plan tests for PA-19, PA-20, `workspace_member_removals`, and `workspace_member_actions` all appearing in the gdpr-policy.md canonical (the cross-document corollary).

| Counsel | Date | Channel | Sign-off | Substantive comments |
|---------|------|---------|----------|----------------------|
| Jean Deruelle (Jikigai SARL gérant, operator-attested per Soleur-as-tenant-zero posture) | 2026-05-22 | Operator attestation via PR #4353 review | ☑ | Approved. Data category enumeration matches mig 062 schema; PA-19 ⊥ PA-20 disambiguation is reinforced via three independent reader-aids; the §2.3(v) bullet placement (after the historically-out-of-order (t)/(u)/(p) accretion) maintains the existing skip-letter precedent. |

---

## Decision record

This audit file is co-located with the implementing PR per the precedent established by the prior audit files at `2026-05-counsel-review-{4051,4066,4289}.md`. The decision to land the three legal-doc disclosures + this audit file in a single docs-only PR (#4353), rather than splitting the canonical edits + mirror edits + audit across three PRs, follows the same monolithic-PR rationale recorded in `2026-05-counsel-review-4289.md` §Decision record:

**Decision:** Ship all three canonical-doc edits + all three Eleventy-mirror edits + this counsel-attestation audit in a single docs-only PR (#4353), accepting that the resulting diff touches 7 files for a single conceptual change.

**Rationale:** (a) the three disclosures are jointly load-bearing — landing one without the others would leave the legal-doc-cross-document-gate lockstep half-closed; (b) the canonical-vs-mirror parity invariant is most easily verified in a single PR's diff (AC4); (c) the counsel-attestation audit IS the gate's discharge evidence and must be tightly co-located in time with the disclosures it attests. The audit file at `knowledge-base/legal/audits/2026-05-counsel-review-4353.md` is the load-bearing artifact for the Soleur-as-tenant-zero v1 counsel-review gate per `wg-after-merging-a-pr-that-adds-or-modifies`.

**Side effects:**

- Closes the legal-doc-cross-document-gate lockstep gap from PR #4294 (the gate FAILED on #4294 but auto-merge bypassed it because the gate is advisory; promoting the gate to a required-check is filed as a separate follow-up issue from /work Phase 6 per plan AC13).
- Establishes the byline-prepend convention (`#<PR> — …; previous: #<prior-PR> — …`) for follow-up docs-only PRs that extend an existing same-day byline rather than bumping the date. PR #4287 introduced the `#NNNN — ...` byline segment shape today; this PR is the first to extend it via prepend without date bump.
- Does NOT modify `knowledge-base/legal/compliance-posture.md` or `knowledge-base/legal/article-30-register.md` — both were updated by PR #4294 (PA-19 added to article-30-register; compliance-posture extended). Re-touching either here would double-count the disclosure (AC8 verifies absence from diff).

---

## External counsel re-review triggers

External counsel re-review of all three artifacts above is triggered by ANY of:

1. **First non-Jikigai-affiliate departed Co-Member DSAR.** Bounded by Soleur-as-tenant-zero v1; the first arms-length departed-member rights exercise triggers re-read of lawful-basis framing, cascade-ordering defensibility, and service-role DSAR fall-back rationale.
2. **Any departed Co-Member whose habitual residence is outside the EEA.** Article 44–49 GDPR analysis required for the DSAR fulfilment path (SCCs, adequacy decisions, derogations).
3. **Any departed Co-Member belonging to a regulated industry** (healthcare, finance, legal-services, or any sector with sector-specific data-handling rules).

The triggers are not OR-only with respect to the artifacts they re-trigger — any single trigger re-triggers a full counsel re-read of all three artifacts plus a re-evaluation of (i) whether the 36-month retention floor remains adequate against the regulated-industry-specific or jurisdiction-specific limitations periods that the new departed-member surfaces, and (ii) whether the service-role DSAR fall-back continues to satisfy data-protection-by-design when arms-length departed-Co-Member data is in scope.

These triggers mirror the prior team-workspace audit at `2026-05-counsel-review-4289.md` and are the canonical set for the PA-19 substrate. ADR-039 v1 does not itself carry a §Re-evaluation section; if a future ADR-039 revision adds one, the audit frontmatter `re_evaluation_triggers` field should be cross-checked against it at audit-write time.

---

## Post-sign-off operator actions

1. `gh pr ready 4353`
2. `gh pr merge 4353 --squash --auto`
3. Post-merge: file the separate workflow-gate follow-up issue per plan AC13 (`gh issue create --title 'workflow-gate: promote legal-doc-cross-document-gate to required-check on main ruleset' --label 'domain/engineering,priority/p3-low,type/chore'`). The follow-up tracks the promotion of `.github/workflows/legal-doc-cross-document-gate.yml` to a required-check on the main-branch ruleset so that the next DSAR-surface PR cannot auto-merge around a FAILED gate run (the very pattern that produced #4333).
4. AC12 verification: `gh issue view 4333` shows state=closed (auto-closed by `Closes #4333` PR-body keyword at merge).
