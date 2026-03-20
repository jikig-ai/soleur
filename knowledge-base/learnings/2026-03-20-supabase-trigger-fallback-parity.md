# Learning: Supabase trigger and application fallback must use identical conditional logic

## Problem

The auth callback in `apps/web-platform/app/(auth)/callback/route.ts` had a fallback INSERT path that created a `users` row when the `handle_new_user()` database trigger failed silently or was absent. This fallback unconditionally set `tc_accepted_at: new Date().toISOString()` for every new user, regardless of whether they actually accepted the Terms & Conditions during signup.

The database trigger in `005_add_tc_accepted_at.sql` correctly checked `raw_user_meta_data->>'tc_accepted' = 'true'` before stamping the timestamp, but the TypeScript fallback did not mirror this conditional. The result was a false T&C acceptance record for any user whose row was created by the fallback path -- undermining GDPR/contract audit trail integrity.

## Solution

1. **Extracted `tcAccepted` boolean** from `user.user_metadata?.tc_accepted` in the GET handler with a dual check (`=== true || === "true"`) to handle both the JS boolean and the PostgreSQL text-extracted string form.
2. **Extended `ensureWorkspaceProvisioned` signature** to accept `tcAccepted: boolean` as a third parameter, keeping the function narrowly typed without coupling it to the full Supabase user object.
3. **Made the fallback conditional:** `tc_accepted_at: tcAccepted ? new Date().toISOString() : null` -- mirroring the trigger's `CASE WHEN ... THEN now() ELSE null END`.
4. **Changed `.insert()` to `.upsert()`** with `{ onConflict: "id", ignoreDuplicates: true }` to handle the race condition where the trigger and fallback both attempt to create the row.

## Key Insight

When a database trigger and an application-level fallback both write the same field, they must use identical conditional logic. The trigger is the primary path; the fallback is a safety net. If the safety net applies weaker conditions than the primary path, it silently corrupts data for exactly the cases the primary path was designed to guard against.

More generally: **safety-net code paths deserve the same conditional rigor as primary paths.** They are tempting to write as simplified "just make it work" stubs, but they fire precisely in degraded conditions where correctness matters most. Audit every safety-net INSERT/UPDATE for condition parity with the primary writer.

A secondary insight: safety-net INSERT paths should use upsert (or INSERT ... ON CONFLICT DO NOTHING) to handle races with trigger execution. The trigger and fallback run in different transactions, so both can observe the row as absent and attempt an INSERT. Without conflict handling, one of them fails with a unique constraint violation.

## Prevention

- **Pattern to audit:** Any application-level fallback that writes the same row/field as a database trigger. Grep for comments containing "fallback", "safety net", or "if trigger fails" near INSERT/UPDATE statements, then compare the conditional logic against the trigger definition.
- **Code review checklist item:** When reviewing a trigger + fallback pair, verify field-by-field that every conditional in the trigger has a corresponding conditional in the fallback. A diff of the two code paths (SQL vs. application language) should show structural symmetry.
- **Upsert by default:** Safety-net INSERTs that race with triggers should always use upsert/ON CONFLICT to avoid unique constraint failures.

## Related

- Issue #925: The bug report for the unconditional `tc_accepted_at` stamp
- Issue #931: `tc_accepted` metadata is client-controlled (forgeable consent) -- pre-existing issue discovered during review
- Issue #932: Open redirect via `x-forwarded-host` -- pre-existing issue discovered during review
- Issue #933: No downstream enforcement of `tc_accepted_at` -- pre-existing issue discovered during review
- Issue #934: Remediate existing incorrectly-stamped rows -- pre-existing issue discovered during review
- PR #918 / commit `78517bd`: DPD cross-reference fix (same legal compliance area)
- Migration: `apps/web-platform/supabase/migrations/005_add_tc_accepted_at.sql`
- Original T&C acceptance mechanism: Issue #889

## Tags
category: logic-errors
module: web-platform/auth
problem_type: trigger-fallback-parity
severity: high
tags: [supabase, database-trigger, fallback-insert, tc-acceptance, gdpr, upsert, race-condition, conditional-parity]
