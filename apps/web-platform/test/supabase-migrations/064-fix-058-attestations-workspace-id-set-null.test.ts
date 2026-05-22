import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import path from "node:path";

// Migration-shape test for 064_fix_058_attestations_workspace_id_set_null.sql
// (issue #4329). Offline lint — runs without a live database.
//
// Mirrors the 062-workspace-member-removals.test.ts pattern. 064 applies
// the sister-table carve-out to 058's workspace_member_attestations:
// workspace_id FK demoted RESTRICT → SET NULL + WORM trigger admits the
// implicit NOT NULL → NULL transition from the ON DELETE SET NULL cascade
// when anonymise_organization_membership DELETEs the workspace in
// account-delete.ts step 3.92.

const MIGRATION_PATH = path.join(
  __dirname,
  "../../supabase/migrations/064_fix_058_attestations_workspace_id_set_null.sql",
);
const DOWN_PATH = path.join(
  __dirname,
  "../../supabase/migrations/064_fix_058_attestations_workspace_id_set_null.down.sql",
);
const REFERENCE_058 = path.join(
  __dirname,
  "../../supabase/migrations/058_workspace_member_attestations.sql",
);
const REFERENCE_062 = path.join(
  __dirname,
  "../../supabase/migrations/062_workspace_member_removals_and_remove_rpc_update.sql",
);

const sql = readFileSync(MIGRATION_PATH, "utf8");
const downSql = readFileSync(DOWN_PATH, "utf8");
const ref058 = readFileSync(REFERENCE_058, "utf8");
const ref062 = readFileSync(REFERENCE_062, "utf8");
const executable = sql.replace(/--[^\n]*/g, "");
const downExecutable = downSql.replace(/--[^\n]*/g, "");

describe("migration 064_fix_058_attestations_workspace_id_set_null", () => {
  describe("AC2 + AC2.5: workspace_id FK demotion + DROP NOT NULL in a single ALTER TABLE statement", () => {
    it("FK is dropped + re-added as ON DELETE SET NULL + workspace_id DROP NOT NULL in one multi-clause ALTER (atomic)", () => {
      // AC2.5 deepen-added: prevents window where new SET NULL FK could
      // fire on a still-NOT-NULL column. Single regex spans all three
      // clauses terminated by a single `;`.
      expect(executable).toMatch(
        /ALTER\s+TABLE\s+public\.workspace_member_attestations[\s\S]{0,1500}?DROP\s+CONSTRAINT\s+IF\s+EXISTS\s+workspace_member_attestations_workspace_id_fkey[\s\S]{0,200}?ADD\s+CONSTRAINT\s+workspace_member_attestations_workspace_id_fkey\s+FOREIGN\s+KEY\s*\(workspace_id\)\s+REFERENCES\s+public\.workspaces\(id\)\s+ON\s+DELETE\s+SET\s+NULL[\s\S]{0,300}?ALTER\s+COLUMN\s+workspace_id\s+DROP\s+NOT\s+NULL\s*;/i,
      );
    });

    it("DOES NOT split the FK swap and NULL drop across multiple ALTER TABLE statements (no separate `ALTER TABLE ... ALTER COLUMN workspace_id DROP NOT NULL` between two `;`-terminated statements)", () => {
      // Reject the anti-shape: two separate ALTER TABLE statements where
      // the FK swap is in statement 1 and the DROP NOT NULL is in
      // statement 2. The cheapest detection — count standalone
      // `ALTER TABLE public.workspace_member_attestations` statement starts
      // that contain ONLY `DROP NOT NULL` (and no DROP CONSTRAINT).
      const standaloneNullDrop =
        /ALTER\s+TABLE\s+public\.workspace_member_attestations\s+ALTER\s+COLUMN\s+workspace_id\s+DROP\s+NOT\s+NULL\s*;/i;
      const merged =
        /ALTER\s+TABLE\s+public\.workspace_member_attestations[\s\S]*?DROP\s+CONSTRAINT[\s\S]*?ALTER\s+COLUMN\s+workspace_id\s+DROP\s+NOT\s+NULL\s*;/i;
      // If a merged form is present, the standalone form should NOT also
      // appear separately — otherwise the migration is double-altering.
      if (executable.match(merged)) {
        // Remove the merged segment; the remaining body must not have a
        // standalone NULL-drop statement.
        const withoutMerged = executable.replace(merged, "");
        expect(withoutMerged).not.toMatch(standaloneNullDrop);
      }
    });
  });

  describe("AC3: workspace_id is NULL-able post-ALTER", () => {
    it("ALTER COLUMN workspace_id DROP NOT NULL appears", () => {
      expect(executable).toMatch(
        /ALTER\s+COLUMN\s+workspace_id\s+DROP\s+NOT\s+NULL/i,
      );
    });
  });

  describe("AC1: trigger function rewrite — structural-shape pattern", () => {
    const fnMatch = executable.match(
      /CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.workspace_member_attestations_no_mutate\(\)[\s\S]*?\$\$;/i,
    );

    it("function is redefined with pinned search_path", () => {
      expect(fnMatch).not.toBeNull();
      expect(fnMatch![0]).toMatch(
        /SET\s+search_path\s*=\s*public,\s*pg_temp/i,
      );
    });

    it("DELETE arm preserved — always rejected (attestations has no retention sweep)", () => {
      expect(fnMatch![0]).toMatch(
        /IF\s+TG_OP\s*=\s*'DELETE'\s+THEN[\s\S]*?RAISE\s+EXCEPTION[\s\S]*?append-only[\s\S]*?USING\s+ERRCODE\s*=\s*'P0001'/i,
      );
    });

    it("AC4: function body does NOT reference current_user (per learning 2026-05-18-worm-trigger-bypass-role-check-fails-under-postgrest-routing)", () => {
      expect(fnMatch![0]).not.toMatch(/current_user/i);
    });

    it("strict-immutable lineage is (id, accepted_at) only — workspace_id REMOVED from the lineage check", () => {
      // Lineage was (id, workspace_id, accepted_at) in pre-064 058:97-99.
      // Post-064 it MUST be (id, accepted_at) — workspace_id is now
      // governed by a separate transition rule below.
      expect(fnMatch![0]).toMatch(
        /NEW\.id\s+IS\s+DISTINCT\s+FROM\s+OLD\.id[\s\S]*?NEW\.accepted_at\s+IS\s+DISTINCT\s+FROM\s+OLD\.accepted_at/i,
      );
      // Defense: the strict-lineage clause must NOT include workspace_id.
      // Extract the lineage-immutable IF block and verify workspace_id absent.
      const lineageBlock = fnMatch![0].match(
        /IF\s+NEW\.id\s+IS\s+DISTINCT\s+FROM\s+OLD\.id[\s\S]*?audit\s+lineage\s+is\s+immutable[^']*'[\s\S]*?'P0001'/i,
      );
      expect(lineageBlock).not.toBeNull();
      // The lineage block should NOT contain the substring `workspace_id` —
      // workspace_id is handled in a separate block below.
      expect(lineageBlock![0]).not.toMatch(
        /NEW\.workspace_id\s+IS\s+DISTINCT\s+FROM\s+OLD\.workspace_id/i,
      );
    });

    it("workspace_id NOT NULL → NULL admissible; NULL → NOT NULL or value-change rejected", () => {
      expect(fnMatch![0]).toMatch(
        /OLD\.workspace_id\s+IS\s+NULL\s+AND\s+NEW\.workspace_id\s+IS\s+NOT\s+NULL/i,
      );
      expect(fnMatch![0]).toMatch(
        /workspace_member_attestations\.workspace_id\s+is\s+append-only;\s+only\s+ON\s+DELETE\s+SET\s+NULL\s+transitions\s+permitted/i,
      );
    });

    it("each of 5 PII columns admits NOT NULL → NULL transition", () => {
      // inviter_user_id, invitee_user_id, attestation_text, ip_hash, user_agent.
      const piiCols = [
        "inviter_user_id",
        "invitee_user_id",
        "attestation_text",
        "ip_hash",
        "user_agent",
      ];
      for (const col of piiCols) {
        expect(fnMatch![0]).toMatch(
          new RegExp(
            `OLD\\.${col}\\s+IS\\s+NULL\\s+AND\\s+NEW\\.${col}\\s+IS\\s+NOT\\s+NULL`,
            "i",
          ),
        );
      }
    });

    it("raises P0001 for the four lineage / workspace_id / PII rejection paths", () => {
      const raises = fnMatch![0].match(/RAISE\s+EXCEPTION/gi) ?? [];
      // 1 DELETE always-reject + 1 lineage + 1 workspace_id + 1 PII = 4.
      expect(raises.length).toBeGreaterThanOrEqual(4);
    });
  });

  describe("AC1: triggers re-attached + REVOKE matrix preserved", () => {
    it("BEFORE UPDATE + BEFORE DELETE triggers re-attached", () => {
      expect(executable).toMatch(
        /CREATE\s+TRIGGER\s+workspace_member_attestations_no_update\s+BEFORE\s+UPDATE\s+ON\s+public\.workspace_member_attestations\s+FOR\s+EACH\s+ROW\s+EXECUTE\s+FUNCTION\s+public\.workspace_member_attestations_no_mutate\(\)/i,
      );
      expect(executable).toMatch(
        /CREATE\s+TRIGGER\s+workspace_member_attestations_no_delete\s+BEFORE\s+DELETE\s+ON\s+public\.workspace_member_attestations\s+FOR\s+EACH\s+ROW\s+EXECUTE\s+FUNCTION\s+public\.workspace_member_attestations_no_mutate\(\)/i,
      );
    });

    it("REVOKEs trigger function execution from PUBLIC, anon, authenticated, service_role", () => {
      expect(executable).toMatch(
        /REVOKE\s+ALL\s+ON\s+FUNCTION\s+public\.workspace_member_attestations_no_mutate\(\)\s+FROM\s+PUBLIC,\s*anon,\s*authenticated,\s*service_role/i,
      );
    });
  });

  describe("AC11: carve-out parity — 064 trigger structural-shape mirrors 062's pattern", () => {
    it("both 062 and 064 contain the workspace_id NULL-transition admit-arm pattern", () => {
      const arm = /OLD\.workspace_id\s+IS\s+NULL\s+AND\s+NEW\.workspace_id\s+IS\s+NOT\s+NULL/i;
      expect(ref062).toMatch(arm);
      expect(executable).toMatch(arm);
    });

    it("both 062 and 064 raise on workspace_id NULL → NOT NULL or value-change with similar message shape", () => {
      const rejectMsg = /workspace_id\s+is\s+append-only;\s+only\s+ON\s+DELETE\s+SET\s+NULL\s+transitions\s+permitted/i;
      expect(ref062).toMatch(rejectMsg);
      expect(executable).toMatch(rejectMsg);
    });
  });

  describe("AC10: down-migration parity", () => {
    it("includes a 0-row guard on workspace_id IS NULL (not count(*) > 0 — attestations is expected to have rows)", () => {
      // Per plan §3.1: the guard targets the specific class (rows where
      // orphan-org cleanup has nulled workspace_id) rather than table
      // non-emptiness.
      expect(downExecutable).toMatch(
        /WHERE\s+workspace_id\s+IS\s+NULL/i,
      );
      expect(downExecutable).toMatch(
        /Refusing\s+to\s+revert[\s\S]*?workspace_id\s+NULL/i,
      );
    });

    it("restores ALTER COLUMN workspace_id SET NOT NULL (only if 0-row guard passes)", () => {
      expect(downExecutable).toMatch(
        /ALTER\s+COLUMN\s+workspace_id\s+SET\s+NOT\s+NULL/i,
      );
    });

    it("restores ON DELETE RESTRICT FK shape", () => {
      expect(downExecutable).toMatch(
        /DROP\s+CONSTRAINT\s+IF\s+EXISTS\s+workspace_member_attestations_workspace_id_fkey[\s\S]*?ADD\s+CONSTRAINT\s+workspace_member_attestations_workspace_id_fkey\s+FOREIGN\s+KEY\s*\(workspace_id\)\s+REFERENCES\s+public\.workspaces\(id\)\s+ON\s+DELETE\s+RESTRICT/i,
      );
    });

    it("restores the original 058 trigger body verbatim (post-comment-strip, post-whitespace-collapse)", () => {
      // Parity: 058's workspace_member_attestations_no_mutate body MUST
      // match the down-migration's restored body. This is the test that
      // catches drift if someone edits the down body but not 058.
      function extractTriggerFn(src: string): string {
        const stripped = src.replace(/--[^\n]*/g, "");
        const m = stripped.match(
          /CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.workspace_member_attestations_no_mutate\(\)[\s\S]*?\$\$;/i,
        );
        if (!m)
          throw new Error(
            "workspace_member_attestations_no_mutate function not found",
          );
        return m[0].replace(/\s+/g, " ").trim();
      }
      const refBody = extractTriggerFn(ref058);
      const downBody = extractTriggerFn(downSql);
      expect(downBody).toBe(refBody);
    });

    it("re-attaches both BEFORE UPDATE + BEFORE DELETE triggers", () => {
      expect(downExecutable).toMatch(
        /CREATE\s+TRIGGER\s+workspace_member_attestations_no_update\s+BEFORE\s+UPDATE/i,
      );
      expect(downExecutable).toMatch(
        /CREATE\s+TRIGGER\s+workspace_member_attestations_no_delete\s+BEFORE\s+DELETE/i,
      );
    });
  });

  describe("Preflight DO-block (plan §2.1)", () => {
    it("includes a self-describing RAISE EXCEPTION when the FK constraint is absent (defense against name drift)", () => {
      // The constraint name follows Postgres-default convention. If the
      // name diverged on a target db, the migration must abort loudly.
      expect(executable).toMatch(
        /workspace_member_attestations_workspace_id_fkey[\s\S]*?(RAISE\s+EXCEPTION|RAISE\s+NOTICE)/i,
      );
    });
  });
});
