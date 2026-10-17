import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";

const root = join(__dirname, "..", "supabase", "migrations");
const migration = readFileSync(join(root, "149_codex_history_transfer_ack.sql"), "utf8");
const rollback = readFileSync(join(root, "149_codex_history_transfer_ack.down.sql"), "utf8");

describe("migration 149: Codex history-transfer acknowledgments", () => {
  it("stores a member acknowledgment for one conversation and auth-mode generation", () => {
    expect(migration).toMatch(/-- LAWFUL_BASIS: provisional Art\. 6\(1\)\(b\) candidate/);
    expect(migration).toMatch(/-- RETENTION: only the current generation and active workspace-membership epoch/);
    expect(migration).toMatch(/to_regclass\('public\.conversations'\) IS NULL/);
    expect(migration).toMatch(/to_regclass\('public\.users'\) IS NULL/);
    expect(migration).toMatch(/CREATE TABLE public\.codex_history_transfer_acknowledgments/);
    expect(migration).toMatch(/conversation_id uuid NOT NULL\s+REFERENCES public\.conversations\(id\) ON DELETE CASCADE/);
    expect(migration).toMatch(/member_user_id uuid NOT NULL\s+REFERENCES public\.users\(id\) ON DELETE CASCADE/);
    expect(migration).toMatch(/auth_mode_generation bigint NOT NULL CHECK \(auth_mode_generation > 0\)/);
    expect(migration).toMatch(/PRIMARY KEY \(\s*conversation_id,\s*member_user_id,\s*auth_mode_generation,\s*workspace_member_created_at\s*\)/);
    expect(migration).toMatch(/workspace_member_created_at timestamptz NOT NULL/);
    expect(migration).toMatch(/ENABLE ROW LEVEL SECURITY/);
    expect(migration).toMatch(/REVOKE ALL ON public\.codex_history_transfer_acknowledgments FROM PUBLIC, anon, authenticated, service_role/);
    expect(migration).toMatch(/GRANT SELECT ON public\.codex_history_transfer_acknowledgments TO service_role/);
  });

  it("records only the current member and current bound generation through authenticated RPCs", () => {
    expect(migration).toMatch(/CREATE FUNCTION public\.record_codex_history_transfer_acknowledgment\(/);
    expect(migration).toMatch(/CREATE FUNCTION public\.codex_history_transfer_acknowledged\(/);
    expect(migration).toMatch(/SECURITY DEFINER\s+SET search_path = public, pg_temp/);
    expect(migration).toMatch(/auth\.uid\(\)/);
    expect(migration).toMatch(/public\.is_workspace_member\(/);
    expect(migration).toMatch(/CREATE TRIGGER agent_engine_runs_purge_stale_codex_history_ack/);
    expect(migration).toMatch(/CREATE TRIGGER workspace_members_purge_codex_history_ack_on_delete/);
    expect(migration).toMatch(/CREATE TRIGGER workspace_members_purge_codex_history_ack_on_update/);
    expect(migration).toMatch(/FOR UPDATE OF m/);
    expect(migration).toMatch(/r\.engine_id = 'codex'[\s\S]*r\.execution_kind = 'conversation'[\s\S]*r\.auth_mode_generation = p_auth_mode_generation/);
    expect(migration).toMatch(/ON CONFLICT \(\s*conversation_id,\s*member_user_id,\s*auth_mode_generation,\s*workspace_member_created_at\s*\) DO NOTHING/);
    expect(migration).toMatch(/GRANT EXECUTE ON FUNCTION public\.record_codex_history_transfer_acknowledgment\(uuid, bigint\) TO authenticated/);
    expect(migration).toMatch(/GRANT EXECUTE ON FUNCTION public\.codex_history_transfer_acknowledged\(uuid, bigint\) TO authenticated/);
  });

  it("rolls back both acknowledgment RPCs and their private ledger", () => {
    expect(rollback).toMatch(/DROP TRIGGER workspace_members_purge_codex_history_ack_on_update/);
    expect(rollback).toMatch(/DROP TRIGGER workspace_members_purge_codex_history_ack_on_delete/);
    expect(rollback).toMatch(/DROP TRIGGER agent_engine_runs_purge_stale_codex_history_ack/);
    expect(rollback).toMatch(/DROP FUNCTION public\.codex_history_transfer_acknowledged\(uuid, bigint\)/);
    expect(rollback).toMatch(/DROP FUNCTION public\.record_codex_history_transfer_acknowledgment\(uuid, bigint\)/);
    expect(rollback).toMatch(/DROP TABLE public\.codex_history_transfer_acknowledgments/);
  });
});
