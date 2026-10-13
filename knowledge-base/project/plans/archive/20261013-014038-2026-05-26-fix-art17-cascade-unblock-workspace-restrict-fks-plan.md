---
title: "fix(schema): Art. 17 cascade unblock — workspace_members.user_id + workspace_member_actions.workspace_id RESTRICT FK repair"
type: fix
date: 2026-05-26
issues: [4299, 4355]
branch: feat-one-shot-4299-4355-art17-cascade-unblock
lane: cross-domain
classification: regulated-data-write
brand_survival_threshold: single-user-incident
requires_cpo_signoff: true
predecessor_prs: [4357, 4231, 4294]
umbrella_issue: 4229
flag_flip_blocker: 4284
deepened: false
---

# fix(schema): Art. 17 cascade unblock — workspace_members + workspace_member_actions RESTRICT FK repair

## Overview

Two `ON DELETE RESTRICT` foreign keys in the team-workspace schema block the GDPR Art. 17
erasure cascade under edge conditions that will become reachable the moment
`TEAM_WORKSPACE_INVITE_ENABLED` flips to 1 in production:

1. **#4299 — `workspace_members.user_id` RESTRICT (mig 053:83).** The existing cascade at
   `account-delete.ts` step 3.91 already calls `anonymise_workspace_members(p_user_id)`
   which DELETEs membership rows BEFORE `auth.admin.deleteUser()` fires — so the RESTRICT
   FK does not currently block Art. 17 erasure. However, the issue specifies two residual
   concerns the plan must address:
   - **Verification that the existing cascade is complete** — step 3.91 must provably clear
     ALL workspace_members rows referencing the departing user (including those where the
     user is a member of OTHER users' workspaces post-flag-flip), not just the solo
     backfill row.
   - **workspace_member_attestations FKs** — `invitee_user_id` and `inviter_user_id`
     (mig 058:45-46, both `ON DELETE RESTRICT`) must be confirmed as handled by the
     existing step 3.90 (`anonymise_workspace_member_attestations`).

2. **#4355 — `workspace_member_actions.workspace_id` RESTRICT (mig 063:51).** Post-mig-065,
   orphan workspaces are NOT hard-deleted — they survive with NULL-owner orgs. But the
   RESTRICT FK creates a latent deadlock: any future maintenance code that attempts to
   DELETE a workspace (janitor, data migration, manual cleanup) will be blocked by the
   audit rows. The fix shape mirrors mig 062 (`workspace_member_removals`): change the FK
   to `ON DELETE SET NULL`, drop the NOT NULL constraint on `workspace_id`, and add a
   structural-shape WORM trigger carve-out that permits the NOT NULL -> NULL transition.

   **Empirical answer to the #4355 psql probe:** YES — ON DELETE SET NULL fires BEFORE
   UPDATE triggers. This is confirmed by the mig 065/066 learning
   (`2026-05-25-art17-cascade-deadlock-and-worm-trigger-carveout.md`, Key Insight #1):
   "The PG FK enforcement engine fires user triggers in the normal path; SET NULL from a
   parent DELETE is a regular UPDATE on the child as far as triggers are concerned."
   Therefore Option B applies: the WORM trigger on `workspace_member_actions` MUST be
   rewritten with a structural-shape carve-out (NOT just a FK change).

This is PR-1 of a 4-PR drain for flag-flip blockers on `TEAM_WORKSPACE_INVITE_ENABLED`.
Both issues are the same defect class (RESTRICT FK blocks Art. 17 cascade), same file
surface (`account-delete.ts` cascade ordering + new migration), and bundling them in one PR
lets the reviewer audit the full cascade chain end-to-end.

## Research Reconciliation — Spec vs. Codebase

| Spec/Issue Claim | Codebase Reality | Plan Response |
|---|---|---|
| #4299: "only the membership-row anonymise is missing" | `anonymise_workspace_members` already exists (mig 058:383, updated in mig 063:545) and is called at account-delete.ts step 3.91 | Issue was filed before mig 058 landed. The RPC + wiring exist. Plan adds verification AC + defense-in-depth FK change. |
| #4299: "add anonymise_workspace_members using structural-shape WORM bypass" | `workspace_members` has NO WORM trigger — it is a normal table. `anonymise_workspace_members` uses `session_replication_role='replica'` (mig 063:558) to bypass the mig 063 AFTER trigger on `workspace_members` that writes to `workspace_member_actions`. | No structural-shape WORM rewrite needed for workspace_members itself. The session_replication_role usage is correct — it suppresses the AFTER audit trigger, not a BEFORE WORM trigger. |
| #4299: "Wire into account-delete.ts between step 3.90 and 3.91" | Already wired at step 3.91 (account-delete.ts:549-577). | No wiring change needed. AC verifies existing wiring is correct. |
| #4355: "does ON DELETE SET NULL fire BEFORE UPDATE triggers?" | YES — confirmed by learning `2026-05-25-art17-cascade-deadlock-and-worm-trigger-carveout.md` Key Insight #1. | Option B (structural-shape WORM rewrite) required, not Option A (FK-only). |
| #4355: "workspace_member_actions.workspace_id RESTRICT blocks Art. 17" | Post-mig-065, orphan workspaces are NOT deleted — `anonymise_organization_membership` no longer hard-deletes workspaces (mig 065 Part 3). The RESTRICT FK is latent, not currently blocking. | Plan changes FK to SET NULL as defense-in-depth per the mig 062 precedent, preventing future deadlocks if workspace deletion is ever reintroduced (janitor, data migration). |
| #4355: "sister to #4329" | #4329 is CLOSED. It was about `workspace_member_attestations.workspace_id` RESTRICT — the same defect class but on a different table. | The attestations table already has its FK handled. This plan covers the workspace_member_actions table (the remaining sister). |

## Problem Statement

### Current cascade chain (post-mig-065)

```
auth.admin.deleteUser(userId)
  → auth.users DELETE → CASCADE to public.users
    → public.users DELETE:
        organizations.owner_user_id     → SET NULL (mig 065)
        audit_byok_use.founder_id       → SET NULL (mig 065 + 066 carve-out)
        workspace_members.user_id       → RESTRICT ← rows already DELETEd by step 3.91
        workspace_member_actions.actor_  → RESTRICT ← rows already NULLed by step 3.93
        workspace_member_actions.target_ → RESTRICT ← rows already NULLed by step 3.93
        ... (conversations, messages, etc. → CASCADE)
```

### Why these RESTRICTs are still concerning

1. **workspace_members.user_id RESTRICT**: If step 3.91 fails silently (Sentry-only error,
   non-fatal catch swallowing the error), the auth-delete cascade will abort. Current code
   correctly returns `{ success: false }` on failure, but the RESTRICT FK is the last line
   of defense — it should never fire because step 3.91 should have cleaned up. Verification
   that the cascade is robust under multi-workspace membership (post-flag-flip) is the
   actionable deliverable for #4299.

2. **workspace_member_actions.workspace_id RESTRICT**: While orphan workspaces are not
   currently deleted, this RESTRICT creates a maintenance hazard. The mig 062 precedent
   (`workspace_member_removals.workspace_id ON DELETE SET NULL`) shows the pattern:
   change FK + drop NOT NULL + add structural-shape WORM trigger carve-out. Doing this
   now, while the code surface is fresh, is cheaper than discovering it blocks a future
   janitor or data migration.

## Proposed Solution

### Phase 0: Verification (no code changes)

Verify that the existing Art. 17 cascade correctly handles workspace_members.user_id
(#4299) by:
- Confirming `anonymise_workspace_members` DELETEs ALL rows where `user_id = p_user_id`
  (not just solo-backfill rows).
- Confirming step 3.90 (`anonymise_workspace_member_attestations`) NULLs
  `invitee_user_id` and `inviter_user_id` for the departing user.
- Confirming step 3.93 (`anonymise_workspace_member_actions`) NULLs `actor_user_id`
  and `target_user_id` for the departing user.
- Confirming the `account-delete.test.ts` cascade-order test covers the workspace
  anonymise steps.

### Phase 1: New migration — workspace_member_actions.workspace_id SET NULL + WORM carve-out

A single new migration (next available number after existing migrations) that:

1. **Schema preconditions** — `to_regclass` guards for `public.workspace_member_actions`
   and `public.workspaces` per the mig 065 pattern and `lint-migration-fk-preconditions`
   CI gate.

2. **DROP NOT NULL on workspace_id** — allows NULL values for orphan-workspace cleanup.

3. **Drop and re-add FK** — `ON DELETE RESTRICT` -> `ON DELETE SET NULL`.

4. **Replace the WORM trigger function** — `workspace_member_actions_no_mutate` must be
   rewritten from pure-reject to structural-shape recognition:
   - **DELETE**: unchanged (pure-reject, unless past 7-year retention — match the mig 062
     precedent if the retention purge function `purge_workspace_member_actions` already
     needs the DELETE carve-out, OR keep the existing retention-purge bypass via
     `session_replication_role='replica'` since the purge function already uses it).
   - **UPDATE shape "Art. 17 anonymise"**: recognize the NOT NULL -> NULL transition on
     PII columns (`actor_user_id`, `target_user_id`) AND `workspace_id`, while pinning
     audit lineage (`id`, `action_type`, `old_role`, `new_role`, `created_at`,
     `attestation_id`).

   **Pattern source:** mig 062 `workspace_member_removals_no_mutate` (lines 140-212) —
   the exact same structural-shape WORM trigger with per-column NOT NULL -> NULL
   recognition for PII + workspace_id transitions.

5. **COMMENT update** on the function to document the carve-out.

### Phase 2: Account-delete.ts verification + test hardening

No code changes to `account-delete.ts` itself — the cascade ordering is already correct.
Deliverables:
- Verify the cascade order test in `account-delete.test.ts` covers all workspace-related
  anonymise steps in the correct order: 3.90 (attestations) -> 3.901 (departed-user
  messages) -> 3.905 (removals) -> 3.91 (members) -> 3.92 (org membership) -> 3.93
  (actions). Update the test if any steps are missing from the assertion.

## Technical Approach

### Migration number

```bash
ls apps/web-platform/supabase/migrations/ | sort | tail -3
```

Current latest: `071_*`. The new migration should be `072_workspace_member_actions_workspace_id_set_null.sql`.

### WORM trigger rewrite — structural-shape recognition

The existing `workspace_member_actions_no_mutate` (mig 063:108-124) is pure-reject:

```sql
-- Current (pure-reject):
RAISE EXCEPTION 'workspace_member_actions is append-only (WORM); % rejected', TG_OP
  USING ERRCODE = 'P0001';
```

The replacement follows the mig 062 structural-shape pattern:

```sql
-- New (structural-shape with Art. 17 + SET NULL carve-out):
-- NOTE: the CREATE OR REPLACE FUNCTION declaration MUST include
-- SET search_path = public, pg_temp per cq-pg-security-definer-search-path-pin-pg-temp.
-- Expected column set (mig 072): id, workspace_id, actor_user_id, target_user_id,
-- action_type, old_role, new_role, attestation_id, created_at.
-- If a future migration adds columns, update this trigger.
IF TG_OP = 'DELETE' THEN
  RAISE EXCEPTION 'workspace_member_actions is append-only (WORM); DELETE rejected'
    USING ERRCODE = 'P0001';
END IF;

-- UPDATE: audit lineage must be immutable
IF NEW.id           IS DISTINCT FROM OLD.id
  OR NEW.action_type IS DISTINCT FROM OLD.action_type
  OR NEW.old_role    IS DISTINCT FROM OLD.old_role
  OR NEW.new_role    IS DISTINCT FROM OLD.new_role
  OR NEW.created_at  IS DISTINCT FROM OLD.created_at
  OR NEW.attestation_id IS DISTINCT FROM OLD.attestation_id
THEN
  RAISE EXCEPTION 'workspace_member_actions audit lineage is immutable'
    USING ERRCODE = 'P0001';
END IF;

-- workspace_id: NOT NULL -> NULL permitted (ON DELETE SET NULL cascade)
IF (OLD.workspace_id IS NULL AND NEW.workspace_id IS NOT NULL)
  OR (OLD.workspace_id IS NOT NULL AND NEW.workspace_id IS NOT NULL
      AND NEW.workspace_id IS DISTINCT FROM OLD.workspace_id)
THEN
  RAISE EXCEPTION 'workspace_member_actions.workspace_id: only NOT NULL -> NULL permitted'
    USING ERRCODE = 'P0001';
END IF;

-- PII columns: NOT NULL -> NULL permitted (Art. 17 anonymise)
IF (OLD.actor_user_id IS NULL AND NEW.actor_user_id IS NOT NULL)
  OR (OLD.actor_user_id IS NOT NULL AND NEW.actor_user_id IS NOT NULL
      AND NEW.actor_user_id IS DISTINCT FROM OLD.actor_user_id)
  OR (OLD.target_user_id IS NULL AND NEW.target_user_id IS NOT NULL)
  OR (OLD.target_user_id IS NOT NULL AND NEW.target_user_id IS NOT NULL
      AND NEW.target_user_id IS DISTINCT FROM OLD.target_user_id)
THEN
  RAISE EXCEPTION 'workspace_member_actions PII columns: only NOT NULL -> NULL permitted'
    USING ERRCODE = 'P0001';
END IF;

RETURN NEW;
```

### Interaction with existing `anonymise_workspace_member_actions` RPC

The existing RPC (mig 063:304-324) uses `SET LOCAL session_replication_role = 'replica'`
to bypass the WORM trigger entirely. After this migration, the RPC still works correctly:
- With `session_replication_role='replica'`, the trigger is skipped (ENABLE ORIGIN default).
- Without the GUC, the structural-shape trigger would also ALLOW the update (NOT NULL -> NULL
  on PII columns) — belt-and-suspenders.

The FK-cascade SET NULL path (workspace deletion) fires WITHOUT `session_replication_role`
and is handled by the structural-shape carve-out in the new trigger.

### Interaction with `purge_workspace_member_actions` retention sweep

The existing purge function (mig 063:347-368) uses `SET LOCAL session_replication_role =
'replica'` to bypass the WORM trigger for DELETEs. The new trigger's DELETE arm is still
pure-reject, so the purge function continues to work via the `session_replication_role`
bypass. No change needed to the purge function.

**Alternative considered:** Add a retention-based DELETE carve-out (per mig 062 pattern:
`IF OLD.created_at < now() - interval '7 years' THEN RETURN OLD; END IF;`). This would
make the purge function work WITHOUT the GUC bypass. Decision: keep the existing
`session_replication_role` pattern for consistency with the RPC — the purge function
already uses it. Adding the carve-out would be scope creep.

## Alternative Approaches Considered

| Approach | Rejected Because |
|---|---|
| Change `workspace_members.user_id` from RESTRICT to CASCADE | Destroys the explicit-anonymisation guard — membership rows would be silently deleted by the FK cascade instead of going through the audited `anonymise_workspace_members` path. Violates the mig 053 design intent. |
| Change `workspace_members.user_id` from RESTRICT to SET NULL | workspace_members PK is `(workspace_id, user_id)` — NULL user_id would violate the PK constraint. And membership rows should be DELETED, not NULLed, because a membership row with NULL user_id is meaningless. |
| Change `workspace_member_actions.workspace_id` to ON DELETE CASCADE | Destroys audit lineage — CASCADE would delete the entire audit row when the workspace is deleted. The audit row should survive (workspace_id NULLed) as a record-of-existence. |
| Do nothing for #4299 | Acceptable in terms of current functionality (step 3.91 handles it), but the issue is a flag-flip blocker and explicit verification + test hardening is required before the flag flips. |
| Add a retention DELETE carve-out to workspace_member_actions trigger | Scope creep — the existing `purge_workspace_member_actions` already bypasses via `session_replication_role`. Adding a second bypass path is unnecessary complexity. |

## User-Brand Impact

- **If this lands broken, the user experiences:** "Account deletion failed. Please try again." error when attempting to delete their account — the Art. 17 cascade aborts, leaving the user's data intact but unable to exercise their right to erasure.
- **If this leaks, the user's data is exposed via:** No new exposure vector — this migration NULL-sets workspace_id (not PII). The PII columns (actor_user_id, target_user_id) are already handled by the existing anonymise RPC.
- **Brand-survival threshold:** `single-user incident` — one workspace member exercising Art. 17 right-to-erasure and being blocked is a statutory incident under GDPR.

## Observability

```yaml
liveness_signal:
  what: account-delete cascade success rate (existing Sentry monitors)
  cadence: per-invocation (every account deletion)
  alert_target: Sentry web-platform project
  configured_in: apps/web-platform/server/account-delete.ts (reportSilentFallback calls)

error_reporting:
  destination: Sentry web-platform via NEXT_PUBLIC_SENTRY_DSN
  fail_loud: "anonymise_workspace_member_actions failed — aborting deletion" (account-delete.ts:661)

failure_modes:
  - mode: WORM trigger rejects a legitimate Art. 17 SET NULL cascade
    detection: Sentry error with SQLSTATE P0001 from workspace_member_actions_no_mutate
    alert_route: Sentry web-platform -> operator email
  - mode: Migration 072 fails to apply (schema-vs-ledger drift)
    detection: CI migration runner exits non-zero; Supabase migration status check
    alert_route: CI failure notification

logs:
  where: Supabase logs -> Vector -> Better Stack (existing pipeline)
  retention: 30 days (Better Stack default)

discoverability_test:
  command: >
    DATABASE_URL=$(doppler secrets get DATABASE_URL_POOLER -p soleur -c dev --plain)
    node -e "const{Client}=require('pg');const c=new Client(process.env.DATABASE_URL);
    c.connect().then(()=>c.query(\"SELECT conname, confdeltype FROM pg_constraint
    WHERE conrelid='workspace_member_actions'::regclass AND conname LIKE '%workspace_id%'\"))
    .then(r=>{console.log(r.rows);c.end()})"
  expected_output: '[{ conname: "workspace_member_actions_workspace_id_fkey", confdeltype: "n" }]'
```

## Domain Review

**Domains relevant:** Legal, Engineering

### Legal (CLO)

**Status:** reviewed (carry-forward from #4230 brainstorm + #4299/#4355 issue triage)
**Assessment:** Both issues are GDPR Art. 17 compliance defects. Path 1 (anonymise-then-delete)
is the CLO-recommended approach per the #4230 brainstorm. The workspace_member_actions.workspace_id
SET NULL change does not create new PII processing — it NULLs a workspace reference (not PII) on
an already-anonymised audit row. No Article 30 register update required (PA-20 already covers
workspace_member_actions; the SET NULL transition does not change the processing purpose, data
categories, or retention).

### Engineering (CTO)

**Status:** reviewed
**Assessment:** The migration follows established precedent (mig 062 workspace_member_removals,
mig 065/066 cascade deadlock repair). The structural-shape WORM trigger pattern is the canonical
approach. No new infrastructure, no new dependencies, no CI changes.

## Open Code-Review Overlap

- **#4355** — this plan CLOSES #4355 (the issue itself is the scope-out being resolved).
  Disposition: **fold in** (this IS the fix).
- **#4254** — `template_id NOT NULL fixture drift breaks 5 tenant-iso suites`. Different
  table (`template_authorizations`), different failure class (fixture drift, not FK deadlock).
  Disposition: **acknowledge** — unrelated; does not touch workspace_member_actions or
  account-delete.ts cascade ordering.

## Files to Edit

- `apps/web-platform/supabase/migrations/072_workspace_member_actions_workspace_id_set_null.sql` — **NEW** migration
- `apps/web-platform/test/account-delete.test.ts` — add/update cascade verification for multi-workspace membership

## Files to Create

- `apps/web-platform/supabase/migrations/072_workspace_member_actions_workspace_id_set_null.sql`
- `apps/web-platform/supabase/migrations/072_workspace_member_actions_workspace_id_set_null.down.sql`

## Acceptance Criteria

### Pre-merge (PR)

- [x] **AC1 (FK change):** `psql` query against dev confirms `workspace_member_actions.workspace_id` FK is `ON DELETE SET NULL` (confdeltype = 'n') and column is nullable.
  ```bash
  DATABASE_URL=$(doppler secrets get DATABASE_URL_POOLER -p soleur -c dev --plain) \
  node -e "..." # query pg_constraint for confdeltype
  ```
- [x] **AC2 (WORM trigger shape):** The new `workspace_member_actions_no_mutate` function body contains:
  - DELETE pure-reject (unchanged from mig 063).
  - UPDATE lineage-immutability check on `(id, action_type, old_role, new_role, created_at, attestation_id)`.
  - UPDATE workspace_id NOT NULL -> NULL carve-out (per mig 062 pattern).
  - UPDATE PII columns NOT NULL -> NULL carve-out for `actor_user_id` and `target_user_id`.
  - No `session_replication_role` check in the trigger body (per learning `2026-05-18-worm-trigger-bypass-role-check-fails-under-postgrest-routing.md`).
- [x] **AC3 (WORM sentinel):** The trigger still rejects:
  - Direct DELETE.
  - UPDATE that changes a lineage column (e.g., `action_type`).
  - UPDATE that transitions a PII column from NULL -> NOT NULL (re-identification).
  - UPDATE that changes `workspace_id` to a DIFFERENT non-NULL value.
- [x] **AC4 (anonymise RPC compat):** `anonymise_workspace_member_actions(p_user_id)` continues to work — the `session_replication_role='replica'` bypass skips the trigger entirely, and the structural-shape carve-out would also permit the transition.
- [x] **AC5 (purge RPC compat):** `purge_workspace_member_actions()` continues to work — the `session_replication_role='replica'` bypass skips the trigger for DELETEs.
- [x] **AC6 (cascade verification):** `account-delete.test.ts` cascade-order test passes and covers all workspace-related anonymise steps in correct order: 3.90 -> 3.901 -> 3.905 -> 3.91 -> 3.92 -> 3.93 (3.94 byok_delegations is also in the cascade but unrelated to this fix).
- [x] **AC7 (#4299 verification):** Grep confirms `anonymise_workspace_members` is called at step 3.91 with `WHERE user_id = p_user_id` (DELETEs all membership rows, not just solo backfill).
  ```bash
  grep -A 5 "anonymise_workspace_members" apps/web-platform/server/account-delete.ts | head -10
  sed -n '/anonymise_workspace_members/,/RETURN/p' apps/web-platform/supabase/migrations/063_workspace_member_actions.sql | head -20
  ```
- [x] **AC8 (#4299 attestation verification):** Grep confirms `anonymise_workspace_member_attestations` is called at step 3.90 and covers both `invitee_user_id` and `inviter_user_id`.
  ```bash
  grep -A 5 "anonymise_workspace_member_attestations" apps/web-platform/server/account-delete.ts | head -10
  sed -n '/anonymise_workspace_member_attestations/,/RETURN/p' apps/web-platform/supabase/migrations/058_workspace_member_attestations.sql | head -20
  ```
- [x] **AC9 (down migration):** `.down.sql` restores the original pure-reject trigger, re-adds NOT NULL constraint, and changes FK back to RESTRICT.
- [ ] **AC10 (CI green):** All CI checks pass including `lint-migration-fk-preconditions`.
- [ ] **AC11 (PR body):** PR body contains `Closes #4299` and `Closes #4355`.

### Post-merge (operator)

- [ ] **AC12 (dev verification):** After migration applies to dev, run the discoverability_test command and confirm `confdeltype: "n"` for the workspace_id FK.
  Automation: executed inline by /work Phase 4 via `doppler run` + node one-liner — not operator-driven.
- [ ] **AC13 (prd verification):** After migration applies to prd, run the same query.
  Automation: `gh workflow run tenant-integration.yml` (existing CI workflow) covers the cascade path end-to-end.

## Test Scenarios

- Given a user who is a member of 3 workspaces (solo + 2 invited), when `deleteAccount` is called, then all 3 workspace_members rows are deleted by step 3.91 and `auth.admin.deleteUser` succeeds.
- Given a workspace_member_actions row with non-NULL workspace_id, when the parent workspace is deleted (hypothetical future janitor), then workspace_id is SET NULL and the WORM trigger permits the transition.
- Given a workspace_member_actions row with non-NULL actor_user_id, when `anonymise_workspace_member_actions` is called, then actor_user_id is NULLed and the trigger (bypassed by session_replication_role) does not fire.
- Given a workspace_member_actions row, when a direct UPDATE attempts to change `action_type`, then the WORM trigger raises P0001.
- Given a workspace_member_actions row with NULL actor_user_id, when a direct UPDATE attempts to set actor_user_id to a non-NULL value, then the WORM trigger raises P0001 (re-identification guard).

## Implementation Phases

### Phase 0: Precondition verification (no code changes)

1. **Verify #4299 is already handled.** Read `anonymise_workspace_members` in mig 063:545-570.
   Confirm the function does `DELETE FROM public.workspace_members WHERE user_id = p_user_id`
   (deletes ALL membership rows for the departing user, not just specific workspace_id values).
2. **Verify #4299 attestation coverage.** Read `anonymise_workspace_member_attestations` in
   mig 058:342-364. Confirm it NULLs `invitee_user_id` and `inviter_user_id` via
   `SET invitee_user_id = NULL, inviter_user_id = NULL WHERE invitee_user_id = p_user_id OR inviter_user_id = p_user_id`.
3. **Verify cascade order in account-delete.ts.** Confirm steps 3.90 -> 3.91 -> 3.92 -> 3.93
   run in the correct order per the comment block at lines 48-97.
4. **Read mig 062 structural-shape trigger** (lines 140-212) as the pattern source for the
   new trigger.
5. **Confirm migration number.** `ls apps/web-platform/supabase/migrations/ | sort | tail -3`
   to determine the next available number.

### Phase 1: Write migration 072

1. **Schema preconditions** — `to_regclass` guards.
2. **ALTER TABLE workspace_member_actions ALTER COLUMN workspace_id DROP NOT NULL.**
3. **DROP + re-ADD FK** with `ON DELETE SET NULL`.
4. **CREATE OR REPLACE FUNCTION workspace_member_actions_no_mutate** — structural-shape
   trigger body per the Technical Approach section above.
5. **No trigger re-creation needed** — `CREATE OR REPLACE FUNCTION` updates the function
   body in-place; the existing trigger references the function by name.
6. **COMMENT ON FUNCTION** update documenting the carve-out.
7. **Write `.down.sql`** — reverse: restore NOT NULL, restore RESTRICT FK, restore pure-reject trigger.

### Phase 2: Test hardening

1. **Update `account-delete.test.ts`** cascade-order test to explicitly assert the workspace
   anonymise steps (3.90, 3.901, 3.905, 3.91, 3.92, 3.93) if not already covered.
   (Multi-workspace membership testing is omitted — it would test the mock, not Postgres.
   Real multi-workspace verification is covered by AC1 against dev and AC13 via
   tenant-integration CI.)

### Phase 3: AC verification

1. Run all AC verification commands.
2. Run `bun test apps/web-platform/test/account-delete.test.ts` to confirm tests pass.

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| WORM trigger carve-out is too permissive — allows mutations beyond Art. 17 shape | Per-column NOT NULL -> NULL recognition (mig 062 pattern) is the tightest possible carve-out. The `to_jsonb` minus-key approach (mig 066) is drift-proof but more complex; the per-column approach is sufficient here because workspace_member_actions has a stable schema (added in mig 063, no schema changes since). |
| Migration 072 number collision with another in-flight PR | Check `ls apps/web-platform/supabase/migrations/` at Phase 0 step 5. If 072 is taken, use the next available number. |
| Existing `session_replication_role='replica'` bypass in anonymise RPC creates two bypass paths | Both paths are valid and complementary: the GUC bypass is the primary (used by the RPC), the structural-shape carve-out is defense-in-depth (permits FK-cascade SET NULL without the GUC). The mig 062 precedent establishes this dual-path pattern. |
| NOT NULL -> NULL on workspace_id changes query plans | The partial index `workspace_member_actions_workspace_created_idx ON (workspace_id, created_at DESC)` continues to work — NULL workspace_id rows are simply excluded from the index. The `list_workspace_member_actions` RPC filters by `workspace_id = p_workspace_id` (non-NULL), so NULL rows are naturally excluded from queries. |
| `attestation_id RESTRICT` FK (mig 063:60) creates the same defect class on attestation deletion | OUT OF SCOPE. During Art. 17 cascade, attestations are NULLed (step 3.90 `anonymise_workspace_member_attestations` sets invitee/inviter_user_id = NULL) but NOT deleted. The `workspace_member_attestations` table rows survive with PII NULLed. The RESTRICT FK on `attestation_id` only blocks attestation-row DELETE, which never happens during Art. 17 cascade. If a future janitor deletes orphan attestations, this FK will block — but that is a separate issue. |

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. Fill it before requesting deepen-plan or `/work`.
- The structural-shape trigger uses per-column `IS DISTINCT FROM` checks rather than the `to_jsonb` minus-key approach (mig 066). This is a deliberate choice: `workspace_member_actions` has a stable column set (7 columns, no additions since mig 063). If a future migration adds a column, the trigger must be updated. The `to_jsonb` approach would be drift-proof but is overkill for a table that has been stable for months.
- Per the precedent-diff gate: mig 062 `workspace_member_removals_no_mutate` (lines 140-212) is the canonical structural-shape WORM trigger. The new trigger in mig 072 MUST match this pattern closely. Read the precedent side-by-side during implementation.
- When downgrading an FK to SET NULL on a WORM-triggered table, ALWAYS pair with the trigger carve-out in the same migration — never as a follow-up (learning from mig 065 Session Error #2).

## References

- `apps/web-platform/supabase/migrations/062_workspace_member_removals_and_remove_rpc_update.sql:140-212` — structural-shape WORM trigger precedent
- `apps/web-platform/supabase/migrations/063_workspace_member_actions.sql:108-124` — current pure-reject WORM trigger to be replaced
- `apps/web-platform/supabase/migrations/063_workspace_member_actions.sql:304-324` — existing anonymise RPC (unchanged)
- `apps/web-platform/supabase/migrations/065_art17_cascade_deadlock_repair.sql` — FK downgrade precedent (organizations + audit_byok_use)
- `apps/web-platform/supabase/migrations/066_audit_byok_use_art17_carveout.sql` — to_jsonb carve-out precedent (not used here)
- `apps/web-platform/server/account-delete.ts:549-577` — step 3.91 (anonymise_workspace_members)
- `apps/web-platform/server/account-delete.ts:640-673` — step 3.93 (anonymise_workspace_member_actions)
- `knowledge-base/project/learnings/2026-05-25-art17-cascade-deadlock-and-worm-trigger-carveout.md` — Key Insight #1 (SET NULL fires BEFORE UPDATE triggers)
- `knowledge-base/project/learnings/2026-05-18-worm-trigger-bypass-role-check-fails-under-postgrest-routing.md` — no role-check in trigger body
- `knowledge-base/project/learnings/2026-05-15-worm-trigger-blocks-pg-cron-retention-sweep.md` — retention purge bypass pattern
- #4299, #4355 — issues being closed
- #4284 — `TEAM_WORKSPACE_INVITE_ENABLED` flag-flip follow-through (gated on this PR)
- #4229 — team-workspace umbrella
