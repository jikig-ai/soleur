---
name: art17-cascade-deadlock-and-worm-trigger-carveout
description: GDPR Art-17 cascade fails when FK SET NULL fires a WORM BEFORE trigger; drift-proof row-hash carve-out via to_jsonb minus column equality
metadata:
  type: project
  category: database-issues
  date: 2026-05-25
  pr: 4357
  issue: 4356
  refs: [4249, 4231, 4343]
---

# Art-17 cascade deadlock + WORM trigger row-hash carve-out

## Problem

GDPR Art-17 cascade (`auth.users → public.users` CASCADE → child tables) was
fully broken on dev + prd post-mig-053. Symptoms in CI:

- 6+ `*tenant-isolation.test.ts` files failing `afterAll` with the opaque
  `AuthApiError: "Database error deleting user"` (HTTP 500 `unexpected_failure`).
- `dsar-export-workspace-tables.integration.test.ts` AC-GDPR-17-CALLER:
  `deleteAccount` returns `{ success: false, error: "Account deletion failed.
  Please try again." }`.
- The structured log on the dsar-export run gave the proximate cause:
  `ERROR: anonymise_organization_membership failed — aborting deletion` at
  `account-delete.ts:519`. But the underlying SQL error was hidden behind
  Supabase auth-js's wrap.

Reproducing the cascade in a transaction against dev surfaced the actual
SQL error:

```text
DELETE FROM auth.users WHERE id = '<test-user-id>';
ERROR: audit_byok_use is append-only (WORM)
```

## Root cause — two-layer deadlock

**Layer 1: organizations.owner_user_id RESTRICT (mig 053:51).** Every new
user gets a solo organization via `handle_new_user`. The owner FK was
`NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT`, so the cascade
`auth.users → public.users` would abort at the RESTRICT FK check.

`account-delete.ts` step 3.92 tried to break this with an orphan-org
hard-delete (`DELETE FROM workspaces; DELETE FROM organizations`), but
that DELETE was itself blocked by:

**Layer 2: WORM-ledger workspace_id RESTRICT FKs.** `workspace_member_actions`
(mig 063:51), `workspace_member_attestations` (mig 058:43), and mig 059's
nine-table workspace_id sweep all declared `workspace_id … ON DELETE
RESTRICT` to `workspaces.id`. Hard-deleting orphan workspaces was
impossible while these rows existed — and the WORM BEFORE-DELETE triggers
on workspace_member_actions / workspace_member_attestations forbade
deleting *them* even when service-role.

The cascade was a circular RESTRICT chain that no single migration owned.

## Solution

**Mig 065** breaks the cycle by downgrading the two user-RESTRICT FKs that
block `public.users` delete:

- `organizations.owner_user_id` RESTRICT → SET NULL + DROP NOT NULL.
- `audit_byok_use.founder_id` RESTRICT → SET NULL + DROP NOT NULL.
- `anonymise_organization_membership` simplified — orphan-delete path
  removed; reassign-ownership path keeps for live multi-tenant orgs with
  deterministic `ORDER BY created_at ASC, user_id ASC` tiebreak.

But the SET NULL cascade UPDATE on `audit_byok_use` fired the WORM
BEFORE-UPDATE trigger (mig 037), which RAISEs P0001 unconditionally —
the entire cascade aborted at step 4.

**Mig 066** carves out the Art-17 anonymization shape on the WORM
trigger:

```sql
CREATE OR REPLACE FUNCTION public.audit_byok_use_no_mutate() RETURNS trigger AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'audit_byok_use is append-only (WORM); DELETE rejected'
      USING ERRCODE = 'P0001';
  END IF;
  IF TG_OP = 'UPDATE' THEN
    IF OLD.founder_id IS NOT NULL
       AND NEW.founder_id IS NULL
       AND (to_jsonb(NEW) - 'founder_id') = (to_jsonb(OLD) - 'founder_id')
    THEN
      RETURN NEW;  -- Art-17 anonymization carve-out
    END IF;
    RAISE EXCEPTION 'audit_byok_use is append-only (WORM); UPDATE rejected'
      USING ERRCODE = 'P0001';
  END IF;
  RETURN NEW;
END;
$$;
```

Two non-obvious shape choices:

1. **FOR EACH ROW** (not STATEMENT — original mig 037 was STATEMENT). The
   trigger needs OLD/NEW access to check the transition.

2. **`(to_jsonb(NEW) - 'founder_id') = (to_jsonb(OLD) - 'founder_id')`**
   replaces the obvious per-column `IS NOT DISTINCT FROM` chain. The
   per-column shape would silently widen the carve-out the day someone
   adds a new column to `audit_byok_use` and forgets to extend the chain
   — an attacker (or buggy code) could then mutate the new column
   alongside the founder_id NULL transition. The JSONB-minus-key compare
   is drift-proof by construction: any future column flows through the
   equality automatically.

## Key insights

1. **WORM BEFORE triggers fire on FK SET NULL cascade UPDATEs.** The PG
   FK enforcement engine fires user triggers in the normal path; SET NULL
   from a parent DELETE is a regular UPDATE on the child as far as
   triggers are concerned. To allow the cascade you must EITHER (a) carve
   out the specific transition in the trigger body, OR (b) wrap the
   parent DELETE in a SECURITY DEFINER RPC that sets
   `session_replication_role = 'replica'`. Option (a) is preferred when
   the trigger is on a public table that production callers also write
   to.

2. **`to_jsonb(NEW) - 'col' = to_jsonb(OLD) - 'col'` is a drift-proof
   "all columns except col unchanged" check.** Use this instead of
   per-column `IS NOT DISTINCT FROM` chains in any trigger body that
   needs to allow a specific column transition while pinning the rest.
   JSONB equality is deep + NULL-safe.

3. **Cascade-chain deadlocks span multiple migrations.** No single
   migration "owned" the #4356 deadlock — mig 053 + mig 058 + mig 063
   + mig 059 each added RESTRICTs that, in aggregate, formed a circular
   chain. The fix landed in mig 065 (single repair migration) but the
   diagnosis required tracing FK constraints across 5+ files.

4. **Doppler + node-pg session-mode pooler bypass enables prd post-merge
   verification without dashboard eyeballs** (per
   `hr-no-dashboard-eyeball-pull-data-yourself`). Pattern:

   ```bash
   DATABASE_URL=$(doppler secrets get DATABASE_URL_POOLER -p soleur -c prd --plain) \
   NODE_PATH=/tmp/node_modules \
   node /tmp/pg-query-fk/prd-verify.js
   ```

   The pooler URL's port `:6543` is transaction mode (rejects multi-
   statement DDL); rewrite to `:5432` for session mode before applying or
   verifying. The direct DB host (`db.<ref>.supabase.co:5432`) is
   IPv6-only and typically unreachable.

5. **Silent test-helper catches hide exactly the regression class the
   helper exists to catch.** `tenant-isolation-teardown.ts` originally
   wrapped its anonymise-RPC calls in `try { ... } catch {}` "best
   effort". A real GRANT/REVOKE drift or PGRST202 signature mismatch
   would no longer surface — and `auth.admin.deleteUser` would still
   succeed post-mig-065 because SET NULL handles it. Helper became a
   tautology that masked the very thing #4356 was filed to catch. Always
   `console.warn` (or equivalent) on caught errors in test cleanup;
   continue the chain but make the failure visible.

6. **PR-quality lint `Block direct userId emissions` (#3698) only
   grandfathers existing sites.** New `log.info` / `log.warn` /
   `log.error` calls under `apps/web-platform/server/` MUST emit
   `userIdHash` (via `hashUserId(userId)` from `@/server/observability`),
   not raw `userId`. The pino formatter rename hook does not apply to
   new code.

## Session Errors

1. **CI fail on `lint-migration-fk-preconditions` (run 26372424027).**
   Mig 065 referenced `public.users`, `public.organizations`,
   `public.audit_byok_use` without `to_regclass` precondition guards.
   Recovery: merged main + added DO block. **Prevention:** when
   authoring a new migration that cross-references `public.<table>`,
   add the `to_regclass IS NULL THEN RAISE EXCEPTION` block as the
   first DO statement, by default.

2. **CI fail post-mig-065 (run 26372543966): audit_byok_use WORM
   trigger blocked the SET NULL cascade UPDATE.** Recovery: mig 066
   row-level carve-out. **Prevention:** when downgrading an FK to
   SET NULL on a WORM-triggered table, ALWAYS pair with the trigger
   carve-out in the same PR — never as a follow-up.

3. **Misleading line citations in migration comments** — `053:330` /
   `053:329` (actual: `053:51`) and ambiguous `mig 050:` (two 050_*.sql
   files exist). Caught by comment-analyzer agent at PR review.
   **Prevention:** when citing line numbers in migration comments, run
   `grep -n` and verify before writing; when citing migrations by
   prefix that collides, use the full filename (e.g.,
   `050_fix_scope_grants_trigger_bypass`).

4. **Empty `catch {}` in tenant-isolation-teardown.ts** swallowed the
   GRANT/REVOKE/signature regression class the helper exists to catch.
   Caught by silent-failure-hunter. **Prevention:** never silent-catch
   in helpers whose purpose is exposing failures.
   `console.warn({rpc, code, message})` + continue is the canonical
   shape.

5. **mig 065.down.sql DELETE would fail under WORM trigger.** Caught by
   code-reviewer. The `DELETE FROM audit_byok_use WHERE founder_id IS
   NULL` (needed before re-asserting NOT NULL) would fire the WORM
   trigger and abort. **Prevention:** down migrations that DELETE from
   a WORM-protected table must bracket the DELETE with `SET LOCAL
   session_replication_role = 'replica'; … RESET`.

6. **Non-deterministic ORDER BY in
   anonymise_organization_membership reassign** — `ORDER BY
   m.created_at ASC` without a PK tiebreak. **Prevention:** ORDER BY
   clauses that pick a single winner must include a deterministic
   secondary (PK or unique column).

7. **userId-emission lint (#3698) fired on new orphan-org observability
   `log.info` / `log.warn` calls in account-delete.ts.** Recovery:
   imported `hashUserId` and emitted `userIdHash` directly. **Prevention:**
   new log calls under `server/` must use `userIdHash` — the pino rename
   hook only covers grandfathered sites.

8. **Mig 066 row-hash regex test failed** because the actual SQL had
   outer parens around `(to_jsonb(NEW) - 'founder_id')` that my regex
   didn't tolerate. **Prevention:** when writing source-grep regex
   assertions, paste a fragment of the actual file content first, then
   escape — never write the regex from memory.

9. **Bun-installed `pg` package was not node-findable.** `bun add pg`
   installs to bun's global cache; `node -e "require('pg')"` couldn't
   resolve it. Recovery: `npm install pg` to `/tmp/node_modules` +
   `NODE_PATH=/tmp/node_modules`. **Prevention:** for one-off node
   scripts that need a package, use `npm install` (or `bun install`
   into a local `node_modules`); avoid `bun add` for node-runtime
   consumers.

## Related

- [[wg-when-tests-fail-and-are-confirmed-pre]] — tenant-integration was
  red on main for 5+ consecutive runs pre-#4356; this PR was the
  forward fix that closed the gap.
- [[hr-no-dashboard-eyeball-pull-data-yourself]] — the Doppler+pg
  verification pattern at the end of this learning is the canonical
  shape.
- [[cq-pg-security-definer-search-path-pin-pg-temp]] — mig 065 and 066
  both pin `SET search_path = public, pg_temp` on the redeclared
  functions.
- PR #4343 fixed Class A/B of the same family ("workspace_member_actions
  + grant_action_class + service-role is_workspace_member GRANT").
  PR #4357 closed Classes G/H/I/J + the deadlock.
