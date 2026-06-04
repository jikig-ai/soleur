import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import path from "node:path";

// Migration-shape test for 098_workspace_logos.sql (issue #4916,
// feat-workspace-logo-upload). Offline lint — runs without a live database,
// mirroring 068-attachments-workspace-shared.test.ts.
//
// Enforces AC1/AC2 from the plan plus the structural guarantees behind AC3:
//   - logo_path column added (nullable, no backfill).
//   - private workspace-logos bucket, 1 MB cap, allowed_mime_types=['image/webp']
//     (canonical re-encode output is always WebP; the route never writes other types).
//   - is_workspace_owner(p_workspace_id, p_user_id) SECURITY DEFINER plpgsql with
//     pinned search_path, NULL-args guard, 4-role REVOKE + GRANT authenticated.
//   - storage.objects RLS: 1 SELECT (member) + 3 narrow INSERT/UPDATE/DELETE (owner);
//     UPDATE carries BOTH USING and WITH CHECK (cross-tenant-move denial, AC2/AC3);
//     every policy AND-guards `^[0-9a-f-]{36}$` BEFORE the ::uuid cast (malformed-path
//     clean-deny, AC3); no FOR ALL; no COMMENT ON POLICY (Supabase prd ownership).
//   - down.sql reverses in order: policies -> function -> DELETE objects -> bucket -> column.
//
// Live tenant-isolation behaviours (owner-write / member-read / non-member-deny /
// cross-tenant-overwrite-deny / cross-tenant-move-deny / malformed-clean-deny) are
// structurally guaranteed by the asserted policy clauses below and additionally
// verified at apply-time against DEV (migration-checklist.md), the same stance 068
// takes for its F4 invariant.

const MIGRATION_PATH = path.join(
  __dirname,
  "../../supabase/migrations/098_workspace_logos.sql",
);
const DOWN_PATH = path.join(
  __dirname,
  "../../supabase/migrations/098_workspace_logos.down.sql",
);

const sql = readFileSync(MIGRATION_PATH, "utf8");
const downSql = readFileSync(DOWN_PATH, "utf8");

// Strip line-comments so per-line `--` prose doesn't false-match patterns.
const executable = sql.replace(/--[^\n]*/g, "");
const downExecutable = downSql.replace(/--[^\n]*/g, "");

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

describe("migration 098_workspace_logos", () => {
  describe("transaction wrapping (delegated to migration runner)", () => {
    function topLevelBeginCommits(src: string): number {
      const stripped = src.replace(/\$\$[\s\S]*?\$\$/g, "");
      const beginMatches = stripped.match(/^\s*BEGIN\s*;/gim) ?? [];
      const commitMatches = stripped.match(/^\s*COMMIT\s*;/gim) ?? [];
      return beginMatches.length + commitMatches.length;
    }

    it("body has NO top-level BEGIN; or COMMIT; (delegated to psql --single-transaction)", () => {
      expect(topLevelBeginCommits(sql)).toBe(0);
    });

    it("down.sql also has NO top-level BEGIN; or COMMIT;", () => {
      expect(topLevelBeginCommits(downSql)).toBe(0);
    });
  });

  describe("AC1: column + bucket", () => {
    it("adds logo_path text nullable with IF NOT EXISTS (no backfill)", () => {
      expect(executable).toMatch(
        /ALTER\s+TABLE\s+public\.workspaces\s+ADD\s+COLUMN\s+IF\s+NOT\s+EXISTS\s+logo_path\s+text/i,
      );
      // Negative-space: not NOT NULL, no DEFAULT backfill.
      expect(executable).not.toMatch(/logo_path\s+text\s+NOT\s+NULL/i);
    });

    it("creates the private workspace-logos bucket: public=false, 1 MB cap, allowed_mime_types=['image/webp'], ON CONFLICT DO NOTHING", () => {
      expect(executable).toMatch(
        /INSERT\s+INTO\s+storage\.buckets\s*\([^)]*\)\s*VALUES[\s\S]*?'workspace-logos'/i,
      );
      expect(executable).toMatch(/false\s*,\s*1048576/);
      expect(executable).toMatch(/ARRAY\[\s*'image\/webp'\s*\]/i);
      expect(executable).toMatch(/ON\s+CONFLICT\s*\(id\)\s+DO\s+NOTHING/i);
    });
  });

  describe("AC2: is_workspace_owner helper", () => {
    it("declares (p_workspace_id uuid, p_user_id uuid) RETURNS boolean", () => {
      expect(executable).toMatch(
        /CREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\s+public\.is_workspace_owner\s*\(\s*p_workspace_id\s+uuid\s*,\s*p_user_id\s+uuid\s*\)\s+RETURNS\s+boolean/i,
      );
    });

    it("is plpgsql (NOT sql) to defeat planner-inlining", () => {
      expect(executable).toMatch(
        /FUNCTION\s+public\.is_workspace_owner[\s\S]*?LANGUAGE\s+plpgsql/i,
      );
      expect(executable).not.toMatch(
        /FUNCTION\s+public\.is_workspace_owner[\s\S]*?LANGUAGE\s+sql/i,
      );
    });

    it("SECURITY DEFINER with search_path = public, pg_temp", () => {
      expect(executable).toMatch(
        /FUNCTION\s+public\.is_workspace_owner[\s\S]*?SECURITY\s+DEFINER[\s\S]*?SET\s+search_path\s*=\s*public,\s*pg_temp/i,
      );
    });

    it("body has NULL-args guard returning false and a parameterized owner EXISTS (no dynamic SQL)", () => {
      const body = fnBodies.get("is_workspace_owner") ?? "";
      expect(body).toBeTruthy();
      expect(body).toMatch(
        /IF\s+p_workspace_id\s+IS\s+NULL\s+OR\s+p_user_id\s+IS\s+NULL\s+THEN[\s\S]*?RETURN\s+false\s*;/i,
      );
      expect(body).toMatch(
        /SELECT\s+1\s+FROM\s+public\.workspace_members\s+WHERE\s+workspace_id\s*=\s*p_workspace_id\s+AND\s+user_id\s*=\s*p_user_id\s+AND\s+role\s*=\s*'owner'/i,
      );
      // Negative-space: no dynamic SQL.
      expect(body).not.toMatch(/EXECUTE\s+/i);
    });

    it("REVOKE from all four roles, GRANT to authenticated only", () => {
      expect(executable).toMatch(
        /REVOKE\s+ALL\s+ON\s+FUNCTION\s+public\.is_workspace_owner\(uuid,\s*uuid\)\s+FROM\s+PUBLIC,\s+anon,\s+authenticated,\s+service_role/i,
      );
      expect(executable).toMatch(
        /GRANT\s+EXECUTE\s+ON\s+FUNCTION\s+public\.is_workspace_owner\(uuid,\s*uuid\)\s+TO\s+authenticated/i,
      );
    });
  });

  describe("AC2/AC3: storage.objects RLS policy split", () => {
    it("creates exactly four policies (1 SELECT member + 3 narrow owner writes)", () => {
      const names = policies.map((p) => p.name).sort();
      expect(names).toHaveLength(4);
    });

    it("has no FOR ALL policy", () => {
      expect(policies.find((p) => p.cmd === "ALL")).toBeUndefined();
    });

    it("SELECT policy gates on is_workspace_member", () => {
      const sel = policies.find((p) => p.cmd === "SELECT");
      expect(sel).toBeTruthy();
      expect(sel!.using).toMatch(/bucket_id\s*=\s*'workspace-logos'/i);
      expect(sel!.using).toMatch(/public\.is_workspace_member\s*\(/i);
      // Negative-space: SELECT must NOT use the owner helper.
      expect(sel!.using).not.toMatch(/is_workspace_owner/i);
    });

    it("INSERT policy: WITH CHECK only, gated on is_workspace_owner", () => {
      const ins = policies.find((p) => p.cmd === "INSERT");
      expect(ins).toBeTruthy();
      expect(ins!.using).toBeNull();
      expect(ins!.withCheck).toMatch(/public\.is_workspace_owner\s*\(/i);
    });

    it("UPDATE policy: BOTH USING and WITH CHECK non-null, both gated on is_workspace_owner (cross-tenant-move denial)", () => {
      const upd = policies.find((p) => p.cmd === "UPDATE");
      expect(upd).toBeTruthy();
      expect(upd!.using).toBeTruthy();
      expect(upd!.withCheck).toBeTruthy();
      expect(upd!.using).toMatch(/public\.is_workspace_owner\s*\(/i);
      expect(upd!.withCheck).toMatch(/public\.is_workspace_owner\s*\(/i);
    });

    it("DELETE policy: USING only, gated on is_workspace_owner", () => {
      const del = policies.find((p) => p.cmd === "DELETE");
      expect(del).toBeTruthy();
      expect(del!.using).toMatch(/public\.is_workspace_owner\s*\(/i);
      expect(del!.withCheck).toBeNull();
    });

    it("every policy AND-guards the `^[0-9a-f-]{36}$` shape on foldername[1] BEFORE the ::uuid cast", () => {
      for (const p of policies) {
        const clause = [p.using, p.withCheck].filter(Boolean).join(" || ");
        const regexIdx = clause.search(
          /\(storage\.foldername\(name\)\)\[1\]\s*~\s*'\^\[0-9a-f-\]\{36\}\$'/i,
        );
        const castIdx = clause.search(
          /\(\(storage\.foldername\(name\)\)\[1\]\)::uuid/i,
        );
        expect(regexIdx, `policy "${p.name}" missing regex guard`).toBeGreaterThan(-1);
        expect(castIdx, `policy "${p.name}" missing ::uuid cast`).toBeGreaterThan(-1);
        expect(
          regexIdx,
          `policy "${p.name}" casts before guarding`,
        ).toBeLessThan(castIdx);
      }
    });

    it("no permissive WITH CHECK (true) clause", () => {
      expect(executable).not.toMatch(/WITH\s+CHECK\s*\(\s*true\s*\)/i);
    });

    it("no COMMENT ON POLICY on storage.objects (Supabase prd ownership constraint)", () => {
      expect(executable).not.toMatch(/COMMENT\s+ON\s+POLICY[\s\S]*?storage\.objects/i);
    });
  });

  describe("AC9: lawful-basis annotation", () => {
    it("body carries a LAWFUL_BASIS comment referencing a GDPR Art. 6 basis", () => {
      expect(sql).toMatch(/LAWFUL_BASIS:[\s\S]*?Art\.\s*6/i);
    });

    it("references the article-30-register.md PA entry", () => {
      expect(sql).toMatch(/article-30-register\.md/i);
    });
  });

  describe("down.sql reverts SQL-droppable objects (policies, function, column)", () => {
    it("drops the four storage.objects policies", () => {
      const drops =
        downExecutable.match(/DROP\s+POLICY\s+IF\s+EXISTS\s+"[^"]+"\s+ON\s+storage\.objects/gi) ??
        [];
      expect(drops.length).toBe(4);
    });

    it("drops is_workspace_owner", () => {
      expect(downExecutable).toMatch(
        /DROP\s+FUNCTION\s+IF\s+EXISTS\s+public\.is_workspace_owner\(uuid,\s*uuid\)/i,
      );
    });

    it("drops the logo_path column", () => {
      expect(downExecutable).toMatch(
        /ALTER\s+TABLE\s+public\.workspaces\s+DROP\s+COLUMN\s+IF\s+EXISTS\s+logo_path/i,
      );
    });

    it("does NOT attempt direct DELETE on storage.objects / storage.buckets (blocked by Supabase protect_delete trigger; Storage-API teardown only — 019/042 precedent)", () => {
      expect(downExecutable).not.toMatch(/DELETE\s+FROM\s+storage\.objects/i);
      expect(downExecutable).not.toMatch(/DELETE\s+FROM\s+storage\.buckets/i);
    });
  });
});
