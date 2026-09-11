import { describe, expect, it } from "vitest";
import { readFileSync } from "node:fs";
import path from "node:path";

const root = path.join(__dirname, "../supabase/migrations");
const sql = readFileSync(path.join(root, "138_agent_engine_runs.sql"), "utf8");
const down = readFileSync(path.join(root, "138_agent_engine_runs.down.sql"), "utf8");
const code = sql.split("\n").filter((line) => !line.trim().startsWith("--")).join("\n");

describe("migration 138: agent engine live runs", () => {
  it("creates the settings, run, and event tables with RLS", () => {
    expect(sql).toContain("public.workspace_engine_settings");
    expect(sql).toContain("public.agent_engine_runs");
    expect(sql).toContain("public.agent_engine_events");
    expect((sql.match(/ENABLE ROW LEVEL SECURITY/g) ?? []).length).toBe(3);
  });

  it("keeps execution bindings immutable and event writes idempotent", () => {
    expect(code).toMatch(/UNIQUE \(run_id, event_id\)/);
    expect(code).toMatch(/UNIQUE \(run_id, sequence\)/);
    expect(code).toMatch(/agent_engine_runs_conversation_uniq/);
  });

  it("pins the owner RPC search path and qualifies public relations", () => {
    expect(code).toMatch(/SECURITY DEFINER[\s\S]*SET search_path = public, pg_temp/);
    expect(code).toMatch(/public\.is_workspace_owner/);
    expect(code).toMatch(/public\.workspace_engine_settings/);
    expect(code).toMatch(/CREATE OR REPLACE FUNCTION public\.bind_agent_engine_run/);
  });

  it("keeps writes behind server RPCs and scopes reads to workspace membership", () => {
    expect(code).toMatch(/workspace_engine_settings_member_select[\s\S]*is_workspace_member/);
    expect(code).toMatch(/agent_engine_runs_member_select[\s\S]*is_workspace_member/);
    expect(code).toMatch(/agent_engine_events_member_select[\s\S]*is_workspace_member/);
    expect(code).toMatch(/GRANT EXECUTE ON FUNCTION public\.bind_agent_engine_run[\s\S]*TO service_role/);
  });

  it("does not use transactional-incompatible concurrent indexes", () => {
    expect(code).not.toMatch(/CONCURRENTLY/i);
  });

  it("has a down migration", () => {
    expect(down).toMatch(/DROP TABLE IF EXISTS public\.agent_engine_events/);
    expect(down).toMatch(/DROP TABLE IF EXISTS public\.agent_engine_runs/);
  });
});
