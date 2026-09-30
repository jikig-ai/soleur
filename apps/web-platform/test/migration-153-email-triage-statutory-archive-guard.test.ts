import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import path from "node:path";

const MIGRATION_PATH = path.join(
  __dirname,
  "../supabase/migrations/153_email_triage_statutory_archive_guard.sql",
);
const DOWN_PATH = path.join(
  __dirname,
  "../supabase/migrations/153_email_triage_statutory_archive_guard.down.sql",
);
const MIGRATION_111_PATH = path.join(
  __dirname,
  "../supabase/migrations/111_email_triage_items_workspace_shared.sql",
);

const sql = readFileSync(MIGRATION_PATH, "utf-8");
const downSql = readFileSync(DOWN_PATH, "utf-8");
const mig111 = readFileSync(MIGRATION_111_PATH, "utf-8");

// Negative assertions run against the DDL with `--` comment lines stripped —
// the header comments deliberately NAME contrasted constructs (grep-over-
// script-body learning).
const code = sql
  .split("\n")
  .filter((l) => !l.trim().startsWith("--"))
  .join("\n");
const downCode = downSql
  .split("\n")
  .filter((l) => !l.trim().startsWith("--"))
  .join("\n");

function functionBody(source: string): string {
  const m = source.match(
    /CREATE OR REPLACE FUNCTION public\.set_email_triage_status[\s\S]*?\$\$;/,
  );
  if (!m) throw new Error("set_email_triage_status body not found");
  return m[0];
}

describe("mig 153: statutory archive pin on set_email_triage_status", () => {
  it("re-creates the function", () => {
    expect(sql).toContain(
      "CREATE OR REPLACE FUNCTION public.set_email_triage_status(p_id uuid, p_status text)",
    );
  });

  it("rejects archiving a statutory row (P0001)", () => {
    expect(code).toContain("v_row.statutory_class IS NOT NULL");
    expect(code).toContain("statutory rows are never archived");
    expect(code).toMatch(/ERRCODE = 'P0001'/);
  });

  it("keeps the mig-111 workspace-OWNER authz (not the 102 user_id pin)", () => {
    const body = functionBody(code);
    expect(body).toContain("is_email_triage_workspace_owner");
    expect(body).not.toContain("v_row.user_id <> auth.uid()");
    expect(body).toContain("SET search_path = public, pg_temp");
    expect(body).toContain("app.email_triage_status_in_progress");
  });

  it("places the statutory clause after the status gate, before the GUC arm", () => {
    const body = functionBody(code);
    const statusGate = body.indexOf("v_row.status <> 'new'");
    const statutory = body.indexOf("statutory_class IS NOT NULL");
    const guc = body.indexOf("app.email_triage_status_in_progress = 'on'");
    expect(statusGate).toBeGreaterThan(-1);
    expect(statutory).toBeGreaterThan(statusGate);
    expect(guc).toBeGreaterThan(statutory);
  });

  it("refreshes the function COMMENT to name the statutory pin", () => {
    expect(sql).toMatch(/COMMENT ON FUNCTION[\s\S]*statutory/);
  });

  it("down-file restores the mig-111 body verbatim (not the 102 ancestor)", () => {
    const downBody = functionBody(downCode);
    const live111Body = functionBody(
      mig111
        .split("\n")
        .filter((l) => !l.trim().startsWith("--"))
        .join("\n"),
    );
    // The down body must equal 111's — identical authz + no statutory clause.
    expect(downBody).toBe(live111Body);
    expect(downBody).not.toContain("statutory_class IS NOT NULL");
    expect(downBody).toContain("is_email_triage_workspace_owner");
  });
});
