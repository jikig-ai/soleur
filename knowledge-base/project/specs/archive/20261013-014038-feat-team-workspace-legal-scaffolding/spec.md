---
title: Team-Workspace Legal Scaffolding (ToS 2.2.0 + AUP §5.5 + DPD §2.3 + Privacy §4.x + Side Letter)
status: specified
issue: 4284
brainstorm: knowledge-base/project/brainstorms/2026-05-22-feat-team-workspace-legal-scaffolding-brainstorm.md
branch: feat-team-workspace-legal-scaffolding
pr: 4289
source_pr: 4225
parent_umbrella: 4229
date: 2026-05-22
lane: cross-domain
brand_survival_threshold: single-user incident
requires_clo_signoff: true
requires_cpo_signoff: true
requires_cto_signoff: true
requires_adr: true
---

# Spec — Team-Workspace Legal Scaffolding

## Problem Statement

PR #4225 (`feat-team-workspace-multi-user`) shipped the schema, RLS rewrite,
DSAR cascade, and feature-flagged invite UI for first-class organizations +
workspaces + workspace_members. The feature is dormant until both
`FLAG_TEAM_WORKSPACE_INVITE=1` is set in prd Doppler AND
`TEAM_WORKSPACE_ALLOWLIST_ORG_IDS` includes Jikigai's `org_id`. Per
AC-LEGAL-FLIP (`knowledge-base/legal/compliance-posture.md:95`), the flip
is blocked until this PR lands the legal scaffolding (ToS 2.2.0 + AUP §5.5
+ DPD §2.3 + Side Letter), with Privacy Policy §4.x added in scope after
CLO review.

## Goals

- G1: ToS 2.2.0 §Workspace Members published (canonical + Eleventy mirror)
  with owner-as-controller framing, co-member access framing, and owner
  indemnification including audit-log scope-bleed carve-out (#4231).
- G2: TC_VERSION bumped 2.1.0 → 2.2.0 with TC_DOCUMENT_SHA refresh.
- G3: AUP §5.5 published (canonical + mirror) — owner attestation that
  invitees are under employment/contractor agreement until customer-DPA ships.
- G4: DPD §2.3(u) + §4.2 carve-out published (canonical + mirror) —
  workspace co-member as data category; co-members are NOT processors.
- G5: Privacy Policy §4.11 + recipient note at workspace-data block —
  Art. 13(1)(e) user-facing notice.
- G6: Side Letter template + signature register + operator-attested counsel
  review audit file landed.
- G7: `/accept-terms` page disclosure copy explains the 2.2.0 change.
- G8: AC-LEGAL-FLIP row at `compliance-posture.md:95` narrowed to
  Doppler-only precondition (or moved to Completed Compliance Work).
- G9: ADR recorded for the re-acceptance-wave-on-merge tradeoff.
- G10: #4231 spec updated noting ToS 2.2.0 already absorbs audit-log
  indemnification carve-out.

## Non-Goals

- N1: Customer-facing DPA template (parallel CLO track; not gated by
  AC-LEGAL-FLIP for jikigai-internal flip).
- N2: Click-to-attest checkbox in invite UI (CPO ruled out for v1).
- N3: Splitting the PR into doc-only + flag-flip (operator chose monolithic).
- N4: New runtime code paths, schema, or feature flags (doc + version
  literal + audit file only).
- N5: External counsel engagement before merge (operator-attested per
  #4081/#4066/#4213 precedent; external re-review trigger documented in
  audit file).
- N6: Doppler `FLAG_TEAM_WORKSPACE_INVITE=1` flip (lives in a follow-up
  PR; this PR only narrows the AC-LEGAL-FLIP precondition).

## Functional Requirements

- FR1: ToS 2.2.0 §Workspace Members text includes (a) owner-as-controller
  framing, (b) co-member access framing ("access under owner's account"),
  (c) owner indemnification including audit-log scope-bleed carve-out
  citing workspace_member_actions.
- FR2: `**Last Updated:** May 22, 2026` line present in every changed
  canonical doc body AND mirror hero, matching regex
  `[A-Z][a-z]+\s+\d{1,2},\s+\d{4}`.
- FR3: AUP §5.5 owner attestation text + cross-reference from existing AUP
  scope clause.
- FR4: DPD §2.3(u) co-member data-category sub-section + DPD §4.2 carve-out
  ("co-members are NOT processors").
- FR5: Privacy Policy §4.11 co-member data-class disclosure (parallel to
  §4.10 LinkedIn pattern) + recipient note at the workspace-data block.
- FR6: Side Letter template at `docs/legal/side-letter-template.md` with
  confidentiality + IP assignment + workspace-activity-logged + audit-log
  visibility acknowledgement. RCS jurisdiction token = "RCS Paris".
- FR7: Side Letter register at `knowledge-base/legal/side-letter-register.md`
  mirroring `tenant-dpa-register.md` shape.
- FR8: Counsel review audit file at
  `knowledge-base/legal/audits/2026-05-22-counsel-review-team-workspace.md`
  with operator attestation (Jean as Jikigai SARL gérant) + external
  re-review trigger list.
- FR9: `/accept-terms` page disclosure text (location TBD during build —
  likely an Art. 13(3) "we updated terms" banner above the existing accept
  flow).
- FR10: AC-LEGAL-FLIP row at `compliance-posture.md:95` updated to narrow
  remaining precondition list.

## Technical Requirements

- TR1: TC_VERSION literal at `apps/web-platform/lib/legal/tc-version.ts:14`
  bumped 2.1.0 → 2.2.0.
- TR2: TC_DOCUMENT_SHA literal at the same file refreshed via
  `sha256sum docs/legal/terms-and-conditions.md`.
- TR3: Eleventy mirror parity for every changed canonical doc — assertion
  enforced by `apps/web-platform/test/legal-doc-consistency.test.ts:71-78`
  (heading sequence) and lines 115-135 (date equality).
- TR4: Sentinel-string regression check before push — grep new copy against
  `legal-doc-consistency.test.ts:80-113` regex set.
- TR5: RCS-jurisdiction invariant — Side Letter must use "RCS Paris" only
  per `legal-doc-consistency.test.ts:137-189` `tokens.size === 1` assertion.
- TR6: CI gates that must pass — `tc-document-sha-guard`,
  `legal-doc-cross-document-gate`, `scheduled-legal-audit`.
- TR7: ADR created via `/soleur:architecture create` recording the
  monolithic-PR decision and its re-acceptance-wave tradeoff.
- TR8: No new code paths beyond TC_VERSION + TC_DOCUMENT_SHA literals;
  DSAR_TABLE_ALLOWLIST already covers workspace tables (per #4225).

## User-Brand Impact

`USER_BRAND_CRITICAL=true`. Threshold: `single-user incident`. Vectors:
trust breach / cross-tenant read (owner-as-controller framing must be
correct); user data exposure (Privacy Policy §4.11 must be live before
flag flips); disclosure / Art-13 gap (re-acceptance fires immediately on
merge per `middleware.ts:175-177`, so `/accept-terms` copy must explain
the change).

The `user-impact-reviewer` agent at PR review is the load-bearing gate.
Plan (if produced) inherits this section verbatim.

## Domain Review (carry-forward)

- **CLO:** Approved with deliverable list a–e (brainstorm Phase 0.5).
  Required additions beyond original brainstorm: Privacy Policy §4.11,
  Side Letter register, audit-log carve-out in ToS indemnification.
- **CPO:** Approved with operator override on PR shape (monolithic over
  recommended split). Off-platform Side Letter PDF; no click-to-attest in v1.
- **CTO:** Approved with sequencing notes — middleware re-acceptance fires
  immediately on merge (no flag guard); TC_VERSION ↔ TC_DOCUMENT_SHA
  coupled only for ToS canonical; DSAR allowlist already covers workspace
  tables; 4 doc-only sharp edges captured in TR4/TR5/FR2.

## Acceptance Criteria

- [ ] G1 — ToS 2.2.0 §Workspace Members live with all 3 sub-clauses (FR1)
- [ ] G2 — TC_VERSION 2.1.0 → 2.2.0 + SHA refresh + CI green
- [ ] G3 — AUP §5.5 live with owner attestation language
- [ ] G4 — DPD §2.3(u) + §4.2 carve-out live
- [ ] G5 — Privacy Policy §4.11 + recipient note live
- [ ] G6 — Side Letter template + register + audit file landed
- [ ] G7 — `/accept-terms` disclosure copy live
- [ ] G8 — AC-LEGAL-FLIP row narrowed at `compliance-posture.md:95`
- [ ] G9 — ADR landed via `/soleur:architecture create`
- [ ] G10 — #4231 spec updated noting audit-log carve-out absorbed
- [ ] CI green: `tc-document-sha-guard` + `legal-doc-cross-document-gate`
      + `scheduled-legal-audit` + `legal-doc-consistency.test.ts`
- [ ] User-impact-reviewer pass before merge
- [ ] Operator counsel attestation signed in audit file
