---
lane: single-domain
requires_cpo_signoff: true
brand_survival_threshold: single-user incident
---

# Plan: Fix Account-Delete Saga Failure at anonymise-action-sends (GDPR Art. 17)

## Implementation Addendum (2026-05-31, /work — migration 087)

The implementation **deviated from the plan's prescribed structural-shape
mechanism** after pulling authoritative current function bodies from the live
dev DB (FINDINGS §5.2). Three plan gaps drove the change; the operator
approved the new mechanism + scope via `AskUserQuestion` (CPO sign-off surface).

1. **Mechanism: uniform `app.worm_bypass` custom GUC, NOT structural-shape.**
   `anonymise_workspace_members` (a saga-FATAL step the plan's 5-table scope
   omitted) uses the bypass to suppress two **AFTER side-effect triggers**
   (`workspace_members_audit`, `byok_delegations_on_member_delete`) so the
   erasure DELETE creates no new audit/PII rows. Structural-shape detection
   has no "reject shape" to permit for an AFTER side-effect trigger — it
   fundamentally cannot express this case. A privilege-free `SET LOCAL
   app.worm_bypass = 'on'` GUC (checked via `current_setting('app.worm_bypass',
   true) = 'on'`) is uniform across BEFORE-reject AND AFTER-suppress triggers,
   needs no superuser (fixes the 42501), and has NO `current_user` dependency
   (so it is NOT the proven-dead pattern of learning 2026-05-18 — it is that
   learning's own recommended no-role-check bypass). This avoids the plan's
   `FOR EACH STATEMENT → FOR EACH ROW` trigger-form change entirely (the GUC
   check works at statement level).

2. **Scope expanded to the full erasure path** (operator chose "Full saga +
   DROP NOT NULL"): migration `087_worm_bypass_privilege_independence.sql`
   converts **7 anonymise RPCs** (action_sends, template_authorizations,
   workspace_member_actions, workspace_members, byok_delegation_acceptances,
   byok_delegation_withdrawals, audit_github_token_use) + **8 trigger
   functions** (6 BEFORE reject/shape + 2 AFTER side-effect). The plan's
   5-table scope would have left the saga still failing at
   `anonymise_workspace_members`.

3. **`byok_delegation_acceptances.user_id` DROP NOT NULL** — a REAL, distinct
   defect (NOT the retracted action_sends one): the column is `NOT NULL` with
   81 live rows and FK→users ON DELETE RESTRICT, yet the anonymise RPC sets it
   NULL (23502 on any real row, independent of WORM). Made nullable.

**Deferred** (operator choice, non-erasure paths): `purge_workspace_member_actions`
+ `revoke_template_authorization` still use `session_replication_role` →
tracking issue #4702. **Already fixed upstream**: the FINDINGS §1b observability
defect (PostgREST `pg_code` not captured) landed via #4695 (`observability.ts`
extracts `pg_code` as a Sentry tag) — no work needed.

**Verification**: transactional dev validation (BEGIN…assert…ROLLBACK, never
committed) proved each RPC succeeds without `session_replication_role`, WORM
still rejects ordinary UPDATE/DELETE (P0001), DROP NOT NULL lets the byok
anonymise null a real row, idempotent re-run = 0, the GUC re-arms after the RPC
(no leak), and the AFTER-trigger suppression creates 0 new audit rows on a
3-row workspace_members DELETE. The 42501 cannot reproduce on dev (dev's
`postgres` holds the `session_replication_role` grant; prod's does not — this
matches the FINDINGS and is itself the root-cause confirmation). Regression
guard: `test/supabase-migrations/087-worm-bypass-privilege-independence.test.ts`
(no-DB, default CI) + extended `action-sends-worm.test.ts` (h.2/h.3).

## Enhancement Summary
**Deepened on:** 2026-05-30
**Key corrections during deepen (load-bearing):**
1. **Retracted two of three draft "defects."** Migration 051 source shows
   `action_sends.user_id` is ALREADY `NULL`-able (line 102) and the EXECUTE grant
   to `service_role` ALREADY exists (lines 238-243), and `search_path` is ALREADY
   pinned (line 198). The draft's Defect B (NOT NULL) and Defect C (missing grant)
   were paraphrase-without-verification errors; shipping those "fixes" would have
   been harmful no-op churn on a GDPR surface. Only Defect A
   (`session_replication_role` privilege) survives — and only as a hypothesis
   pending reproduction.
2. **Surfaced prior-art migration 050** (`050_fix_scope_grants_trigger_bypass.sql`)
   — the codebase ALREADY fixed this exact bug class for scope_grants using
   **structural-shape detection**, and its header + the cited learning
   (`2026-05-18-worm-trigger-bypass-role-check-fails-under-postgrest-routing.md`)
   PROVE the GUC/`current_user` role-gate is the WRONG fix (silently always-false
   under PostgREST routing in a SECURITY DEFINER function). This **retracted the
   draft's proposed sentinel-GUC mechanism** — the fix is now structural-shape
   detection mirroring 050 (precedent-diff gate, Phase 4.4).
3. **Identified the 064 complication**: `064_action_sends_acknowledgment.sql`
   already narrowed the reject trigger to `BEFORE UPDATE OF <12 cols> FOR EACH
   STATEMENT`. Structural-shape needs `OLD`/`NEW`, so the migration must recreate
   the trigger `FOR EACH ROW` while preserving the column-list narrowing.
4. **Corrected fabricated file/symbol references:** real code site is
   account-delete.ts:259-290 (not 36-46); real test files are
   `action-sends-worm.test.ts` + `account-delete-sentry-mirror.test.ts` +
   `account-delete.cascade.integration.test.ts` (the draft's
   `account-delete-rpc.test.ts` / `account-delete-saga.test.ts` do NOT exist);
   migration 065 is TAKEN (`065_art17_cascade_deadlock_repair.sql`); next free
   number is **087** (086 is highest, verified by `ls | sort`).
5. **Enumerated the sibling-defect blast radius**: `session_replication_role` is
   used by 7 migrations (051, 053, 063, 072, 074, 084 anonymise-path + 036, 052
   non-anonymise). If Defect A reproduces, all anonymise-path siblings are broken
   identically; fix scope defaults to saga-wide structural-shape conversion.
6. Added mandatory `## User-Brand Impact` and `## Observability` sections.

All claims in the retraction table + the 050/064/051 reads were re-confirmed
against source this session (full migration text returned).

## Metadata
- **Issue**: N/A (bug report from Settings → Danger Zone)
- **Branch**: feat-one-shot-account-delete-anonymise-action-sends
- **Status**: Deepened — root-cause + fix-mechanism corrected (structural-shape,
  not GUC); fix gated on /work reproduction.
- **Regulated surface**: YES — GDPR Article 17 (Right to Erasure). gdpr-gate review on the diff is MANDATORY before ship (AGENTS hard rule `hr-gdpr-gate-on-regulated-data-surfaces`).

## Problem Statement

Account deletion fails in the Settings → Danger Zone flow. After the user types
the confirmation email and clicks "Confirm Deletion", the UI shows:

> "Account deletion failed at anonymise-action-sends. Please try again."

This is the first step of the GDPR Art. 17 account-delete saga
(`apps/web-platform/server/account-delete.ts`). Because the saga aborts on the
first failing step and is ordered child-rows-before-parent, **no account can be
deleted at all** — the erasure request cannot be honoured, which is itself a GDPR
compliance failure (erasure must be actionable).

## Root Cause

The error string is emitted by the saga step at
`apps/web-platform/server/account-delete.ts:259-290` (step 3.82): when
`service.rpc("anonymise_action_sends", { p_user_id: userId })` returns a non-null
error (line 273) OR throws (line 282), it mirrors to Sentry via
`reportSilentFallback` and returns
`"Account deletion failed at anonymise-action-sends. Please try again."`. The
saga aborts on first error and is ordered child-rows-before-parent, so this is the
**first** anonymise step in the cascade — when it fails, no account can be deleted
at all, which is itself a GDPR Art. 17 compliance failure (erasure must be
actionable).

The RPC `public.anonymise_action_sends(p_user_id uuid)` is defined in
`apps/web-platform/supabase/migrations/051_action_class_widening_and_action_sends.sql:194-249`.

### Premise Validation — draft-plan defects retracted (CRITICAL)

The first draft of this plan asserted THREE compounding defects (A: privilege, B:
NOT NULL, C: missing grant). Re-reading migration 051 verbatim **retracts two of
the three** — they were paraphrase-without-verification errors. Only Defect A
survives. This correction is load-bearing: shipping the retracted "fixes" (a
`DROP NOT NULL`, an EXECUTE grant) would have been no-op-or-harmful churn on a
GDPR surface.

| Draft claim | Verified reality (mig 051) | Disposition |
| --- | --- | --- |
| Defect B: `user_id uuid NOT NULL` → `SET user_id=NULL` violates NOT NULL | Line 102: `user_id uuid NULL REFERENCES public.users(id) ON DELETE RESTRICT` with comment "NULLABLE to admit Art-17 anonymisation." | **RETRACTED.** Column is already nullable. No `DROP NOT NULL` needed. |
| Defect C: no `GRANT EXECUTE … TO service_role` | Lines 236-243: `REVOKE ALL … FROM PUBLIC, anon, authenticated;` then `GRANT EXECUTE … TO service_role;` AND `TO authenticated;` | **RETRACTED.** Grant exists for both service_role and authenticated. |
| search_path needs pinning | Line 198: `SET search_path = public, pg_temp` already present | **RETRACTED.** Already pinned per `cq-pg-security-definer-search-path-pin-pg-temp`. |
| Proposed fix: sentinel GUC (`app.action_sends_anonymise_in_progress`) | Migration 050 header + learning 2026-05-18: the GUC/`current_user` role-gate is "silently always-false when an INVOKER trigger fires inside a SECURITY DEFINER function" — it was ABANDONED for scope_grants in favour of structural-shape detection | **RETRACTED.** Fix is structural-shape detection (mirror 050), NOT a GUC. |
| Defect A: `SET LOCAL session_replication_role='replica'` (line 224) fails on hosted Supabase | Unverifiable from source alone — **must be reproduced** (Step 1). Strongest suspect per feature brief. | **STANDS** (pending reproduction). The structural-shape fix removes the line regardless, so it is robust whether or not A is the precise SQLSTATE. |

### Defect A (the one real, unretracted suspect) — `session_replication_role`
Line 224: `SET LOCAL session_replication_role = 'replica';` (line 230 `RESET`s it).

On hosted Supabase the role that ultimately executes the `SET` may lack the
privilege. `session_replication_role` is a **superuser-only GUC** on stock
Postgres. The function is `SECURITY DEFINER` (executes as its owner); whether the
`SET LOCAL` succeeds depends on whether the owner role on hosted Supabase has the
required privilege. On managed Supabase the migration owner is typically
`postgres`, which is **not** a full superuser. If so, Postgres raises:

> `permission denied to set parameter "session_replication_role"`

…and the whole RPC aborts before the UPDATE. This manifests ONLY on hosted
Supabase, not in superuser-context local/CI runs — which is exactly why it shipped
green. **This is a hypothesis, not yet a verified fact** (see Step 1 reproduction).

**Why the fix is robust even if A's exact SQLSTATE differs:** the structural-shape
fix (below) DELETES the `session_replication_role` line entirely, replacing the
bypass with a mechanism that needs no privilege and no GUC. So the fix is correct
whether A fires as `42501 permission denied` OR as the PostgREST-routing
silent-always-false class that learning 2026-05-18 documents for the GUC variant.
Reproduction still REQUIRED (Step 1) to (a) confirm the bug is real at runtime and
(b) capture the error string for the regression assertion — do not write the
migration before reproduction yields a confirmed error.

### Prior-art: migration 050 already fixed this EXACT bug class — READ IN FULL
`050_fix_scope_grants_trigger_bypass.sql` (read in full during deepen) fixed the
scope_grants Art-17 trigger-bypass. Its mechanism is **structural-shape
detection** — the `scope_grants_no_mutate` trigger recognizes the anonymise
UPDATE by `OLD.founder_id IS NOT NULL AND NEW.founder_id IS NULL AND <all other
cols unchanged>` and `RETURN NEW`s it; `anonymise_scope_grants` is a bare
`UPDATE … SET founder_id=NULL` with NO bypass mechanism. The 050 header
(lines 5-12) explicitly states the GUC+`current_user` role-gate (043/044's
precedent — and the first draft of THIS plan's proposal) "is silently
always-false when an INVOKER trigger fires inside a SECURITY DEFINER function."
**This retracts the draft's proposed sentinel-GUC fix.** The Solution Overview
below now prescribes structural-shape detection, copied from 050.

### Sibling-RPC audit (ENUMERATED during deepen)
`grep -rl session_replication_role apps/web-platform/supabase/migrations/` returns
**9 files** (verified): 036 (release_slot, non-anonymise), 051 (action_sends),
052 (multi_source_dedup, non-anonymise), 053 (template_authorizations — confirmed:
`SET LOCAL session_replication_role='replica'` at 053:421), 063 + 072
(workspace_member_actions), 074 (byok_delegation_acceptances), 084
(byok_delegation_withdrawals), 065.down. The byok RPCs' account-delete.ts comments
(836, 861) and the 748 comment (`anonymise_workspace_members`) confirm the same
pattern is pervasive on the anonymise path. **If Defect A reproduces, ALL
anonymise-path RPCs using `session_replication_role` are broken identically on
prod** — masked today only because the saga aborts on the FIRST step
(action_sends). Fix scope DEFAULTS to saga-wide structural-shape conversion; any
sibling left unconverted needs a tracking issue + rationale
(`wg-when-deferring-a-capability-create-a`). Note 050 already converted
scope_grants, so it is NOT in scope.

### Migration 064 interaction (VERIFIED during deepen)
`064_action_sends_acknowledgment.sql` (the real 064; the draft's filename
`064_action_sends_message_class_and_worm_narrowing.sql` does NOT exist —
corrected) narrowed `action_sends_no_update` from `BEFORE UPDATE` to `BEFORE
UPDATE OF <12-column list>` (064:62-78) so the Inngest writer can UPDATE the 3
new ack columns (`acknowledged_at`/`artifact_url`/`failure_reason`) without
tripping WORM. The reject FUNCTION (`action_sends_no_mutate`) is still
pure-reject. The anonymise UPDATE touches `user_id` + `recipient_id_hash`, BOTH
in the 064 column list, so it DOES fire the reject trigger — confirming the
WORM-bypass is genuinely required and the `session_replication_role` line cannot
be deleted without replacing it (structural-shape detection is that replacement).
064's `.down.sql` and the exact 12-column list must be re-read at /work and the
column-list narrowing PRESERVED in the rewritten `FOR EACH ROW` trigger.

## Solution Overview

**The mechanism is FIXED by precedent: structural-shape detection, NOT a GUC,
NOT `session_replication_role`.** This is the load-bearing correction of the
deepen pass. Migration `050_fix_scope_grants_trigger_bypass.sql` (PR-G #3947)
already solved this EXACT bug class for `scope_grants`, and the learning it cites
(`2026-05-18-worm-trigger-bypass-role-check-fails-under-postgrest-routing.md`)
explicitly documents WHY the sentinel-GUC / `current_user` role-gate approach
that the first draft of THIS plan proposed is the wrong fix:

> The GUC + `current_user='service_role'` role check is **silently always-false
> when an INVOKER trigger fires inside a SECURITY DEFINER function** —
> `current_user` resolves to the function owner (`postgres`), not the
> PostgREST-set caller role. Migrations 043/044's GUC+role precedent silently
> always-failed; 050 replaced it with structural-shape detection.

So the codebase has TWO families:
- **Old/abandoned:** GUC + role gate (043 dsar, 044 tc_acceptances) AND
  `SET LOCAL session_replication_role='replica'` (051 action_sends, 053
  template_authorizations, 063/072 workspace_member_actions, 074/084 byok). These
  are the broken-or-fragile patterns.
- **New/canonical (post-#3984):** **structural-shape detection** in the WORM
  trigger (048/050 scope_grants). The trigger recognizes the Art-17 anonymise
  UPDATE by its *column-transition shape* (`OLD.user_id IS NOT NULL AND
  NEW.user_id IS NULL AND <every other column unchanged>`) and `RETURN NEW`s it;
  the anonymise RPC is a plain `UPDATE … SET user_id=NULL` with NO bypass call at
  all. No GUC, no `session_replication_role`, no `current_user` — works under
  PostgREST routing because it inspects row shape, not session role.

**The fix adopts the 050 structural-shape mechanism for action_sends.** This is
mandated by the precedent-diff gate (Phase 4.4) — do NOT invent the sentinel-GUC
the draft proposed; the learning proves it would silently fail the same way.

### Important complication — migration 064 narrowed the action_sends trigger
064 changed `action_sends_no_update` from `BEFORE UPDATE` (all columns) to
`BEFORE UPDATE OF <12-column list>` (064:62-78) so the Inngest acknowledgment
writer can UPDATE `acknowledged_at`/`artifact_url`/`failure_reason` (the 3 new
columns NOT in the list) without tripping the WORM reject. The reject trigger
function (`action_sends_no_mutate`, mig 051:130) is still **pure-reject** — it
unconditionally `RAISE`s; it does NOT do structural-shape detection like
scope_grants. So the anonymise UPDATE (which touches `user_id` + `recipient_id_hash`,
BOTH in the 064 column list) DOES fire the reject trigger, and the RPC bypasses
it via `session_replication_role` (051:224). **This is the bug surface.**

### Concrete fix (structural-shape, mirroring 050)
1. **New forward migration**, next free number — highest existing is **086**
   (verified by `ls | sort`), so `087_fix_action_sends_worm_bypass.sql`. Do NOT
   reuse 065 (taken: `065_art17_cascade_deadlock_repair`). Ship a paired
   `.down.sql` (project convention).
   - **Rewrite `public.action_sends_no_mutate()`** from pure-reject to
     structural-shape (mirror 050's `scope_grants_no_mutate` exactly):
     - `IF TG_OP = 'DELETE' THEN RAISE … P0001` (DELETE always rejected).
     - **Shape: Art-17 anonymise** — `OLD.user_id IS NOT NULL AND NEW.user_id IS
       NULL AND NEW.recipient_id_hash = '__anonymised__' AND <every OTHER column
       IS NOT DISTINCT FROM OLD>` → `RETURN NEW`. (action_sends anonymise sets
       BOTH user_id→NULL AND recipient_id_hash→'__anonymised__' per 051:226-227,
       so the shape check must allow the recipient_id_hash transition too — this
       DIFFERS from scope_grants which only nulls founder_id. Enumerate EVERY
       action_sends column from the 051 DDL, 102-119, when writing the
       `IS NOT DISTINCT FROM` guards, plus the 064 ack columns.)
     - Else `RAISE … 'action_sends is append-only (WORM); … rejected' P0001`.
   - **CRITICAL trigger-form decision:** 051/064's reject trigger is `FOR EACH
     STATEMENT`. Structural-shape detection needs `OLD`/`NEW` row references,
     which are **only available in `FOR EACH ROW` triggers** — `OLD`/`NEW` are
     NULL/unavailable at statement level. So the migration MUST also recreate the
     `action_sends_no_update` trigger as **`BEFORE UPDATE OF <cols> FOR EACH
     ROW`** (preserve 064's column-list narrowing so ack-column writes still
     bypass). This is a real shape change vs. 050 (scope_grants was already
     `FOR EACH ROW`). Re-confirm 064's exact column list and replicate it.
   - **Rewrite `public.anonymise_action_sends(p_user_id uuid)`**: delete the
     `SET LOCAL session_replication_role='replica'` (224) and the
     `RESET session_replication_role` (230). Keep the authorisation check, the
     `SET search_path = public, pg_temp` (198), the existing REVOKE/GRANT block
     (236-243, do NOT re-grant), and the `UPDATE … SET user_id=NULL,
     recipient_id_hash='__anonymised__' WHERE user_id=p_user_id` (225-228). The
     UPDATE now passes because it matches the trigger's anonymise shape.
2. **Sibling-RPC scope (the feature brief's "are all of them broken?" question).**
   The Step-0 grep confirms `session_replication_role` is used by: 051
   (action_sends), 053 (template_authorizations), 063/072 (workspace_member_actions),
   074 (byok_delegation_acceptances), 084 (byok_delegation_withdrawals), plus 036
   (release_slot — non-anonymise) and 052 (dedup — non-anonymise). **If
   reproduction confirms the privilege failure, ALL anonymise RPCs using
   `session_replication_role` are broken identically on prod** — the saga only
   masks them because it aborts on the FIRST step (action_sends). The fix should
   convert EACH to structural-shape in the same migration for saga-wide
   consistency, OR explicitly scope-out with a tracking issue
   (`wg-when-deferring-a-capability-create-a`) and rationale. Default: convert all
   anonymise-path RPCs. (Note `anonymise_workspace_members` per account-delete.ts:748
   comment also uses the pattern — include it in the Step-0 enumeration.)
3. **No change to `account-delete.ts` logic.** Abort-on-first-error + Sentry
   mirror at 273-290 stay intact (`cq-silent-fallback-must-mirror-to-sentry`
   compliant). Real site is 259-290 (draft's 36-46 was wrong).
4. **Idempotency preserved** — UPDATE … WHERE user_id=p_user_id no-ops on
   already-NULLed rows; the shape check still passes on a re-run that matches
   nothing.

### Why structural-shape over `session_replication_role` (and over the draft's GUC)
- `session_replication_role` is superuser-only on stock Postgres → fails on
  hosted Supabase if the function owner lacks the privilege (Defect A, the live
  suspect).
- The draft's sentinel-GUC + the older `current_user` role gate are PROVEN to
  silently always-fail under PostgREST routing inside a SECURITY DEFINER function
  (learning 2026-05-18 + migration 050 header). Do NOT reintroduce them.
- Structural-shape detection inspects the row transition, not the session role or
  any GUC → robust under PostgREST routing AND privilege-independent. It is the
  codebase's post-#3984 canonical WORM-bypass for Art-17 anonymise.
- It scopes the bypass to EXACTLY the anonymise transition shape — narrower than
  `session_replication_role='replica'` (which also disables FK triggers).

## Implementation Steps

### Step 1: Reproduce the runtime failure (REQUIRED before fixing)
- The existing `action-sends-worm.test.ts` is an **opt-in integration test**
  (`TENANT_INTEGRATION_TEST=1`, runs against a real Supabase project via
  `doppler run -p soleur -c dev`) — it is NOT pg-mem and does NOT run in default
  CI. Its test (h) calls `anonymise_action_sends` and passed pre-ship, which means
  EITHER the dev Supabase role HAS the `session_replication_role` privilege while
  prod's does not, OR the failure is environment/state-specific. **This divergence
  is the crux** — reproduction must target the environment where the bug actually
  fires (prod-equivalent role privileges), not just dev.
  - `hr-dev-prd-distinct-supabase-projects`: reproduce against DEV (or a
    throwaway), NEVER prod. Do NOT create synthetic users against prod.
- Reproduction must confirm the EXACT failing operation and error string. Run, as
  the `service_role`/`authenticator` (NOT as a superuser):
  `SELECT public.anonymise_action_sends('<synthetic-uuid>');` and capture whether
  it raises `permission denied to set parameter "session_replication_role"`
  (confirms Defect A) or succeeds (refutes A → re-open root-cause).
- If A is refuted, widen the probe: check `SET LOCAL session_replication_role`
  directly under the SECURITY DEFINER owner; inspect the actual Sentry event that
  produced the UI error (the saga mirrors via `reportSilentFallback` with
  `op: "anonymise-action-sends"`) for the real SQLSTATE/message — pull it via the
  Sentry API per `hr-no-dashboard-eyeball-pull-data-yourself`, do not eyeball.
- Capture the exact error string to assert in the regression test.
- **Do NOT write the fix migration until this step yields a confirmed error.**
  The two retracted draft defects prove the cost of fixing unverified hypotheses.

### Step 0 (at /work, BEFORE writing any migration): mandatory source reads
- Read `050_fix_scope_grants_trigger_bypass.sql` IN FULL — it is the precedent
  for this exact bug class. The fix mechanism MUST match it.
- Read the learning cited in 051's header:
  `2026-05-18-worm-trigger-bypass-role-check-fails-under-postgrest-routing.md`
  (locate via `grep -rl worm-trigger-bypass knowledge-base/`).
- `grep -rl session_replication_role apps/web-platform/supabase/migrations/` and
  list EVERY RPC using it (sibling-defect scope decision).
- Confirm the highest existing migration number (`ls .../migrations/ | sort | tail`)
  — pick the next free number. Migration 065 is TAKEN
  (`065_art17_cascade_deadlock_repair.sql`); do NOT collide.
- Confirm the action_sends reject trigger function name and shape in 051
  (`action_sends_no_mutate`, `FOR EACH STATEMENT`) and whether 064 altered it.

### Step 2: Write the forward migration (`087_fix_action_sends_worm_bypass.sql`)
- Location: `apps/web-platform/supabase/migrations/087_fix_action_sends_worm_bypass.sql`
  + paired `.down.sql` (087 = next free; 086 is highest existing, verified).
- Mechanism: **structural-shape detection, mirroring 050** (NOT a GUC, NOT
  `session_replication_role`). Do NOT include `DROP NOT NULL` (already nullable)
  or a new EXECUTE grant (already granted) — both retracted.
- Rewrite `action_sends_no_mutate()` to structural-shape (DELETE reject; anonymise
  shape `user_id NOT NULL→NULL` + `recipient_id_hash→'__anonymised__'` + all other
  cols `IS NOT DISTINCT FROM` → RETURN NEW; else RAISE P0001). Enumerate every
  action_sends column (051 DDL 102-119 + 064 ack cols) in the guards.
- Recreate `action_sends_no_update` trigger as **`FOR EACH ROW`** (was `FOR EACH
  STATEMENT`) so `OLD`/`NEW` are available; preserve 064's `BEFORE UPDATE OF
  <12-col>` narrowing so ack writes still bypass.
- `CREATE OR REPLACE anonymise_action_sends` removing the
  `session_replication_role` set/reset; keep auth check, search_path, REVOKE/GRANT.
- Convert sibling `session_replication_role` anonymise RPCs the same way (or
  scope-out with tracking issue) — see Solution Overview §2.
- Project migration conventions: numbered, idempotent (`CREATE OR REPLACE` /
  `DROP TRIGGER IF EXISTS` / `IF EXISTS`), NO outer `BEGIN/COMMIT` (Supabase
  wraps), NO `CREATE INDEX CONCURRENTLY`, header comment noting GDPR Art-17 +
  citing 050 as the precedent and learning 2026-05-18 as the rationale.

### Step 3: Verify the saga server module
- Re-read `apps/web-platform/server/account-delete.ts`: confirm no code change is
  needed; the fix is entirely in SQL. Confirm the error→Sentry mirror and
  abort-on-first-error semantics remain.
- Trace the caller chain `DangerZone.tsx` → `danger-zone/actions.ts` →
  `deleteAccount` to confirm no UI change needed (the UI already surfaces the
  structured error; once the RPC succeeds the saga proceeds to delete-user).

### Step 4: Tests (see Testing Strategy)

### Step 5: gdpr-gate on the diff (MANDATORY)
- Run the `soleur:gdpr-gate` skill on the full diff (migration + tests). This is
  a GDPR Art. 17 surface; shipping without it violates `hr-gdpr-gate-on-regulated-data-surfaces`.
- Resolve any findings inline before marking ready.

### Step 6: pre-ship migration check
- Run `soleur:preflight` (migration ordering, no version-file bumps in feature
  branch per `wg-never-bump-version-files-in-feature`).

## Testing Strategy

Existing tests to extend (VERIFIED to exist under `apps/web-platform/test/server/`):
- `action-sends-worm.test.ts` — WORM reject + Art-17 anonymise path, integration
  (`TENANT_INTEGRATION_TEST=1`). Tests (b)/(c) assert WORM reject; (h) asserts
  anonymise sets `user_id IS NULL` + `recipient_id_hash='__anonymised__'`.
- `account-delete-sentry-mirror.test.ts` — asserts the saga's Sentry mirror.
- `account-delete.cascade.integration.test.ts` — full cascade integration.
- (Draft cited `account-delete-rpc.test.ts` and `account-delete-saga.test.ts` —
  **neither exists**; corrected to the real filenames above.)

Changes (write the failing test FIRST per `cq-write-failing-tests-before`):

1. **Regression that would have caught the original failure.** The integration
   suite (h) passed pre-ship because dev's role evidently HAS the privilege the
   prod role lacks — so a same-suite test alone may not reproduce. Two layers:
   - **(a) Migration-SQL guardrail (always runnable, no DB):** assert against the
     new migration text that `anonymise_action_sends` no longer contains
     `session_replication_role`, that `action_sends_no_mutate` contains the
     structural-shape anonymise guard (`NEW.user_id IS NULL` / `recipient_id_hash`
     / `IS NOT DISTINCT FROM`), that the trigger is recreated `FOR EACH ROW`, and
     that `search_path` stays pinned. Fails fast if the broken pattern returns;
     runs in default CI. Do NOT assert "user_id made nullable" or "EXECUTE grant
     added" — both already hold (retracted defects).
   - **(b) Integration assertion (opt-in):** extend `action-sends-worm.test.ts`
     so the anonymise call is exercised under a role WITHOUT the
     `session_replication_role` privilege if the harness can simulate it (e.g.,
     `SET ROLE` to a non-privileged role before the RPC) — making (h) reproduce
     the prod failure on dev. If role-simulation is impractical, document why and
     rely on (a) + the structural-shape mechanism's privilege-independence.
2. **WORM still enforced for normal writes**: a plain `UPDATE` (of any pre-064
   identity column) / `DELETE` of an action_sends row that does NOT match the
   anonymise shape still throws `append-only` (P0001). Tests (b)/(c) already cover
   this — confirm they still pass post-fix.
3. **Anonymise succeeds & is idempotent**: after the RPC, rows have
   `user_id IS NULL` + `recipient_id_hash='__anonymised__'`; re-running no-ops.
   Test (h) covers the first call — add a second call asserting 0 additional rows.
4. **Structural-shape is tightly scoped**: a normal-caller UPDATE that nulls
   `user_id` but ALSO changes another column (or does not set
   `recipient_id_hash='__anonymised__'`) is still rejected (P0001) — the shape
   guard must not be a backdoor for arbitrary WORM mutation. Add a test that an
   UPDATE matching only PART of the anonymise shape is rejected. (This is the
   action_sends analogue of the scope_grants Shape-2 test. At /work, grep
   `knowledge-base/project/learnings/` for the WORM-ledger RLS-owner-insert /
   RPC-bypass learning and cite its verified path — do not assert a path here
   that this deepen pass could not re-confirm under the degraded shell.)
5. **Saga end-to-end** (`account-delete.cascade.integration.test.ts`): the cascade
   reaches past anonymise-action-sends and `deleteAccount` returns
   `{ success: true }`; a forced RPC failure still yields the structured per-step
   error + Sentry mirror (`account-delete-sentry-mirror.test.ts`).
6. **Sibling RPCs**: if the fix converts sibling `session_replication_role` RPCs,
   add the same WORM-still-rejects + anonymise-succeeds assertions for each
   converted table (or scope-out with rationale if left unconverted).

## Acceptance Criteria
- [ ] Root cause **reproduced** against dev/throwaway (NOT prod) with the exact
      failing operation + error string captured in the PR body. Fix migration was
      NOT written before this.
- [ ] Migration 050 read in full at /work Step 0; fix mechanism is
      structural-shape detection (matches 050), NOT a GUC, NOT
      `session_replication_role`.
- [ ] New forward migration is `087_*` (NOT 065 — taken) with paired `.down.sql`.
- [ ] `anonymise_action_sends` no longer references `session_replication_role`;
      WORM bypass is via `action_sends_no_mutate` structural-shape detection.
- [ ] `action_sends_no_update` trigger recreated `FOR EACH ROW` (so OLD/NEW are
      available) preserving 064's `BEFORE UPDATE OF <12-col>` narrowing.
- [ ] `anonymise_action_sends` retains `SET search_path = public, pg_temp` and the
      pre-existing REVOKE/GRANT block (NOT re-granted — already present).
- [ ] NO `DROP NOT NULL` on `user_id` and NO new EXECUTE grant in the migration
      (both retracted — already hold). The diff is minimal: trigger fn + RPC body.
- [ ] WORM still rejects ordinary UPDATE/DELETE (P0001), AND rejects a partial-
      shape UPDATE that nulls user_id but changes another column (no backdoor).
- [ ] Anonymise succeeds (`user_id IS NULL`, `recipient_id_hash='__anonymised__'`)
      and is idempotent on re-run.
- [ ] Sibling `session_replication_role` anonymise RPCs (053 template_auth,
      063/072 workspace_member_actions, 074/084 byok, anonymise_workspace_members):
      either converted to structural-shape in the same migration (if reproduction
      shows shared defect) OR explicitly scoped out with a tracking issue +
      rationale.
- [ ] Cascade reaches past anonymise-action-sends; `deleteAccount` returns
      `{ success: true }`; per-step error + Sentry mirror preserved on forced
      failure.
- [ ] Migration-SQL guardrail test added (asserts no `session_replication_role`,
      structural-shape guard present, trigger is `FOR EACH ROW`, search_path
      pinned) — runs in default CI.
- [ ] gdpr-gate run on the diff with findings resolved.
- [ ] preflight migration check passes.

## Risks & Rollback
- **Wrong mechanism (the draft's mistake)**: the GUC/`current_user` role gate is
  PROVEN to silently always-fail under PostgREST routing in a SECURITY DEFINER
  function (learning 2026-05-18 + mig 050 header). The fix MUST be structural-shape
  detection mirroring 050. Mitigation: precedent-diff gate (Phase 4.4), Step 0
  reads 050 first. HARD prerequisite.
- **Statement→row trigger change**: structural-shape needs `OLD`/`NEW`, available
  only in `FOR EACH ROW`. The migration changes `action_sends_no_update` from
  `FOR EACH STATEMENT` (051/064) to `FOR EACH ROW`. Risk: bulk-UPDATE performance
  (per-row vs per-statement firing) — acceptable; action_sends UPDATEs are rare
  (anonymise + ack writes only). Preserve 064's `BEFORE UPDATE OF <cols>` so ack
  writes still bypass the trigger entirely.
- **Shape-guard column enumeration**: the anonymise shape must list EVERY
  action_sends column in `IS NOT DISTINCT FROM` guards (051 DDL + 064 ack cols).
  Missing a column either over-permits (security: a backdoor mutation) or
  over-rejects (the anonymise UPDATE fails). Test #4 (partial-shape rejection) +
  test #3 (anonymise success) bracket this. Re-read 051 DDL + 064 at /work.
- **Sibling-scope decision**: if reproduction confirms Defect A, every
  `session_replication_role` RPC in the saga is broken identically; fixing only
  action_sends leaves the NEXT step (`anonymise_scope_grants` etc.) to fail on the
  retry. Default to saga-wide conversion. Track any deliberately-deferred sibling
  as a GitHub issue (`wg-when-deferring-a-capability-create-a`).
- **No new dependency**: the migration-SQL guardrail test is plain string
  assertions over the migration file — no new dev dependency, no
  `cq-before-pushing-package-json-changes` gate.
- **Rollback**: migrations are forward-only. Each fix migration ships a
  `.down.sql` (project convention — every migration has a paired down file) that
  `CREATE OR REPLACE`s the prior function bodies. Do NOT edit 051/064 in place.
- **Forward-fix only**: `anonymise_action_sends` is idempotent, so re-running the
  saga after the fix safely completes any partially-anonymised erasure.

## User-Brand Impact
**If this lands broken, the user experiences:** the Settings → Danger Zone
"Delete Account" flow fails with "Account deletion failed at
anonymise-action-sends. Please try again." on every attempt — the user CANNOT
exercise their GDPR Art. 17 right to erasure at all. This is the current state.
**If this leaks, the user's data is exposed via:** not a leak risk per se, but a
**non-deletion** risk — PII (`recipient_id_hash`, `user_id` linkage in
`action_sends`, and all downstream cascade rows) persists indefinitely against a
user who explicitly requested erasure, which is itself an Art. 17 / Art. 5(1)(e)
storage-limitation violation.
**Brand-survival threshold:** single-user incident. A single founder unable to
delete their account — on a regulated erasure surface, for an EU-single-user
product — is a brand-and-compliance incident. `requires_cpo_signoff: true`.

## Observability
```yaml
liveness_signal:
  what: anonymise-action-sends step success rate within the account-delete saga
  cadence: per account-deletion attempt (event-driven, not periodic)
  alert_target: Sentry — issue alert on reportSilentFallback events with
    feature=account-delete, op=anonymise-action-sends
  configured_in: apps/web-platform/server/account-delete.ts:274-289 (already
    emits via reportSilentFallback); Sentry alert rule in apps/web-platform/infra
error_reporting:
  destination: Sentry (via reportSilentFallback / @/server/observability)
  fail_loud: yes — the saga returns { success:false } AND mirrors to Sentry; the
    UI surfaces the structured per-step error string. No silent swallow.
failure_modes:
  - mode: session_replication_role privilege denied (Defect A)
    detection: Sentry event op=anonymise-action-sends with SQLSTATE 42501 /
      "permission denied to set parameter"
    alert_route: Sentry issue alert → account-delete saga failure
  - mode: structural-shape guard does not match the anonymise UPDATE (regression)
    detection: anonymise RPC raises P0001 "append-only (WORM)" with
      op=anonymise-action-sends
    alert_route: same Sentry alert; migration-SQL guardrail test fails in CI first
  - mode: sibling RPC fails after action_sends fixed (saga moves the break downstream)
    detection: Sentry event with a DIFFERENT op (anonymise-scope-grants, etc.)
    alert_route: same saga-failure alert, distinguished by op tag
logs:
  where: pino structured logs (createChildLogger "account-delete") + Sentry
  retention: per existing platform log retention (Sentry default)
discoverability_test:
  command: gh api -X GET "/repos/:owner/:repo/actions" >/dev/null; then query
    Sentry API for issues with tag op=anonymise-action-sends over last 7d via the
    Sentry REST API (no ssh) — verdict PASS if zero new events post-deploy
  expected_output: zero anonymise-action-sends failure events after the fix
    deploys and a real account-delete is exercised on dev
