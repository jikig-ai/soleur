import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";

const migration = readFileSync(join(__dirname, "../supabase/migrations/173_codex_history_notice_issuance.sql"), "utf8");

describe("migration 173: notice-bound Codex acknowledgment", () => {
  it("stores private notice issuance by owner, conversation, generation, and membership epoch", () => {
    expect(migration).toMatch(/CREATE TABLE public\.codex_history_transfer_notice_issuances/);
    expect(migration).toMatch(/nonce_hash text NOT NULL/);
    expect(migration).toMatch(/delivered_at timestamptz/);
    expect(migration).toMatch(/workspace_id uuid NOT NULL/);
    expect(migration).toMatch(/member_user_id uuid NOT NULL REFERENCES public\.users\(id\) ON DELETE CASCADE/);
    expect(migration).toMatch(/FOREIGN KEY \(workspace_id, member_user_id\)\s+REFERENCES public\.workspace_members\(workspace_id, user_id\) ON DELETE CASCADE/);
    expect(migration).toMatch(/ENABLE ROW LEVEL SECURITY/);
    expect(migration).toMatch(/REVOKE ALL ON public\.codex_history_transfer_notice_issuances FROM PUBLIC, anon, authenticated, service_role/);
  });

  it("requires one current server-issued notice and consumes it before acknowledging", () => {
    const issue = migration.search(/^CREATE FUNCTION public\.issue_codex_history_transfer_notice\($/m);
    const record = migration.search(/^CREATE FUNCTION public\.record_codex_history_transfer_acknowledgment\($/m);
    const recordBody = migration.slice(record);
    const issuanceDelete = record + recordBody.search(/^  DELETE FROM public\.codex_history_transfer_notice_issuances AS i$/m);
    const ackInsert = record + recordBody.search(/^  INSERT INTO public\.codex_history_transfer_acknowledgments \($/m);
    expect(issue).toBeGreaterThan(-1);
    expect(record).toBeGreaterThan(issue);
    expect(migration.slice(issue, record)).toMatch(/c\.user_id = v_member_user_id/);
    expect(migration.slice(issue, record)).toMatch(/r\.auth_mode_generation = p_auth_mode_generation/);
    expect(issuanceDelete).toBeGreaterThan(record);
    expect(ackInsert).toBeGreaterThan(issuanceDelete);
    expect(migration.slice(issuanceDelete, ackInsert)).toMatch(/IF NOT FOUND THEN\s+RETURN false;/);
    expect(migration).toMatch(/REVOKE ALL ON FUNCTION public\.record_codex_history_transfer_acknowledgment\(uuid, bigint\) FROM PUBLIC, anon, authenticated, service_role;\s+DROP FUNCTION public\.record_codex_history_transfer_acknowledgment\(uuid, bigint\);/);
    expect(migration).toMatch(/nonce_hash = p_nonce_hash/);
    expect(migration).toMatch(/delivered_at IS NOT NULL/);
    expect(migration).toMatch(/CREATE TRIGGER purge_stale_codex_history_transfer_notice_issuances/);
    expect(migration).toMatch(/CREATE TRIGGER purge_replaced_codex_history_notice_membership/);
    expect(migration).toMatch(/REVOKE ALL ON FUNCTION public\.issue_codex_history_transfer_notice\(uuid, bigint, uuid, text\) FROM PUBLIC, anon, authenticated, service_role/);
    expect(migration).toMatch(/GRANT EXECUTE ON FUNCTION public\.issue_codex_history_transfer_notice\(uuid, bigint, uuid, text\) TO service_role/);
    expect(migration).toMatch(/GRANT EXECUTE ON FUNCTION public\.record_codex_history_transfer_acknowledgment\(uuid, bigint, text\) TO authenticated/);
  });
});
