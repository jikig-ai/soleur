---
issue: 4329
title: "fix(supabase): mig 064 058-attestations workspace_id RESTRICT FK → SET NULL to unblock Art. 17 orphan-org cleanup"
type: bug-fix
classification: gdpr-art17-blocker
lane: cross-domain
brand_survival_threshold: single-user-incident
requires_cpo_signoff: true
plan: knowledge-base/project/plans/2026-05-22-fix-058-attestations-workspace-id-restrict-art17-erasure-plan.md
---

# Spec: 058 attestations workspace_id FK fix (#4329)

## Problem Statement

`workspace_member_attestations.workspace_id REFERENCES public.workspaces(id) ON DELETE RESTRICT` at migration `058_workspace_member_attestations.sql:43` causes a deterministic GDPR Art. 17 erasure failure for any user who is sole owner of a workspace that has at least one prior attestation row. The cascade in `apps/web-platform/server/account-delete.ts` aborts at step 3.92 (`anonymise_organization_membership`) when its orphan-org branch issues `DELETE FROM public.workspaces` (058:445) and the RESTRICT FK blocks it. The user receives a generic error toast; their data persists past their stated wish to erase.

## Functional Requirements

- **FR1: Demote 058 attestations.workspace_id FK from RESTRICT to SET NULL.** New migration 064.
- **FR2: Allow workspace_id NULL.** `ALTER COLUMN workspace_id DROP NOT NULL` in the same ALTER TABLE statement.
- **FR3: Rewrite WORM trigger to admit the cascade transition.** Mirror migration 062's structural-shape pattern (062:140-212). Strict-immutable lineage = `(id, accepted_at)` only. workspace_id NOT NULL → NULL admissible; NULL → NOT NULL or value-change rejected. 5 PII columns each NOT NULL → NULL admissible (preserved from existing 058 shape).
- **FR4: Preserve all REVOKE/GRANT matrix unchanged.** Re-attach BEFORE UPDATE + BEFORE DELETE triggers.
- **FR5: Document the carve-out in ADR-038 §Invariants.** Cross-reference ADR-039 §Invariants.1.
- **FR6: Update PA-2 + PA-19 cross-references in `article-30-register.md`** to record the carve-out shape.
- **FR7: File follow-up issue #4329-A** at /work Phase 0 for 063 sister-defect (`workspace_member_actions.workspace_id` RESTRICT FK at 063:51). Link `blocks: 4284`.

## Non-Functional Requirements

- **NFR1: Atomicity.** FK swap + DROP NOT NULL in single ALTER TABLE statement (Postgres atomic at statement-level).
- **NFR2: Backward compatibility.** Existing attestation rows unchanged; ALTER widens admissible state-space only.
- **NFR3: Idempotent down-migration.** 0-row guard against silent destroy when any row has workspace_id IS NULL (set by orphan-org cleanup post-064).
- **NFR4: No new sub-processor, no new data category, no new lawful basis** — Art. 5(2) attribution unchanged.

## Acceptance Criteria

See plan §Acceptance Criteria for the canonical 16-AC list (AC1–AC16) + deepen-added AC2.5.

## Out of Scope

- 063 (`workspace_member_actions`) sister-defect — tracked as #4329-A, scope-out per single-concern PR discipline.
- New behavioural integration tests against dev/prd — `apps/web-platform/test/server/account-delete.test.ts` covers the cascade integration already; deepen verifies via Supabase MCP probe at AC16.
- Trigger function reorganisation beyond the workspace_id admit-arm.
