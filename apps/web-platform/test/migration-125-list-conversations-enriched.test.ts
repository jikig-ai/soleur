import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import path from "node:path";

const MIGRATION_PATH = path.join(
  __dirname,
  "../supabase/migrations/125_list_conversations_enriched.sql",
);
const DOWN_PATH = path.join(
  __dirname,
  "../supabase/migrations/125_list_conversations_enriched.down.sql",
);

const sql = readFileSync(MIGRATION_PATH, "utf-8");
const downSql = readFileSync(DOWN_PATH, "utf-8");

// Negative "must NOT contain X" assertions run against the DDL with `--` comment
// lines stripped — the header comments deliberately name contrasted constructs
// (service_role, SECURITY DEFINER, CONCURRENTLY, BYPASSRLS) to explain their
// absence, and a raw-body grep would false-match them (grep-over-script-body
// learning 2026-06-17).
const code = sql
  .split("\n")
  .filter((l) => !l.trim().startsWith("--"))
  .join("\n");

describe("migration 125: list_conversations_enriched RPC", () => {
  it("creates the RPC with the full 6-arg signature", () => {
    expect(code).toMatch(
      /create\s+or\s+replace\s+function\s+public\.list_conversations_enriched\s*\(/i,
    );
    for (const param of [
      "p_repo_url text",
      "p_workspace_id uuid",
      "p_archive text",
      "p_status text",
      "p_domain text",
      "p_limit int",
    ]) {
      expect(code).toContain(param);
    }
  });

  it("is SECURITY INVOKER (RLS-preserving), NOT DEFINER", () => {
    // Non-vacuous: match `security invoker` bound to the function's language
    // declaration, NOT the `comment on function … 'Client-callable (SECURITY
    // INVOKER)'` string literal (which `code` retains — comment-stripping only
    // removes `--` lines, not SQL string literals).
    expect(code).toMatch(/language\s+sql\s+security\s+invoker/i);
    // DEFINER would bypass RLS-075 — the exact trap this RPC avoids.
    expect(code).not.toMatch(/security\s+definer/i);
  });

  it("BODY applies the outer scope predicates (not just declares the params)", () => {
    // Signature-param presence is necessary but not sufficient: deleting the
    // WHERE-clause use of workspace_id would pass all hook-level tests (they
    // mock the RPC) yet bleed workspace-B conversations into the workspace-A
    // rail — the exact functional bug the workspace_id discriminator prevents.
    expect(code).toMatch(/c\.repo_url\s*=\s*p_repo_url/i);
    expect(code).toMatch(/c\.workspace_id\s*=\s*p_workspace_id/i);
    // The 'general' domain sentinel maps to domain_leader IS NULL in the SQL
    // (verified end-to-end only against the JS mirror otherwise — pin the SQL).
    expect(code).toMatch(/p_domain\s*=\s*'general'[\s\S]*domain_leader\s+is\s+null/i);
  });

  it("pins search_path = public, pg_temp (defense-in-depth)", () => {
    expect(code).toMatch(/set\s+search_path\s*=\s*public\s*,\s*pg_temp/i);
  });

  it("GRANT hygiene: REVOKE from PUBLIC + anon, GRANT to authenticated, NEVER service_role", () => {
    expect(code).toMatch(
      /revoke\s+all\s+on\s+function\s+public\.list_conversations_enriched\([^)]*\)\s+from\s+public/i,
    );
    expect(code).toMatch(
      /revoke\s+all\s+on\s+function\s+public\.list_conversations_enriched\([^)]*\)\s+from\s+anon/i,
    );
    expect(code).toMatch(
      /grant\s+execute\s+on\s+function\s+public\.list_conversations_enriched\([^)]*\)\s+to\s+authenticated/i,
    );
    // service_role BYPASSRLS → would return all tenants' rows unfiltered.
    expect(code).not.toMatch(/grant[^;]*to\s+service_role/i);
  });

  it("ISOLATION: every messages read is LATERAL-correlated on the outer conversation id", () => {
    // The messages RLS (059) is workspace-broad; private-snippet isolation
    // rests entirely on m.conversation_id = c.id inside a LATERAL join. There
    // must be one such correlation per LATERAL block and no uncorrelated
    // `from public.messages` read.
    const lateralCount = (code.match(/join\s+lateral/gi) ?? []).length;
    expect(lateralCount).toBe(3);
    const correlationCount = (
      code.match(/m\.conversation_id\s*=\s*c\.id/gi) ?? []
    ).length;
    expect(correlationCount).toBe(3);
    // No messages read outside a correlated LATERAL (e.g. an IN(...) fan-out).
    expect(code).not.toMatch(/conversation_id\s+in\s*\(/i);
  });

  it("supporting index is plain CREATE INDEX (never CONCURRENTLY) and partial-on-active", () => {
    expect(code).toMatch(
      /create\s+index\s+if\s+not\s+exists\s+idx_conversations_rail/i,
    );
    expect(code).toMatch(/where\s+archived_at\s+is\s+null/i);
    // CONCURRENTLY inside the txn-wrapped runner → SQLSTATE 25001.
    expect(code).not.toMatch(/concurrently/i);
  });

  it("down migration drops the exact function signature + index", () => {
    expect(downSql).toMatch(
      /drop\s+function\s+if\s+exists\s+public\.list_conversations_enriched\(text,\s*uuid,\s*text,\s*text,\s*text,\s*int\)/i,
    );
    expect(downSql).toMatch(
      /drop\s+index\s+if\s+exists\s+public\.idx_conversations_rail/i,
    );
  });
});
