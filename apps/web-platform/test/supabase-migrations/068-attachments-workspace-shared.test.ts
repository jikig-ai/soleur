import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import path from "node:path";

// Migration-shape test for 068_attachments_workspace_shared.sql
// (issue #4318, feat-attachments-rls-bundle-pr2-4318). Offline lint —
// runs without a live database.
//
// Enforces AC1(a)-(g) from the plan plus the F1..F4 invariants from
// the §INVARIANTS header of the migration body itself:
//   F1 (FK-safe pseudonymisation): _anonymise_authored_messages_internal
//       UPDATEs messages.user_id to NULL (NOT a synthetic uuid; mig 046:93
//       FK to auth.users(id) ON DELETE CASCADE forbids it).
//   F2 (cascade ordering): remove_workspace_member calls the internal
//       helper BEFORE the DELETE FROM workspace_members.
//   F3 (write narrowing): the mig 045 FOR ALL policy is split into a
//       widened SELECT + three narrow INSERT/UPDATE/DELETE policies.
//   F4 (helper resolution from storage context): empirically verified
//       in Phase 0 worklog; not lintable from text — covered by Phase 6.2
//       tenant-isolation integration tests.

const MIGRATION_PATH = path.join(
  __dirname,
  "../../supabase/migrations/068_attachments_workspace_shared.sql",
);
const DOWN_PATH = path.join(
  __dirname,
  "../../supabase/migrations/068_attachments_workspace_shared.down.sql",
);
const MIG_067_PATH = path.join(
  __dirname,
  "../../supabase/migrations/067_workspace_member_revocation_lookup.sql",
);

const sql = readFileSync(MIGRATION_PATH, "utf8");
const downSql = readFileSync(DOWN_PATH, "utf8");
const mig067Sql = readFileSync(MIG_067_PATH, "utf8");

// Strip line-comments so per-line `--` prose doesn't false-match patterns.
const executable = sql.replace(/--[^\n]*/g, "");
const downExecutable = downSql.replace(/--[^\n]*/g, "");
const mig067Executable = mig067Sql.replace(/--[^\n]*/g, "");

function extractFunctionBodies(src: string): Map<string, string> {
  const re =
    /CREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\s+public\.(\w+)\s*\(([^)]*)\)[\s\S]*?\$\$([\s\S]*?)\$\$\s*;/gi;
  const out = new Map<string, string>();
  for (const m of src.matchAll(re)) {
    out.set(m[1], m[3]);
  }
  return out;
}

function extractPolicyClauses(src: string): Array<{
  name: string;
  cmd: string;
  using: string | null;
  withCheck: string | null;
}> {
  const re =
    /CREATE\s+POLICY\s+"([^"]+)"\s+ON\s+storage\.objects\s+FOR\s+(SELECT|INSERT|UPDATE|DELETE|ALL)(?:\s+USING\s*\(([\s\S]*?)\))?(?:\s+WITH\s+CHECK\s*\(([\s\S]*?)\))?\s*;/gi;
  const out: Array<{
    name: string;
    cmd: string;
    using: string | null;
    withCheck: string | null;
  }> = [];
  for (const m of src.matchAll(re)) {
    out.push({
      name: m[1],
      cmd: m[2].toUpperCase(),
      using: m[3] ?? null,
      withCheck: m[4] ?? null,
    });
  }
  return out;
}

const fnBodies = extractFunctionBodies(executable);
const policies = extractPolicyClauses(executable);

describe("migration 068_attachments_workspace_shared", () => {
  describe("AC1(g): transaction boundary", () => {
    it("body wraps in BEGIN; ... COMMIT;", () => {
      expect(sql).toMatch(/^\s*(?:--[^\n]*\n)*BEGIN\s*;/m);
      expect(sql).toMatch(/COMMIT\s*;\s*$/m);
    });

    it("down.sql also wraps in BEGIN; ... COMMIT;", () => {
      expect(downSql).toMatch(/^\s*(?:--[^\n]*\n)*BEGIN\s*;/m);
      expect(downSql).toMatch(/COMMIT\s*;\s*$/m);
    });
  });

  describe("AC1(f) + AC1(e): GRANT/REVOKE matrix", () => {
    it("is_attachment_path_workspace_member: REVOKE from all four roles, GRANT to authenticated", () => {
      expect(executable).toMatch(
        /REVOKE\s+ALL\s+ON\s+FUNCTION\s+public\.is_attachment_path_workspace_member\(uuid,\s+uuid\)\s+FROM\s+PUBLIC,\s+anon,\s+authenticated,\s+service_role/i,
      );
      expect(executable).toMatch(
        /GRANT\s+EXECUTE\s+ON\s+FUNCTION\s+public\.is_attachment_path_workspace_member\(uuid,\s+uuid\)\s+TO\s+authenticated/i,
      );
    });

    it("_anonymise_authored_messages_internal: REVOKE from all four roles, NO public GRANT", () => {
      expect(executable).toMatch(
        /REVOKE\s+ALL\s+ON\s+FUNCTION\s+public\._anonymise_authored_messages_internal\(uuid,\s+uuid\)\s+FROM\s+PUBLIC,\s+anon,\s+authenticated,\s+service_role/i,
      );
      // Negative-space: no GRANT EXECUTE for this internal helper.
      expect(executable).not.toMatch(
        /GRANT\s+EXECUTE\s+ON\s+FUNCTION\s+public\._anonymise_authored_messages_internal/i,
      );
    });

    it("anonymise_departed_user_across_workspaces: REVOKE from all four roles, GRANT to service_role", () => {
      expect(executable).toMatch(
        /REVOKE\s+ALL\s+ON\s+FUNCTION\s+public\.anonymise_departed_user_across_workspaces\(uuid\)\s+FROM\s+PUBLIC,\s+anon,\s+authenticated,\s+service_role/i,
      );
      expect(executable).toMatch(
        /GRANT\s+EXECUTE\s+ON\s+FUNCTION\s+public\.anonymise_departed_user_across_workspaces\(uuid\)\s+TO\s+service_role/i,
      );
    });

    it("remove_workspace_member: REVOKE from PUBLIC, anon, authenticated (NOT service_role) + GRANT to authenticated", () => {
      expect(executable).toMatch(
        /REVOKE\s+ALL\s+ON\s+FUNCTION\s+public\.remove_workspace_member\(uuid,\s+uuid\)\s+FROM\s+PUBLIC,\s+anon,\s+authenticated;/i,
      );
      expect(executable).not.toMatch(
        /REVOKE\s+ALL\s+ON\s+FUNCTION\s+public\.remove_workspace_member\(uuid,\s+uuid\)\s+FROM[^;]*service_role/i,
      );
      expect(executable).toMatch(
        /GRANT\s+EXECUTE\s+ON\s+FUNCTION\s+public\.remove_workspace_member\(uuid,\s+uuid\)\s+TO\s+authenticated/i,
      );
    });
  });

  describe("AC1(b) + F3: storage.objects policy split + UUID regex BEFORE ::uuid cast", () => {
    it("DROPs the mig 045 FOR ALL policy", () => {
      expect(executable).toMatch(
        /DROP\s+POLICY\s+IF\s+EXISTS\s+"Users can write own attachment objects"\s+ON\s+storage\.objects/i,
      );
    });

    it("creates exactly four new storage.objects policies (1 SELECT + 3 narrow writes)", () => {
      const names = policies.map((p) => p.name).sort();
      expect(names).toEqual(
        [
          "Users read own + co-member attachment objects",
          "Users write own attachment objects only (delete)",
          "Users write own attachment objects only (insert)",
          "Users write own attachment objects only (update)",
        ].sort(),
      );
    });

    it("SELECT policy is FOR SELECT (not FOR ALL) and includes both own-folder and co-member branches", () => {
      const sel = policies.find((p) => p.cmd === "SELECT");
      expect(sel).toBeTruthy();
      expect(sel!.name).toBe("Users read own + co-member attachment objects");
      expect(sel!.using).toMatch(
        /\(storage\.foldername\(name\)\)\[1\]\s*=\s*auth\.uid\(\)::text/i,
      );
      expect(sel!.using).toMatch(/is_attachment_path_workspace_member/i);
    });

    it("SELECT policy: UUID regex `~ '^[0-9a-f-]{36}$'` appears BEFORE the ::uuid cast (AC1-b)", () => {
      const sel = policies.find((p) => p.cmd === "SELECT");
      const using = sel?.using ?? "";
      const regexIdx = using.search(/\(storage\.foldername\(name\)\)\[2\]\s*~/i);
      const castIdx = using.search(/\(\(storage\.foldername\(name\)\)\[2\]\)::uuid/i);
      expect(regexIdx).toBeGreaterThan(-1);
      expect(castIdx).toBeGreaterThan(-1);
      expect(regexIdx).toBeLessThan(castIdx);
    });

    it("INSERT/UPDATE/DELETE policies are narrow to (foldername)[1] = auth.uid()::text (own-folder only)", () => {
      const writes = policies.filter((p) =>
        ["INSERT", "UPDATE", "DELETE"].includes(p.cmd),
      );
      expect(writes).toHaveLength(3);
      for (const w of writes) {
        const clauses = [w.using, w.withCheck].filter(Boolean).join(" || ");
        expect(clauses).toMatch(
          /\(storage\.foldername\(name\)\)\[1\]\s*=\s*auth\.uid\(\)::text/i,
        );
        // Negative-space: write policies do NOT reference the helper.
        expect(clauses).not.toMatch(/is_attachment_path_workspace_member/i);
      }
    });
  });

  describe("AC1(d): no `WITH CHECK (true)` anywhere in the migration body", () => {
    it("body has no permissive WITH CHECK (true) clause", () => {
      expect(executable).not.toMatch(/WITH\s+CHECK\s*\(\s*true\s*\)/i);
    });
  });

  describe("F1 (E-1): cascade UPDATEs messages.user_id to NULL (FK-safe, not a synthetic pseudonym)", () => {
    it("_anonymise_authored_messages_internal sets user_id = NULL (not a 'member_<hex>' literal)", () => {
      const body = fnBodies.get("_anonymise_authored_messages_internal") ?? "";
      expect(body).toBeTruthy();
      expect(body).toMatch(/SET\s+user_id\s*=\s*NULL/i);
      // Negative-space: no synthetic-uuid mint or 'member_' prefix.
      expect(body).not.toMatch(/gen_random_bytes/i);
      expect(body).not.toMatch(/uuid_generate_v5/i);
      expect(body).not.toMatch(/'member_/i);
    });

    it("predicate filters: m.user_id = p_departing_user AND m.workspace_id = p_workspace_id AND attachments exist AND conv NOT owned by departing user", () => {
      const body = fnBodies.get("_anonymise_authored_messages_internal") ?? "";
      expect(body).toMatch(/m\.user_id\s*=\s*p_departing_user/i);
      expect(body).toMatch(/m\.workspace_id\s*=\s*p_workspace_id/i);
      expect(body).toMatch(
        /EXISTS\s*\(\s*SELECT\s+1\s+FROM\s+public\.message_attachments\s+ma\s+WHERE\s+ma\.message_id\s*=\s*m\.id\s*\)/i,
      );
      expect(body).toMatch(
        /EXISTS\s*\(\s*SELECT\s+1\s+FROM\s+public\.conversations\s+c\s+WHERE\s+c\.id\s*=\s*m\.conversation_id[\s\S]*?c\.user_id\s*<>\s*p_departing_user/i,
      );
    });

    it("defense-in-depth NULL guard on parameters", () => {
      const body = fnBodies.get("_anonymise_authored_messages_internal") ?? "";
      expect(body).toMatch(
        /IF\s+p_departing_user\s+IS\s+NULL\s+OR\s+p_workspace_id\s+IS\s+NULL\s+THEN[\s\S]*?RETURN\s+0\s*;/i,
      );
    });
  });

  describe("AC5 + F2: cascade-ordering inside remove_workspace_member", () => {
    it("body calls _anonymise_authored_messages_internal", () => {
      const body = fnBodies.get("remove_workspace_member") ?? "";
      expect(body).toBeTruthy();
      expect(body).toMatch(
        /public\._anonymise_authored_messages_internal\s*\(\s*p_user_id\s*,\s*p_workspace_id\s*\)/i,
      );
    });

    it("internal-helper call appears BEFORE `DELETE FROM public.workspace_members` (F2 ordering)", () => {
      const body = fnBodies.get("remove_workspace_member") ?? "";
      const cascadeIdx = body.search(/public\._anonymise_authored_messages_internal/i);
      const deleteIdx = body.search(/DELETE\s+FROM\s+public\.workspace_members/i);
      expect(cascadeIdx).toBeGreaterThan(-1);
      expect(deleteIdx).toBeGreaterThan(-1);
      expect(cascadeIdx).toBeLessThan(deleteIdx);
    });

    it("preserves mig 067's AC-FLOW4 guards (NULL-auth, owner-check, self-removal block, owner-target block, idempotent not-a-member)", () => {
      const body = fnBodies.get("remove_workspace_member") ?? "";
      expect(body).toMatch(/auth\.uid\(\)\s+IS\s+NULL/i);
      expect(body).toMatch(/ERRCODE\s*=\s*'28000'/i);
      expect(body).toMatch(/caller is not an owner/i);
      expect(body).toMatch(/ERRCODE\s*=\s*'42501'/i);
      expect(body).toMatch(/owner cannot remove themselves/i);
      expect(body).toMatch(/cannot remove another owner/i);
      expect(body).toMatch(/ERRCODE\s*=\s*'22023'/i);
    });

    it("preserves mig 067's INSERT INTO workspace_member_removals with revocation_reason = 'removed'", () => {
      const body = fnBodies.get("remove_workspace_member") ?? "";
      expect(body).toMatch(
        /INSERT\s+INTO\s+public\.workspace_member_removals[\s\S]*?'removed'/i,
      );
    });

    it("preserves mig 067's user_session_state clear (F6)", () => {
      const body = fnBodies.get("remove_workspace_member") ?? "";
      expect(body).toMatch(
        /UPDATE\s+public\.user_session_state[\s\S]*?SET\s+current_organization_id\s*=\s*NULL/i,
      );
    });
  });

  describe("anonymise_departed_user_across_workspaces RPC", () => {
    it("declares (p_departing_user uuid) signature, RETURNS integer, SECURITY DEFINER with pinned search_path", () => {
      expect(executable).toMatch(
        /CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.anonymise_departed_user_across_workspaces\s*\(\s*p_departing_user\s+uuid\s*\)\s+RETURNS\s+integer/i,
      );
      expect(executable).toMatch(
        /FUNCTION\s+public\.anonymise_departed_user_across_workspaces[\s\S]*?SECURITY\s+DEFINER[\s\S]*?SET\s+search_path\s*=\s*public,\s*pg_temp/i,
      );
    });

    it("iterates DISTINCT m.workspace_id WHERE m.user_id = p_departing_user AND m.workspace_id IS NOT NULL", () => {
      const body = fnBodies.get("anonymise_departed_user_across_workspaces") ?? "";
      expect(body).toMatch(
        /SELECT\s+DISTINCT\s+m\.workspace_id\s+FROM\s+public\.messages\s+m[\s\S]*?m\.user_id\s*=\s*p_departing_user[\s\S]*?m\.workspace_id\s+IS\s+NOT\s+NULL/i,
      );
    });

    it("calls _anonymise_authored_messages_internal inside the loop", () => {
      const body = fnBodies.get("anonymise_departed_user_across_workspaces") ?? "";
      expect(body).toMatch(
        /public\._anonymise_authored_messages_internal\s*\(\s*p_departing_user\s*,\s*r\.workspace_id\s*\)/i,
      );
    });
  });

  describe("is_attachment_path_workspace_member helper", () => {
    it("declares (p_conversation_id uuid, p_user_id uuid) RETURNS boolean", () => {
      expect(executable).toMatch(
        /CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.is_attachment_path_workspace_member\s*\(\s*p_conversation_id\s+uuid\s*,\s*p_user_id\s+uuid\s*\)\s+RETURNS\s+boolean/i,
      );
    });

    it("is plpgsql (NOT sql) to defeat planner-inlining", () => {
      expect(executable).toMatch(
        /FUNCTION\s+public\.is_attachment_path_workspace_member[\s\S]*?LANGUAGE\s+plpgsql/i,
      );
      expect(executable).not.toMatch(
        /FUNCTION\s+public\.is_attachment_path_workspace_member[\s\S]*?LANGUAGE\s+sql/i,
      );
    });

    it("SECURITY DEFINER with search_path = public, pg_temp", () => {
      expect(executable).toMatch(
        /FUNCTION\s+public\.is_attachment_path_workspace_member[\s\S]*?SECURITY\s+DEFINER[\s\S]*?SET\s+search_path\s*=\s*public,\s*pg_temp/i,
      );
    });

    it("body resolves conversations.workspace_id and delegates to public.is_workspace_member", () => {
      const body = fnBodies.get("is_attachment_path_workspace_member") ?? "";
      expect(body).toMatch(
        /SELECT\s+workspace_id\s+INTO\s+v_workspace_id\s+FROM\s+public\.conversations\s+WHERE\s+id\s*=\s*p_conversation_id/i,
      );
      expect(body).toMatch(
        /RETURN\s+public\.is_workspace_member\s*\(\s*v_workspace_id\s*,\s*p_user_id\s*\)/i,
      );
    });

    it("returns false on NULL inputs and on missing conversation", () => {
      const body = fnBodies.get("is_attachment_path_workspace_member") ?? "";
      expect(body).toMatch(
        /IF\s+p_conversation_id\s+IS\s+NULL\s+OR\s+p_user_id\s+IS\s+NULL\s+THEN[\s\S]*?RETURN\s+false\s*;/i,
      );
      expect(body).toMatch(
        /IF\s+v_workspace_id\s+IS\s+NULL\s+THEN[\s\S]*?RETURN\s+false\s*;/i,
      );
    });
  });

  describe("AC1(c): down.sql restores mig 045 + mig 067 body verbatim", () => {
    it("DROPs the four new policies and recreates the mig 045 single FOR ALL policy", () => {
      expect(downExecutable).toMatch(
        /DROP\s+POLICY\s+IF\s+EXISTS\s+"Users read own \+ co-member attachment objects"\s+ON\s+storage\.objects/i,
      );
      expect(downExecutable).toMatch(
        /DROP\s+POLICY\s+IF\s+EXISTS\s+"Users write own attachment objects only \(insert\)"\s+ON\s+storage\.objects/i,
      );
      expect(downExecutable).toMatch(
        /CREATE\s+POLICY\s+"Users can write own attachment objects"\s+ON\s+storage\.objects\s+FOR\s+ALL/i,
      );
    });

    it("DROPs the helper + both cascade RPCs", () => {
      expect(downExecutable).toMatch(
        /DROP\s+FUNCTION\s+IF\s+EXISTS\s+public\.anonymise_departed_user_across_workspaces\(uuid\)/i,
      );
      expect(downExecutable).toMatch(
        /DROP\s+FUNCTION\s+IF\s+EXISTS\s+public\._anonymise_authored_messages_internal\(uuid,\s*uuid\)/i,
      );
      expect(downExecutable).toMatch(
        /DROP\s+FUNCTION\s+IF\s+EXISTS\s+public\.is_attachment_path_workspace_member\(uuid,\s*uuid\)/i,
      );
    });

    it("restores mig 067's remove_workspace_member body verbatim (no _anonymise_authored_messages_internal call)", () => {
      const downBodies = extractFunctionBodies(downExecutable);
      const restored = downBodies.get("remove_workspace_member") ?? "";
      const mig067Bodies = extractFunctionBodies(mig067Executable);
      const original = mig067Bodies.get("remove_workspace_member") ?? "";
      const norm = (s: string) => s.replace(/\s+/g, " ").trim();
      expect(norm(restored)).toEqual(norm(original));
      // Negative-space: the cascade-call MUST NOT appear in the down version.
      expect(restored).not.toMatch(/_anonymise_authored_messages_internal/i);
    });
  });

  describe("LAWFUL_BASIS preamble (gdpr-gate FR-NEW1)", () => {
    it("body carries a LAWFUL_BASIS comment referencing Art. 6(1)(b) and Art. 6(1)(f)", () => {
      expect(sql).toMatch(
        /LAWFUL_BASIS:[\s\S]*?Art\.\s*6\(1\)\(b\)[\s\S]*?Art\.\s*6\(1\)\(f\)/,
      );
    });

    it("body references article-30-register.md PA-2", () => {
      expect(sql).toMatch(/article-30-register\.md.*PA-2/);
    });
  });
});
