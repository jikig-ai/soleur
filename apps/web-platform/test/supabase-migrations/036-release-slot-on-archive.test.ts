import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import path from "node:path";

// Migration-shape test for 036_release_slot_on_archive.sql.
//
// File-parse test, not a live-DB test. It pins the SQL contract that fixes
// the user-reported bug: archiving a conversation must release its
// concurrency slot via the existing `public.release_conversation_slot` RPC.
//
// The trigger fires ONLY on `archived_at` NULL → non-NULL transitions
// (NOT on `status = 'completed'` transitions) — see plan Risk #5: releasing
// on completed-only would let a resumed conversation run outside the slot
// ledger because `resume_session` does not call `acquireSlot`.
//
// Plan: 2026-05-04-fix-cc-conversation-limit-archive-plan.md.

const MIGRATION_PATH = path.join(
  __dirname,
  "../../supabase/migrations/036_release_slot_on_archive.sql",
);

describe("migration 036_release_slot_on_archive", () => {
  const sql = readFileSync(MIGRATION_PATH, "utf8");

  // Strip line-comments before pattern checks so header prose can mention
  // the same tokens without tripping the regex (mirrors 032 pattern).
  const executable = sql.replace(/--[^\n]*/g, "");

  it("declares a SECURITY DEFINER trigger function pinning search_path", () => {
    // cq-pg-security-definer-search-path-pin-pg-temp: pin to public, pg_temp.
    expect(executable).toMatch(/CREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\s+public\.release_slot_on_archive\s*\(\s*\)/i);
    expect(executable).toMatch(/SECURITY\s+DEFINER/i);
    expect(executable).toMatch(/SET\s+search_path\s*=\s*public\s*,\s*pg_temp/i);
  });

  it("body invokes public.release_conversation_slot with OLD.user_id and OLD.id", () => {
    // The function body must call the existing keyed-DELETE RPC with
    // qualified relation names (cq-pg-security-definer-search-path-pin-pg-temp).
    //
    // OLD (not NEW) is load-bearing: the conversations RLS policy uses
    // `FOR ALL USING (auth.uid() = user_id)` with NO `WITH CHECK` clause
    // (001_initial_schema.sql:60-62). A malicious UPDATE can change
    // `NEW.user_id` to any value the attacker chose; the trigger would
    // then drive a definer-elevated DELETE against that user's slot row.
    // OLD.user_id pins the lookup to the auth-checked pre-image owner.
    expect(executable).toMatch(
      /public\.release_conversation_slot\s*\(\s*OLD\.user_id\s*,\s*OLD\.id\s*\)/i,
    );
  });

  it("does NOT pass NEW.user_id or NEW.id to release_conversation_slot (security-sentinel P1)", () => {
    // Belt-and-suspenders for the OLD-vs-NEW invariant above.
    expect(executable).not.toMatch(
      /release_conversation_slot\s*\([^)]*NEW\.user_id/i,
    );
    expect(executable).not.toMatch(
      /release_conversation_slot\s*\([^)]*NEW\.id\b/i,
    );
  });

  it("creates an AFTER UPDATE OF archived_at trigger on public.conversations", () => {
    // `OF archived_at` keeps the trigger no-op for unrelated column updates
    // (cheaper than WHEN-clause filtering alone — Postgres skips trigger
    // evaluation entirely when the named column wasn't in the UPDATE's SET
    // list).
    expect(executable).toMatch(
      /CREATE\s+TRIGGER\s+conversations_release_slot_on_archive[\s\S]*?AFTER\s+UPDATE\s+OF\s+archived_at[\s\S]*?ON\s+public\.conversations/i,
    );
  });

  it("WHEN clause uses IS DISTINCT FROM for nullable archived_at comparison", () => {
    // `OLD.archived_at = NEW.archived_at` returns NULL when both sides are
    // NULL, which `WHEN` treats as false → trigger silently misses the
    // NULL → non-NULL transition. IS DISTINCT FROM correctly compares
    // nullable values (Postgres documented gotcha; see plan Sharp Edges).
    expect(executable).toMatch(
      /WHEN\s*\([^)]*OLD\.archived_at\s+IS\s+DISTINCT\s+FROM\s+NEW\.archived_at[^)]*\)/i,
    );
  });

  it("WHEN clause filters to NULL → non-NULL transitions only (archive, not unarchive)", () => {
    // Unarchive (archived_at non-NULL → NULL) must NOT release a slot — a
    // re-acquire would happen on the next start_session/resume.
    expect(executable).toMatch(
      /WHEN\s*\([^)]*NEW\.archived_at\s+IS\s+NOT\s+NULL[^)]*\)/i,
    );
  });

  it("trigger fires FOR EACH ROW (not statement-level)", () => {
    // Per-row body needs NEW.user_id and NEW.id; FOR EACH STATEMENT cannot
    // see them.
    expect(executable).toMatch(/FOR\s+EACH\s+ROW/i);
  });

  it("does NOT fire on status transitions (archive-only by AFTER UPDATE OF clause)", () => {
    // Trigger is `AFTER UPDATE OF archived_at` — the column list is the
    // hard gate. Belt-and-suspenders: the create-trigger statement must NOT
    // also list `status` in its OF clause.
    const triggerStmt = executable.match(
      /CREATE\s+TRIGGER\s+conversations_release_slot_on_archive[\s\S]*?(?=;)/i,
    );
    expect(triggerStmt, "must declare conversations_release_slot_on_archive trigger").not.toBeNull();
    expect(triggerStmt![0]).not.toMatch(/UPDATE\s+OF\s+[^;]*\bstatus\b/i);
  });

  it("revokes default PUBLIC execute on the trigger function (definer hygiene)", () => {
    // Trigger executes as definer; no direct callers, no grants.
    expect(executable).toMatch(
      /REVOKE\s+ALL\s+ON\s+FUNCTION\s+public\.release_slot_on_archive\s*\(\s*\)\s+FROM\s+PUBLIC/i,
    );
  });
});
