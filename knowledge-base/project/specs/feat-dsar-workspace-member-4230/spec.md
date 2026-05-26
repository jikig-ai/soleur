---
title: DSAR departed-workspace-member coverage
issue: 4230
umbrella: 4229
brainstorm: knowledge-base/project/brainstorms/2026-05-22-dsar-workspace-member-extension-brainstorm.md
branch: feat-dsar-workspace-member-4230
draft_pr: 4294
status: spec
lane: cross-domain
brand_survival_threshold: single-user incident
user_brand_critical: true
date: 2026-05-22
---

# Spec — DSAR Departed-Workspace-Member Coverage

## Problem Statement

After PR #4225 merged the multi-user team-workspace umbrella (#4229), members
who leave a workspace via `remove_workspace_member` are hard-deleted from
`workspace_members`. The DSAR export pipeline (`dsar-export.ts` from PR #3634)
derives workspace metadata at `:609-670` from current `workspace_members`
membership — after removal, this returns empty. A departed member who exercises
GDPR Art. 15 receives an export containing their user-keyed conversation /
message / KB-contribution rows but **no workspace metadata** (orphan context).
Inviter-side attestation rows are similarly orphaned at `:678-697`. There is
also no removal-event ledger, so Art. 15 cannot answer "you were removed from
$workspace on $date by $whom".

This work blocks `FLAG_TEAM_WORKSPACE_INVITE=1` in prd before the first
non-jikigai workspace per umbrella #4229 deferred-follow-up criteria.

## Goals

- G1: A departed workspace member can exercise Art. 15 / 17 / 20 over their
  identifiable rows in workspaces they have left and receive a complete export
  bundle including workspace metadata for each workspace they were a member of.
- G2: Capture removal events in an append-only audit ledger
  (`workspace_member_removals`) so Art. 15 lineage answers "removed on $date
  by $whom" for every prior membership.
- G3: Prevent surviving members' message content from leaking to a departed
  member via mixed-ownership threads, while preserving thread-position metadata
  so the ex-member's own contributions remain contextualized.
- G4: Land coordinated legal-text updates (DPD §2.3, privacy-policy,
  gdpr-policy, `article-30-register.md` row) in PR #4289 (legal scaffolding
  WIP); cross-link both PRs.

## Non-Goals

- NG1: No `workspace_members.left_at` soft-delete column — hard DELETE preserved;
  lineage moves to new `workspace_member_removals` table (Approach B).
- NG2: No changes to `dsar-reauth.ts` — `auth.users` row survives workspace
  removal; existing step-up reauth handles case (a) ex-members unchanged.
- NG3: No public/unauthenticated DSAR intake form — accountless ex-members are
  served via `legal@jikigai.com` admin runbook. Re-evaluation criteria in
  brainstorm.
- NG4: Resolution of the pre-existing `workspace_members.user_id ON DELETE
  RESTRICT` blocking Art. 17 cascade is NOT in scope; filed as separate P1.
- NG5: `runtime_cost_state` RLS-coverage audit is filed as separate follow-up.
- NG6: Roadmap.md team-workspace-pivot update is filed as separate follow-up.

## Functional Requirements

- **FR1:** When the DSAR exporter resolves `workspaceIds` for a target user
  (`dsar-export.ts:609-670`), it MUST UNION current `workspace_members.user_id`
  matches with historical `workspace_member_attestations.invitee_user_id`
  matches. The merged set drives subsequent `workspaces` row inclusion.
- **FR2:** The attestation export at `dsar-export.ts:678-697` MUST also include
  inviter-side rows where the target user appears as `inviter_user_id` (current
  code uses only `invitee_user_id`).
- **FR3:** A new `workspace_member_removals` WORM table MUST be created with
  columns `(id uuid PK, workspace_id uuid NOT NULL, removed_user_id uuid NULL,
  removed_by_user_id uuid NULL, removed_at timestamptz NOT NULL DEFAULT
  now())`, FKs `ON DELETE SET NULL`, WORM trigger matching the
  `workspace_member_attestations_no_mutate` shape (058 L72-125), and an
  `anonymise_workspace_member_removals(p_user_id uuid)` SECURITY DEFINER RPC
  matching the 058 anonymise shape (NULL out PII, preserve `id`, `workspace_id`,
  `removed_at`).
- **FR4:** The `remove_workspace_member` RPC (058 L294-322) MUST be modified to
  INSERT a `workspace_member_removals` row INSIDE the same transaction as the
  DELETE, capturing `removed_user_id`, `removed_by_user_id` (caller's
  `auth.uid()`), and `removed_at`.
- **FR5:** `dsar-export-allowlist.ts` MUST gain a per-row predicate that, for
  `messages` rows belonging to the target user, returns the full row; for
  `messages` rows where the target user appears as a quoted/replied-to author
  in another member's thread, returns thread-position metadata (`message_id`,
  `thread_id`, `created_at`, `role`) but redacts content. Define a single
  helper used at all four `.eq("user_id", expectedUserId)` sites (L291, 311,
  415, 434).
- **FR6:** `workspace_member_removals` MUST be added to the DSAR allowlist as
  a new ownerField branch (analog to L678-697 attestation entry) keyed on
  `removed_user_id`, so departed members see their own removal events.
- **FR7:** A pg_cron retention sweep MUST be added for
  `workspace_member_removals` matching the 24-mo `dsar_export_audit_pii` envelope
  (mig 041 L383-395 shape). The sweep MUST run via SECURITY DEFINER with a GUC
  bypass for the WORM trigger (`app.workspace_member_removal_anonymise_in_progress
  = 'true'` + `current_user = 'service_role'`).

## Technical Requirements

- **TR1:** ADR required per CTO assessment. Run
  `/soleur:architecture create 'DSAR departed-member coverage via removal-event
  ledger'` before any migration merges. Records the schema invariant that
  future Art. 17 cascades must respect.
- **TR2:** `is_workspace_member()` (053 L130-134) is NOT changed. The helper
  remains active-only; departed-member DSAR resolution flows through the
  service-role exporter, not RLS-via-user-JWT.
- **TR3:** Cross-tenant golden-fixture integration test:
  `test/server/dsar-departed-member.integration.test.ts` MUST synthesize two
  users in the same workspace, remove one, fire a DSAR export for the
  removed user, and assert: (a) the export contains the removed user's
  messages with full content; (b) the export contains workspace metadata
  for the former workspace; (c) the export contains a
  `workspace_member_removals` row recording the removal; (d) the export does
  NOT contain the surviving member's message content (only thread-position
  metadata for the quoted-thread case).
- **TR4:** WORM-table convention adherence (per learning
  `2026-05-21-worm-ledger-rls-owner-insert-policy-is-an-rpc-bypass.md`): NO
  owner-insert RLS policy on `workspace_member_removals`; writes flow only
  through the modified `remove_workspace_member` RPC.
- **TR5:** Migration discipline (per #4241 root cause): do NOT apply migration
  to dev-Supabase ahead of main; let CI apply on merge.
- **TR6:** `cq-pg-security-definer-search-path-pin-pg-temp` — both the
  modified `remove_workspace_member` and the new `anonymise_workspace_member_removals`
  RPCs MUST set `SECURITY DEFINER` + `SET search_path = public, pg_temp`.

## Acceptance Criteria

- **AC1:** FR1+FR2 implemented; departed-member DSAR bundle includes
  workspace metadata + both invitee- and inviter-side attestation rows.
- **AC2:** FR3 migration applied; `workspace_member_removals` table exists
  with WORM trigger + anonymise RPC + GUC bypass.
- **AC3:** FR4 implemented; `remove_workspace_member` writes removal row in
  same transaction; an aborted transaction leaves neither row written nor
  delete applied (verified by transaction-rollback test).
- **AC4:** FR5 implemented; allowlist predicate covers all 4 `.eq("user_id"...)`
  sites with one shared helper.
- **AC5:** FR6+FR7 implemented; allowlist branch + retention sweep.
- **AC6:** TR3 integration test passes; mixed-ownership redaction asserted.
- **AC7:** ADR created and committed (TR1).
- **AC8:** PR cross-links #4289 with comment "departed-member legal text in
  scaffolding PR; code in #<this-PR>".
- **AC9:** `user-impact-reviewer` agent passes at PR review (mandatory per
  `USER_BRAND_CRITICAL=true`).
- **AC10:** `gdpr-gate` skill audit passes the diff (regulated-data surface).
- **AC11:** Operator runbook `knowledge-base/operations/runbooks/dsar-accountless-ex-member-fulfillment.md`
  exists with step-by-step admin procedure + Art. 12(3) 1-month clock tracker
  table template.

## Dependencies

- **DEP1:** Umbrella #4229 (MERGED via PR #4225) — provides
  `workspace_members`, `workspace_member_attestations`, RLS sweep, and
  `is_workspace_member()` helper.
- **DEP2:** DSAR endpoint shipped in PR #3634 (closes #3637) — provides
  `dsar-export.ts`, `dsar-reauth.ts`, `dsar_export_jobs`, allowlist scaffold.
- **DEP3:** PR #4289 (open WIP `feat-team-workspace-legal-scaffolding`) — must
  land with departed-member language in DPD §2.3 + privacy-policy + gdpr-policy
  + `article-30-register.md` row. Cross-link both PRs in their bodies.
- **DEP4:** Issue #4284 (open follow-through to flip
  `FLAG_TEAM_WORKSPACE_INVITE=1`) — gated on this PR + #4289 both landing.

## Risks & Assumptions

- **R1:** Modifying `remove_workspace_member` is a behavior change to a recently
  shipped RPC. Mitigation: keep the DELETE semantics identical; only ADD the
  audit-side INSERT inside the same transaction. Roll back via `DROP TABLE
  workspace_member_removals CASCADE` + revert RPC.
- **R2:** Author-only redaction helper is the load-bearing brand-survival
  surface. Mitigation: integration test in AC6 + `user-impact-reviewer` agent.
- **R3:** ADR (TR1) may surface additional consultations (`/soleur:architecture`
  invokes `ddd-architect` agent) that extend plan-time. Mitigation: budget +1
  day for ADR cycle.
- **A1:** Operator's prospect (10-person team) does not require accountless
  ex-member DSAR fulfillment at gate. If false, the runbook (AC11) is
  insufficient and `legal@jikigai.com` volume forces a public-form brainstorm
  ahead of plan.
- **A2:** Existing 24-mo `dsar_export_audit_pii` retention is the right
  envelope for `workspace_member_removals`. To be confirmed at plan time
  (Open Question 3 in brainstorm).

## Estimate

3-5 days (Approach A + B combined) per CTO assessment, +1 day for ADR cycle.
Plan: 4-6 days end-to-end including review iterations.
