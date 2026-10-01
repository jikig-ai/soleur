import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import path from "node:path";

const MIGRATION_PATH = path.join(
  __dirname,
  "../supabase/migrations/154_inbox_item_idempotent_rearchive.sql",
);
const DOWN_PATH = path.join(
  __dirname,
  "../supabase/migrations/154_inbox_item_idempotent_rearchive.down.sql",
);
const MIGRATION_122_PATH = path.join(
  __dirname,
  "../supabase/migrations/122_inbox_item.sql",
);

const sql = readFileSync(MIGRATION_PATH, "utf-8");
const downSql = readFileSync(DOWN_PATH, "utf-8");
const mig122 = readFileSync(MIGRATION_122_PATH, "utf-8");

// Negative assertions run against comment-stripped code.
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
    /CREATE OR REPLACE FUNCTION public\.set_inbox_item_state[\s\S]*?\$\$;/,
  );
  if (!m) throw new Error("set_inbox_item_state body not found");
  return m[0];
}

describe("migration 154: idempotent re-archive on set_inbox_item_state", () => {
  it("re-creates the function", () => {
    expect(sql).toContain(
      "CREATE OR REPLACE FUNCTION public.set_inbox_item_state(p_id uuid, p_action text)",
    );
  });

  it("adds the early-return BEFORE the archive-guard, inside the archived branch", () => {
    const body = functionBody(code);
    const archivedBranch = body.indexOf("p_action = 'archived'");
    const earlyReturn = body.indexOf("status = 'archived' THEN RETURN");
    const guard = body.indexOf("cannot archive an un-acted action_required");
    expect(archivedBranch).toBeGreaterThan(-1);
    expect(earlyReturn).toBeGreaterThan(archivedBranch);
    // Early-return precedes the guard — an already-archived un-acted row
    // returns cleanly (idempotent), it isn't P0001-rejected.
    expect(guard).toBeGreaterThan(earlyReturn);
  });

  it("keeps the mig-122 authz + archive-guard verbatim", () => {
    const body = functionBody(code);
    expect(body).toContain("is_workspace_owner");
    expect(body).toContain("cannot archive an un-acted action_required item");
    expect(body).toContain("SET search_path = public, pg_temp");
    expect(body).toContain("FOR UPDATE");
  });

  it("down-file restores the mig-122 body verbatim", () => {
    const downBody = functionBody(downCode);
    const live122Body = functionBody(
      mig122
        .split("\n")
        .filter((l) => !l.trim().startsWith("--"))
        .join("\n"),
    );
    expect(downBody).toBe(live122Body);
    expect(downBody).not.toContain("THEN RETURN");
  });

  it("keeps the acted/read branches byte-identical to 122", () => {
    const up = functionBody(code);
    const down = functionBody(downCode);
    // The ONLY delta between up and down is the early-return line (+comments).
    const stripEarly = (b: string) =>
      b
        .split("\n")
        .filter(
          (l) =>
            !l.includes("status = 'archived' THEN RETURN") &&
            !l.trim().startsWith("--"),
        )
        .join("\n");
    expect(stripEarly(up)).toBe(stripEarly(down));
  });
});
