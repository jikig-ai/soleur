import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import path from "node:path";

// Migration-shape test for 062_workspace_member_removals_and_remove_rpc_update.sql
// (issue #4230, PR #4294). Offline lint — runs without a live database.
//
// Covers:
//   AC1: migration shape (table, WORM trigger, REVOKE matrix, RPC clauses,
//        down-migration parity).
//   AC2: FK-violation propagation (verified via SQL shape — INSERT lives
//        inside the same SECURITY DEFINER body as the DELETE).
//   AC5 partial: allowlist alignment covered separately in
//        dsar-allowlist-completeness.test.ts.
//
// Live AC2 / AC6 verification requires TENANT_INTEGRATION_TEST=1 against
// a workspace-tables-recovered dev Supabase (see #4325 for the drift
// blocking that path); the .skipIf-gated integration test in
// `test/server/dsar-departed-member.integration.test.ts` documents the
// behavioural contract.

const MIGRATION_PATH = path.join(
  __dirname,
  "../../supabase/migrations/062_workspace_member_removals_and_remove_rpc_update.sql",
);
const DOWN_PATH = path.join(
  __dirname,
  "../../supabase/migrations/062_workspace_member_removals_and_remove_rpc_update.down.sql",
);
const REFERENCE_058 = path.join(
  __dirname,
  "../../supabase/migrations/058_workspace_member_attestations.sql",
);

const sql = readFileSync(MIGRATION_PATH, "utf8");
const downSql = readFileSync(DOWN_PATH, "utf8");
const ref058 = readFileSync(REFERENCE_058, "utf8");
const executable = sql.replace(/--[^\n]*/g, "");
const downExecutable = downSql.replace(/--[^\n]*/g, "");

describe("migration 062_workspace_member_removals_and_remove_rpc_update", () => {
  describe("AC1: table shape", () => {
    it("CREATEs public.workspace_member_removals with PRIMARY KEY id uuid", () => {
      expect(executable).toMatch(
        /CREATE\s+TABLE\s+IF\s+NOT\s+EXISTS\s+public\.workspace_member_removals\s*\([\s\S]*?id\s+uuid\s+PRIMARY\s+KEY\s+DEFAULT\s+gen_random_uuid\(\)/i,
      );
    });

    it("workspace_id FK is NULL-able REFERENCES workspaces ON DELETE SET NULL (orphan-org cleanup carve-out, ADR-039 §Invariants.1)", () => {
      // post-DISSENT inline fix: workspace_id transitions NOT NULL → NULL
      // via implicit UPDATE when anonymise_organization_membership DELETEs
      // the workspace. RESTRICT would block that cleanup pathway.
      expect(executable).toMatch(
        /workspace_id\s+uuid\s+NULL\s+REFERENCES\s+public\.workspaces\(id\)\s+ON\s+DELETE\s+SET\s+NULL/i,
      );
    });

    it("removed_user_id is NULL-able + REFERENCES users(id) ON DELETE RESTRICT (Art. 17 NULL transition target)", () => {
      expect(executable).toMatch(
        /removed_user_id\s+uuid\s+NULL\s+REFERENCES\s+public\.users\(id\)\s+ON\s+DELETE\s+RESTRICT/i,
      );
    });

    it("removed_by_user_id is NULL-able + REFERENCES users(id) ON DELETE RESTRICT", () => {
      expect(executable).toMatch(
        /removed_by_user_id\s+uuid\s+NULL\s+REFERENCES\s+public\.users\(id\)\s+ON\s+DELETE\s+RESTRICT/i,
      );
    });

    it("removed_at is NOT NULL timestamptz DEFAULT now() — audit lineage immutable", () => {
      expect(executable).toMatch(
        /removed_at\s+timestamptz\s+NOT\s+NULL\s+DEFAULT\s+now\(\)/i,
      );
    });

    it("ENABLEs RLS on the table", () => {
      expect(executable).toMatch(
        /ALTER\s+TABLE\s+public\.workspace_member_removals\s+ENABLE\s+ROW\s+LEVEL\s+SECURITY/i,
      );
    });

    it("includes covering index (workspace_id, removed_at DESC)", () => {
      expect(executable).toMatch(
        /CREATE\s+INDEX\s+IF\s+NOT\s+EXISTS\s+workspace_member_removals_workspace_idx\s+ON\s+public\.workspace_member_removals\s*\(workspace_id,\s*removed_at\s+DESC\)/i,
      );
    });
  });

  describe("AC1: REVOKE matrix on table", () => {
    it("REVOKEs UPDATE/DELETE/INSERT from PUBLIC, anon, authenticated", () => {
      expect(executable).toMatch(
        /REVOKE\s+UPDATE\s+ON\s+TABLE\s+public\.workspace_member_removals\s+FROM\s+PUBLIC,\s*anon,\s*authenticated/i,
      );
      expect(executable).toMatch(
        /REVOKE\s+DELETE\s+ON\s+TABLE\s+public\.workspace_member_removals\s+FROM\s+PUBLIC,\s*anon,\s*authenticated/i,
      );
      expect(executable).toMatch(
        /REVOKE\s+INSERT\s+ON\s+TABLE\s+public\.workspace_member_removals\s+FROM\s+PUBLIC,\s*anon,\s*authenticated/i,
      );
    });

    it("does NOT add an owner-insert RLS policy (per cq-WORM-bypass — RPC-only writes)", () => {
      // Per learning 2026-05-21-worm-ledger-rls-owner-insert-policy-is-an-rpc-bypass.md
      expect(executable).not.toMatch(
        /CREATE\s+POLICY[\s\S]*?ON\s+public\.workspace_member_removals[\s\S]*?FOR\s+INSERT/i,
      );
    });
  });

  describe("AC1: SELECT-for-members RLS policy", () => {
    it("policy uses is_workspace_member(workspace_id, auth.uid())", () => {
      expect(executable).toMatch(
        /CREATE\s+POLICY\s+removals_select_for_members\s+ON\s+public\.workspace_member_removals\s+FOR\s+SELECT\s+TO\s+authenticated\s+USING\s+\(\s*public\.is_workspace_member\(workspace_id,\s*auth\.uid\(\)\)\s*\)/i,
      );
    });
  });

  describe("AC1: WORM trigger function — two bypass paths", () => {
    it("function pinning: SET search_path = public, pg_temp", () => {
      expect(executable).toMatch(
        /CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.workspace_member_removals_no_mutate\(\)[\s\S]*?SET\s+search_path\s*=\s*public,\s*pg_temp/i,
      );
    });

    it("DELETE bypass is row-state (removed_at < now() - interval '36 months') — NOT role-gated per learning 2026-05-15", () => {
      expect(executable).toMatch(
        /TG_OP\s*=\s*'DELETE'[\s\S]*?OLD\.removed_at\s*<\s*now\(\)\s*-\s*interval\s+'36\s+months'/i,
      );
    });

    it("DELETE bypass does NOT gate on current_user (role-gate is fragile per 2026-05-15 + 2026-05-18 learnings)", () => {
      // Extract the trigger function body and assert no current_user check.
      const fnMatch = executable.match(
        /CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.workspace_member_removals_no_mutate\(\)[\s\S]*?\$\$;/i,
      );
      expect(fnMatch).not.toBeNull();
      expect(fnMatch![0]).not.toMatch(/current_user/i);
    });

    it("UPDATE bypass uses structural-shape (id + removed_at immutable; workspace_id + PII NOT NULL → NULL only)", () => {
      // Strict-immutable lineage: id + removed_at only (workspace_id was
      // demoted to NOT NULL→NULL admissible per DISSENT-flip; ADR-039
      // §Invariants.1 carve-out).
      expect(executable).toMatch(
        /NEW\.id\s+IS\s+DISTINCT\s+FROM\s+OLD\.id[\s\S]*?NEW\.removed_at\s+IS\s+DISTINCT\s+FROM\s+OLD\.removed_at/i,
      );
      // workspace_id NULL-transition shape (orphan-org cleanup).
      expect(executable).toMatch(
        /OLD\.workspace_id\s+IS\s+NULL\s+AND\s+NEW\.workspace_id\s+IS\s+NOT\s+NULL/i,
      );
      // PII NULL-transition shape for both PII columns.
      expect(executable).toMatch(
        /OLD\.removed_user_id\s+IS\s+NULL\s+AND\s+NEW\.removed_user_id\s+IS\s+NOT\s+NULL/i,
      );
      expect(executable).toMatch(
        /OLD\.removed_by_user_id\s+IS\s+NULL\s+AND\s+NEW\.removed_by_user_id\s+IS\s+NOT\s+NULL/i,
      );
    });

    it("raises P0001 for non-anonymise UPDATE, non-retention DELETE, and workspace_id violations", () => {
      expect(executable).toMatch(
        /RAISE\s+EXCEPTION\s+'workspace_member_removals\s+is\s+append-only;\s+only\s+rows\s+past\s+36-month\s+retention\s+may\s+be\s+deleted'\s+USING\s+ERRCODE\s*=\s*'P0001'/i,
      );
      expect(executable).toMatch(
        /RAISE\s+EXCEPTION\s+'workspace_member_removals\s+is\s+append-only;\s+only\s+Art\.\s+17\s+anonymise[\s\S]*?'P0001'/i,
      );
      // workspace_id NULL→NOT NULL or value-change rejected
      expect(executable).toMatch(
        /RAISE\s+EXCEPTION\s+'workspace_member_removals\.workspace_id\s+is\s+append-only;\s+only\s+ON\s+DELETE\s+SET\s+NULL\s+transitions\s+permitted'/i,
      );
      // id + removed_at strictly immutable
      expect(executable).toMatch(
        /RAISE\s+EXCEPTION\s+'workspace_member_removals\s+audit\s+lineage\s+is\s+immutable\s+\(id,\s+removed_at\)'/i,
      );
    });

    it("BEFORE UPDATE + BEFORE DELETE triggers attached", () => {
      expect(executable).toMatch(
        /CREATE\s+TRIGGER\s+workspace_member_removals_no_update\s+BEFORE\s+UPDATE\s+ON\s+public\.workspace_member_removals\s+FOR\s+EACH\s+ROW\s+EXECUTE\s+FUNCTION\s+public\.workspace_member_removals_no_mutate\(\)/i,
      );
      expect(executable).toMatch(
        /CREATE\s+TRIGGER\s+workspace_member_removals_no_delete\s+BEFORE\s+DELETE\s+ON\s+public\.workspace_member_removals\s+FOR\s+EACH\s+ROW\s+EXECUTE\s+FUNCTION\s+public\.workspace_member_removals_no_mutate\(\)/i,
      );
    });

    it("REVOKEs trigger function execution from PUBLIC, anon, authenticated, service_role", () => {
      expect(executable).toMatch(
        /REVOKE\s+ALL\s+ON\s+FUNCTION\s+public\.workspace_member_removals_no_mutate\(\)\s+FROM\s+PUBLIC,\s*anon,\s*authenticated,\s*service_role/i,
      );
    });
  });

  describe("AC1 + AC7: anonymise_workspace_member_removals RPC", () => {
    it("is SECURITY DEFINER with pinned search_path", () => {
      expect(executable).toMatch(
        /CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.anonymise_workspace_member_removals\(p_user_id\s+uuid\)[\s\S]*?SECURITY\s+DEFINER[\s\S]*?SET\s+search_path\s*=\s*public,\s*pg_temp/i,
      );
    });

    it("NULLs both removed_user_id and removed_by_user_id when either matches p_user_id", () => {
      expect(executable).toMatch(
        /UPDATE\s+public\.workspace_member_removals\s+SET\s+removed_user_id\s*=\s*NULL,\s+removed_by_user_id\s*=\s*NULL\s+WHERE\s+removed_user_id\s*=\s*p_user_id\s+OR\s+removed_by_user_id\s*=\s*p_user_id/i,
      );
    });

    it("REVOKEs from authenticated; GRANTs only to service_role (callable only from account-delete.ts cascade)", () => {
      expect(executable).toMatch(
        /REVOKE\s+ALL\s+ON\s+FUNCTION\s+public\.anonymise_workspace_member_removals\(uuid\)\s+FROM\s+PUBLIC,\s*anon,\s*authenticated/i,
      );
      expect(executable).toMatch(
        /GRANT\s+EXECUTE\s+ON\s+FUNCTION\s+public\.anonymise_workspace_member_removals\(uuid\)\s+TO\s+service_role/i,
      );
    });
  });

  describe("AC1 + AC2 + Kieran P1-4: remove_workspace_member CREATE OR REPLACE preserves clauses", () => {
    const fnMatch = executable.match(
      /CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.remove_workspace_member\(\s*p_workspace_id\s+uuid,\s*p_user_id\s+uuid\s*\)[\s\S]*?\$\$;/i,
    );

    it("function definition exists with the 2-arg signature", () => {
      expect(fnMatch).not.toBeNull();
    });

    it("preserves SECURITY DEFINER", () => {
      expect(fnMatch![0]).toMatch(/SECURITY\s+DEFINER/i);
    });

    it("preserves SET search_path = public, pg_temp", () => {
      expect(fnMatch![0]).toMatch(/SET\s+search_path\s*=\s*public,\s*pg_temp/i);
    });

    it("preserves all 4 AC-FLOW4 guards: auth.uid() NULL check, owner check, self-remove check, owner-target check", () => {
      expect(fnMatch![0]).toMatch(/v_caller_user_id\s+IS\s+NULL/i);
      expect(fnMatch![0]).toMatch(/v_is_owner/i);
      expect(fnMatch![0]).toMatch(
        /v_caller_user_id\s*=\s*p_user_id[\s\S]*?owner\s+cannot\s+remove\s+themselves/i,
      );
      expect(fnMatch![0]).toMatch(
        /v_target_role\s*=\s*'owner'[\s\S]*?cannot\s+remove\s+another\s+owner/i,
      );
      expect(fnMatch![0]).toMatch(/RETURN\s+0/i); // idempotent not-a-member
    });

    it("AC2: INSERT into workspace_member_removals lives INSIDE the same SECURITY DEFINER body (atomic with DELETE)", () => {
      expect(fnMatch![0]).toMatch(
        /INSERT\s+INTO\s+public\.workspace_member_removals\s*\(\s*workspace_id,\s*removed_user_id,\s*removed_by_user_id\s*\)\s*VALUES\s*\(\s*p_workspace_id,\s*p_user_id,\s*v_caller_user_id\s*\)/i,
      );
    });

    it("AC2: INSERT precedes DELETE (so FK violation rolls back DELETE)", () => {
      const insertIdx = fnMatch![0].search(/INSERT\s+INTO\s+public\.workspace_member_removals/i);
      const deleteIdx = fnMatch![0].search(/DELETE\s+FROM\s+public\.workspace_members/i);
      expect(insertIdx).toBeGreaterThan(-1);
      expect(deleteIdx).toBeGreaterThan(-1);
      expect(insertIdx).toBeLessThan(deleteIdx);
    });

    it("preserves REVOKE matrix + GRANT EXECUTE TO authenticated", () => {
      expect(executable).toMatch(
        /REVOKE\s+ALL\s+ON\s+FUNCTION\s+public\.remove_workspace_member\(uuid,\s*uuid\)\s+FROM\s+PUBLIC,\s*anon,\s*authenticated/i,
      );
      expect(executable).toMatch(
        /GRANT\s+EXECUTE\s+ON\s+FUNCTION\s+public\.remove_workspace_member\(uuid,\s*uuid\)\s+TO\s+authenticated/i,
      );
    });
  });

  describe("AC1: pg_cron retention sweep", () => {
    it("schedules workspace-member-removals-retention-sweep daily", () => {
      expect(executable).toMatch(
        /cron\.schedule\(\s*'workspace-member-removals-retention-sweep',\s*'0\s+4\s+\*\s+\*\s+\*'/i,
      );
    });

    it("sweep body DELETEs rows with removed_at < now() - interval '36 months'", () => {
      expect(executable).toMatch(
        /DELETE\s+FROM\s+public\.workspace_member_removals\s+WHERE\s+removed_at\s*<\s*now\(\)\s*-\s*interval\s+'36\s+months'/i,
      );
    });

    it("tolerates duplicate_object on re-run (idempotent migration apply)", () => {
      expect(executable).toMatch(/EXCEPTION\s+WHEN\s+duplicate_object\s+THEN/i);
    });

    // user-impact-reviewer F7 (PR #4294 review): the WORM trigger's DELETE
    // bypass condition (`OLD.removed_at < now() - interval '36 months'`) and
    // the cron sweep's WHERE clause (`removed_at < now() - interval '36
    // months'`) MUST match — drift between them silently keeps every retention
    // row (sweep emits DELETE; trigger rejects). Both reference the same 36-mo
    // boundary; lock it in.
    it("trigger row-state DELETE bypass and cron sweep WHERE clause use the same 36-month boundary", () => {
      // Count occurrences of the canonical `interval '36 months'` form in
      // the executable SQL — at least 2 (trigger bypass + sweep WHERE).
      const matches = executable.match(/interval\s+'36\s+months'/gi) ?? [];
      expect(matches.length).toBeGreaterThanOrEqual(2);
    });
  });

  describe("AC1: down-migration parity", () => {
    it("unschedules the cron job", () => {
      expect(downExecutable).toMatch(
        /cron\.unschedule\(\s*'workspace-member-removals-retention-sweep'/i,
      );
    });

    it("DROPs triggers, trigger function, anonymise RPC, policy, index, table", () => {
      expect(downExecutable).toMatch(
        /DROP\s+TRIGGER\s+IF\s+EXISTS\s+workspace_member_removals_no_update/i,
      );
      expect(downExecutable).toMatch(
        /DROP\s+TRIGGER\s+IF\s+EXISTS\s+workspace_member_removals_no_delete/i,
      );
      expect(downExecutable).toMatch(
        /DROP\s+FUNCTION\s+IF\s+EXISTS\s+public\.workspace_member_removals_no_mutate\(\)/i,
      );
      expect(downExecutable).toMatch(
        /DROP\s+FUNCTION\s+IF\s+EXISTS\s+public\.anonymise_workspace_member_removals\(uuid\)/i,
      );
      expect(downExecutable).toMatch(
        /DROP\s+POLICY\s+IF\s+EXISTS\s+removals_select_for_members/i,
      );
      expect(downExecutable).toMatch(
        /DROP\s+INDEX\s+IF\s+EXISTS\s+public\.workspace_member_removals_workspace_idx/i,
      );
      expect(downExecutable).toMatch(
        /DROP\s+TABLE\s+IF\s+EXISTS\s+public\.workspace_member_removals/i,
      );
    });

    it("restores remove_workspace_member to a pre-change body WITHOUT the INSERT into workspace_member_removals", () => {
      const downFnMatch = downExecutable.match(
        /CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.remove_workspace_member\(\s*p_workspace_id\s+uuid,\s*p_user_id\s+uuid\s*\)[\s\S]*?\$\$;/i,
      );
      expect(downFnMatch).not.toBeNull();
      // The pre-change body must NOT carry the new INSERT.
      expect(downFnMatch![0]).not.toMatch(
        /INSERT\s+INTO\s+public\.workspace_member_removals/i,
      );
      // But it MUST still preserve SECURITY DEFINER + search_path + AC-FLOW4 guards.
      expect(downFnMatch![0]).toMatch(/SECURITY\s+DEFINER/i);
      expect(downFnMatch![0]).toMatch(/SET\s+search_path\s*=\s*public,\s*pg_temp/i);
      expect(downFnMatch![0]).toMatch(/owner\s+cannot\s+remove\s+themselves/i);
      expect(downFnMatch![0]).toMatch(/cannot\s+remove\s+another\s+owner/i);
    });

    it("down-migration's restored body matches 058's source body verbatim (post-comment-strip, post-whitespace-collapse)", () => {
      // Parity check: 058's remove_workspace_member body == down-migration's restored body.
      // Compare normalized executable forms (comments stripped, whitespace collapsed).
      function extractRemoveFn(src: string): string {
        const stripped = src.replace(/--[^\n]*/g, "");
        const m = stripped.match(
          /CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.remove_workspace_member\(\s*p_workspace_id\s+uuid,\s*p_user_id\s+uuid\s*\)[\s\S]*?\$\$;/i,
        );
        if (!m) throw new Error("remove_workspace_member function not found");
        return m[0].replace(/\s+/g, " ").trim();
      }
      const refBody = extractRemoveFn(ref058);
      const downBody = extractRemoveFn(downSql);
      expect(downBody).toBe(refBody);
    });
  });
});
