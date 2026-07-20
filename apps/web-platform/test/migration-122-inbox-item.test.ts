import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import path from "node:path";

const MIGRATION_PATH = path.join(
  __dirname,
  "../supabase/migrations/122_inbox_item.sql",
);
const DOWN_PATH = path.join(
  __dirname,
  "../supabase/migrations/122_inbox_item.down.sql",
);

const sql = readFileSync(MIGRATION_PATH, "utf-8");
const downSql = readFileSync(DOWN_PATH, "utf-8");

// Negative "must NOT contain X" assertions run against the DDL with `--` comment
// lines stripped — the header comments deliberately NAME contrasted constructs
// (RESTRICT, WORM, email_triage_items) to explain their absence, and a raw-body
// grep would false-match them (grep-over-script-body learning).
const code = sql
  .split("\n")
  .filter((l) => !l.trim().startsWith("--"))
  .join("\n");

describe("migration 122: inbox_item operational-notification store", () => {
  it("creates inbox_item with RLS enabled", () => {
    expect(sql).toContain("CREATE TABLE IF NOT EXISTS public.inbox_item");
    expect(sql).toContain(
      "ALTER TABLE public.inbox_item ENABLE ROW LEVEL SECURITY",
    );
  });

  it("has the v1 severity + source CHECK sets (only the emittable sources)", () => {
    expect(code).toMatch(
      /severity[^\n]*CHECK\s*\(severity IN \('action_required', 'attention', 'info'\)\)/,
    );
    // v1 emittable set ONLY — approval_required / autopilot_run are NOT here;
    // #4672 / #4674 ALTER the CHECK when they ship their emitter.
    expect(code).toMatch(
      /source[^\n]*CHECK\s*\(source IN \('task_completed', 'system'\)\)/,
    );
    expect(code).not.toMatch(/CHECK\s*\(source IN[^)]*approval_required/);
    expect(code).not.toMatch(/CHECK\s*\(source IN[^)]*autopilot_run/);
  });

  it("has inline v1 state (no per-Owner recipient-state join — deferred to #4672)", () => {
    for (const col of [
      "workspace_id",
      "user_id",
      "severity",
      "source",
      "title",
      "source_ref",
      "dedup_key",
      "status",
      "read_at",
      "acted_at",
      "archived_at",
    ]) {
      expect(code).toMatch(new RegExp(`\\b${col}\\b`));
    }
    // No recipient-state join table.
    expect(code).not.toMatch(/inbox_item_recipient_state/);
  });

  it("CASCADEs both FKs (operational data follows lifecycle — not the WORM RESTRICT)", () => {
    expect(code).toMatch(
      /workspace_id[^\n]*REFERENCES public\.workspaces\(id\) ON DELETE CASCADE/,
    );
    expect(code).toMatch(
      /user_id[^\n]*REFERENCES public\.users\(id\) ON DELETE CASCADE/,
    );
    // The statutory RESTRICT posture must NOT be copied onto operational data.
    expect(code).not.toMatch(/ON DELETE RESTRICT/);
  });

  it("REVOKEs all three write verbs from PUBLIC/anon/authenticated", () => {
    expect(sql).toMatch(
      /REVOKE INSERT ON TABLE public\.inbox_item FROM PUBLIC, anon, authenticated/,
    );
    expect(sql).toMatch(
      /REVOKE UPDATE ON TABLE public\.inbox_item FROM PUBLIC, anon, authenticated/,
    );
    expect(sql).toMatch(
      /REVOKE DELETE ON TABLE public\.inbox_item FROM PUBLIC, anon, authenticated/,
    );
  });

  it("SELECT policy: targeted rows private to recipient, broadcasts to workspace Owners", () => {
    expect(sql).toContain("CREATE POLICY inbox_item_owner_select");
    // Reuses the shared mig-098 helper — NOT a new helper, NOT the email-specific one.
    expect(code).toMatch(/public\.is_workspace_owner\(workspace_id, auth\.uid\(\)\)/);
    expect(code).not.toMatch(/is_email_triage_workspace_owner/);
    expect(code).not.toMatch(/CREATE OR REPLACE FUNCTION public\.is_workspace_owner/);
    expect(code).not.toMatch(/is_workspace_member/);
    // Targeted-row privacy branch.
    expect(code).toMatch(/user_id = auth\.uid\(\)/);
    expect(code).toMatch(/user_id IS NULL AND public\.is_workspace_owner/);
    // No authenticated write policy (bypass-path learning): exactly one policy,
    // and it is FOR SELECT. (The RPC's `SELECT … FOR UPDATE` row-lock is not a
    // policy, so it is not counted here.)
    expect(code.match(/CREATE POLICY/g)?.length ?? 0).toBe(1);
    expect(code).toMatch(/CREATE POLICY inbox_item_owner_select ON public\.inbox_item\s*FOR SELECT/);
  });

  it("dedup: workspace-scoped partial-unique index (ADR-035)", () => {
    expect(code).toMatch(
      /CREATE UNIQUE INDEX[^\n]*inbox_item_dedup_key_uniq[\s\S]*?\(workspace_id, dedup_key\)[\s\S]*?WHERE dedup_key IS NOT NULL/,
    );
  });

  it("set_inbox_item_state RPC: SECURITY DEFINER, search_path pinned, service_role REVOKE'd", () => {
    expect(code).toMatch(
      /CREATE OR REPLACE FUNCTION public\.set_inbox_item_state\(p_id uuid, p_action text\)/,
    );
    expect(code).toMatch(/SECURITY DEFINER/);
    expect(code).toMatch(/SET search_path = public, pg_temp/);
    expect(code).toMatch(/auth\.uid\(\) IS NULL/);
    expect(code).toMatch(/FOR UPDATE/);
    // service_role explicitly REVOKE'd from the RPC (caller-override guard).
    expect(code).toMatch(
      /REVOKE ALL ON FUNCTION public\.set_inbox_item_state\(uuid, text\)\s*FROM PUBLIC, anon, authenticated, service_role/,
    );
    expect(code).toMatch(
      /GRANT EXECUTE ON FUNCTION public\.set_inbox_item_state\(uuid, text\)\s*TO authenticated/,
    );
  });

  it("RPC archive-guard: refuses to archive an un-acted action_required item", () => {
    expect(code).toMatch(
      /severity = 'action_required' AND v_row\.acted_at IS NULL/,
    );
    expect(code).toMatch(/cannot archive an un-acted action_required item/);
  });

  it("RPC acted_at is set-once (idempotent — pre-wires the 'already resolved' banner)", () => {
    expect(code).toMatch(/v_row\.acted_at IS NULL/);
    expect(code).toMatch(/acted_at = now\(\)/);
  });

  it("retention: 90d sweep with the un-acted action_required carve-out, pg_cron-guarded", () => {
    expect(code).toMatch(/cron\.schedule\(\s*'inbox_item_retention'/);
    expect(code).toMatch(/interval '90 days'/);
    // Only archived OR info are eligible…
    expect(code).toMatch(/status = 'archived' OR severity = 'info'/);
    // …and NEVER an un-acted action_required row (defense-in-depth carve-out).
    expect(code).toMatch(
      /NOT \(severity = 'action_required' AND acted_at IS NULL\)/,
    );
    // pg_cron-absent CI is tolerated.
    expect(code).toMatch(/WHEN undefined_table/);
  });

  it("does NOT touch the email_triage_items WORM ledger", () => {
    expect(code).not.toMatch(/ALTER TABLE public\.email_triage_items/);
    expect(code).not.toMatch(/email_triage_items_no_mutate/);
    expect(code).not.toMatch(/CREATE TRIGGER[^\n]*email_triage_items/);
  });

  describe("down migration", () => {
    it("unschedules the cron, drops the RPC + indexes + table, and the ledger row", () => {
      expect(downSql).toMatch(/cron\.unschedule\('inbox_item_retention'\)/);
      expect(downSql).toMatch(
        /DROP FUNCTION IF EXISTS public\.set_inbox_item_state\(uuid, text\)/,
      );
      expect(downSql).toMatch(/DROP TABLE IF EXISTS public\.inbox_item/);
      expect(downSql).toMatch(
        /DELETE FROM public\._schema_migrations WHERE filename = '122_inbox_item\.sql'/,
      );
      // pg_cron-absent guard on the down-file too.
      expect(downSql).toMatch(/WHEN undefined_table THEN NULL/);
    });

    it("never drops the shared is_workspace_owner helper", () => {
      expect(downSql).not.toMatch(/DROP FUNCTION[^\n]*is_workspace_owner/);
    });
  });
});
