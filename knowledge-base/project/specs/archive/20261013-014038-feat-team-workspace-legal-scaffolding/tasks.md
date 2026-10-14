---
title: Tasks — Team-Workspace Legal Scaffolding (PR #4289)
plan: knowledge-base/project/plans/2026-05-22-feat-team-workspace-legal-scaffolding-plan.md
spec: knowledge-base/project/specs/feat-team-workspace-legal-scaffolding/spec.md
brainstorm: knowledge-base/project/brainstorms/2026-05-22-feat-team-workspace-legal-scaffolding-brainstorm.md
branch: feat-team-workspace-legal-scaffolding
pr: 4289
date: 2026-05-22
lane: cross-domain
brand_survival_threshold: single-user incident
---

# Tasks — Team-Workspace Legal Scaffolding

Derived from `2026-05-22-feat-team-workspace-legal-scaffolding-plan.md` (post-review version). 8 phases, ≈30 tasks. Single PR, monolithic shape.

## Phase 0 — Preconditions

- [ ] 0.1 Read sentinel list at `apps/web-platform/test/legal-doc-consistency.test.ts:80-113`; confirm §Workspace Members + §5.5 + §2.3(u) + §4.11 additions touch zero existing sentinels.
- [ ] 0.2 Verify RCS-jurisdiction canonical = `RCS Paris 927 585 729` (cross-check `docs/legal/data-protection-disclosure.md:177`). Side Letter MUST use this single token; NO secondary RCS-city anywhere in template.
- [ ] 0.3 Confirm next-free letter sequences: DPD §2.3(u), Privacy §4.11, AUP §5.5.
- [ ] 0.4 Run TC enforcement surface parity grep (`rg "tc_accepted_version|TC_VERSION" apps/web-platform/`); record the 4 comparison expressions verbatim for PR-body documentation:
  - middleware.ts:175-177
  - app/(auth)/callback/route.ts:32
  - app/api/accept-terms/route.ts:44+53
  - server/ws-handler.ts:321 + :1100-1230
  Verify all 4 use string-equality against `TC_VERSION` constant (no semver-`<`, no `null` treated as "accepted"). Divergence = P0 inline fix.
- [ ] 0.5 Read `apps/web-platform/app/(auth)/accept-terms/page.tsx` lines 1-60; pick banner insertion point (above existing `<p>` description); reuse `outageBanner` `rounded-lg border` style pattern.

## Phase 1 — Draft 4 Legal Docs + Sync 4 Mirrors

- [ ] 1.1 ToS 2.2.0 §Workspace Members in `docs/legal/terms-and-conditions.md`:
  - [ ] 1.1.1 Identify insertion point (next-free top-level numbered section).
  - [ ] 1.1.2 Draft 3 sub-clauses: (a) owner-as-controller, (b) co-member access framing, (c) owner indemnification including #4231 audit-log carve-out.
  - [ ] 1.1.3 Update `**Last Updated:** May 22, 2026 (<change summary>)` body line.
  - [ ] 1.1.4 Sync mirror at `plugins/soleur/docs/pages/legal/terms-and-conditions.md`; update BOTH hero `<p>Last Updated: May 22, 2026</p>` AND body `**Last Updated:**` lines.
- [ ] 1.2 AUP §5.5 in `docs/legal/acceptable-use-policy.md`:
  - [ ] 1.2.1 Append `### 5.5 Workspace member attestation`; ~80-120 words.
  - [ ] 1.2.2 Update Last Updated body line; sync mirror (both dates).
- [ ] 1.3 DPD §2.3(u) + §4.2 carve-out in `docs/legal/data-protection-disclosure.md`:
  - [ ] 1.3.1 Append §2.3(u) co-member data category (~120-180 words).
  - [ ] 1.3.2 Add §4.2 footer carve-out ("co-members are NOT processors").
  - [ ] 1.3.3 Update Last Updated; sync mirror at `plugins/soleur/docs/pages/legal/data-processing-disclosures.md` (plural stem; both dates).
- [ ] 1.4 Privacy Policy §4.11 + §4.7 recipient note in `docs/legal/privacy-policy.md`:
  - [ ] 1.4.1 Append §4.11 with DUAL-PERSPECTIVE coverage (owner + co-member).
  - [ ] 1.4.2 Add recipient note at §4.7 workspace-data block.
  - [ ] 1.4.3 Update Last Updated; sync mirror (both dates).

## Phase 2 — TC_VERSION + TC_DOCUMENT_SHA Bump

- [ ] 2.1 After all Phase 1 ToS edits are committed (no further `docs/legal/terms-and-conditions.md` changes anticipated), compute `sha256sum docs/legal/terms-and-conditions.md`.
- [ ] 2.2 Edit `apps/web-platform/lib/legal/tc-version.ts`: line 14 → `TC_VERSION = "2.2.0"`; line 35 → `TC_DOCUMENT_SHA = "<sha-from-2.1>"`.
- [ ] 2.3 Run `bash apps/web-platform/scripts/check-tc-document-sha.sh`; expect exit 0.

## Phase 3 — Side Letter Template + Register

- [ ] 3.1 Create `knowledge-base/legal/side-letter-template.md` with §1-§5 + Jikigai signature block (`Jikigai SARL (RCS Paris 927 585 729) — gérant: ___`).
- [ ] 3.2 Create `knowledge-base/legal/side-letter-register.md` (3-column ledger: Counterparty | Workspace ID | Signed at).

## Phase 4 — /accept-terms Banner

- [ ] 4.1 Edit `apps/web-platform/app/(auth)/accept-terms/page.tsx`: insert `<div role="status">` banner above existing `<p>` description.
- [ ] 4.2 Banner predicate reads `tc_accepted_version` server-side; renders iff prior version is non-null AND `!== TC_VERSION`. First-time signups (null prior) hide banner.
- [ ] 4.3 Banner copy: literal "Workspace Members" + literal "May 22, 2026" + link to `/legal/terms-and-conditions`.
- [ ] 4.4 Extend `apps/web-platform/test/accept-terms-copy-regression.test.tsx` with two fixture branches:
  - [ ] 4.4.1 prior-version='2.1.0' → banner renders with all 3 literal strings.
  - [ ] 4.4.2 prior-version=null → banner does NOT render.

## Phase 5 — AC-LEGAL-FLIP + Article 30 Updates

- [ ] 5.1 Edit `knowledge-base/legal/compliance-posture.md:95` — narrow AC-LEGAL-FLIP "Remaining" cell to Doppler-only precondition; reference PR #4289 in past tense.
- [ ] 5.2 Edit `knowledge-base/legal/article-30-register.md:62-67` — remove forward-looking "Flag-flip ON blocked on AC-LEGAL-FLIP" sentence; replace with past-tense reference.

## Phase 6 — Counsel-Review Audit File

- [ ] 6.1 Read `knowledge-base/legal/audits/2026-05-counsel-review-4066.md` as template.
- [ ] 6.2 Create `knowledge-base/legal/audits/2026-05-counsel-review-4289.md`:
  - [ ] 6.2.1 Frontmatter (`type: counsel-review`, `date: 2026-05-22`, `issue: 4284`, `pr: 4289`, `status: SIGNED-OFF (operator-attested)`, `signed_off_by: Jean Deruelle (Jikigai SARL gérant)`).
  - [ ] 6.2.2 5 Artifact sections (ToS / AUP / DPD / Privacy / Side Letter), each with Scope + Particular attention + sign-off table.
  - [ ] 6.2.3 Operator attestation block (canonical phrasing per repo-research §c).
  - [ ] 6.2.4 ≥2 external counsel re-review triggers: (i) first non-Jikigai-affiliate invitee, (ii) any invitee outside EEA, (iii) regulated-industry invitee.
  - [ ] 6.2.5 `## Decision record (replaces ADR-039)` section (2 paragraphs: monolithic-vs-split tradeoff + canonical-date-drift fix consequence).

## Phase 7 — Verify + Push + GDPR-gate

- [ ] 7.1 Run `/soleur:gdpr-gate` against this PR's diff. Capture output in counsel-review audit file. Critical findings → operator-ack + `compliance-posture.md` Active Items row + GH issue `compliance/critical`.
- [ ] 7.2 Local verification:
  - [ ] 7.2.1 `bash apps/web-platform/scripts/check-tc-document-sha.sh` → exit 0.
  - [ ] 7.2.2 `(cd plugins/soleur/docs && npm run build)` Eleventy smoke; check `_site/legal/*.html` renders + no broken internal links.
  - [ ] 7.2.3 `cd apps/web-platform && npx vitest run test/legal-doc-consistency.test.ts test/accept-terms-copy-regression.test.tsx` → 0.
  - [ ] 7.2.4 Re-compute `sha256sum docs/legal/terms-and-conditions.md` matches `tc-version.ts:35` literal (drift check).
- [ ] 7.3 Push branch. Observe CI: `tc-document-sha-guard`, `legal-doc-cross-document-gate`, `scheduled-legal-audit` all green.

## Phase 8 — Review + Merge + Post-Merge Follow-Ups

- [ ] 8.1 Mark PR #4289 ready. `user-impact-reviewer` agent fires automatically (single-user-incident threshold).
- [ ] 8.2 Spawn parallel review agents:
  - [ ] 8.2.1 `pr-review-toolkit:code-reviewer`
  - [ ] 8.2.2 `soleur:legal:legal-compliance-auditor` (full audit of 4 doc changes + Side Letter template + register)
- [ ] 8.3 Address findings inline per `rf-review-finding-default-fix-inline`. P1 blocks merge.
- [ ] 8.4 Verify PR body uses `Ref #4284` (NOT `Closes #4284`): `gh pr view 4289 --json body --jq .body | grep -E '^(Closes|Fixes|Resolves) #4284' | wc -l` → `0`.
- [ ] 8.5 Merge: `gh pr merge 4289 --squash --auto`.
- [ ] 8.6 Post-merge follow-ups:
  - [ ] 8.6.1 Update #4231 issue body (via `gh issue edit 4231` — Phase 12.2 Bash one-liner from plan) noting ToS 2.2.0 indemnification absorbs audit-log scope-bleed carve-out.
  - [ ] 8.6.2 File 4 deferred follow-up issues (per plan "Deferred Follow-Up Issues" section): per-invitee Side Letter, /accept-terms WS recovery banner, #4231 Art-17 cascade, #4231 per-workspace recipient_id_hash salt.
  - [ ] 8.6.3 Doppler flag-flip remains operator-driven via SEPARATE PR; sweeper auto-closes #4284 when both keys land.

## Notes

- `requires_adr: false` — dropped at plan-review (DHH + Simplicity); decision-record absorbed into counsel-review audit §`## Decision record`.
- No middleware edit (banner reads server-side).
- 3-column Side Letter register (columns added when needed).
- Resume prompt for `/clear`-and-resume:
  `/soleur:work knowledge-base/project/plans/2026-05-22-feat-team-workspace-legal-scaffolding-plan.md`
