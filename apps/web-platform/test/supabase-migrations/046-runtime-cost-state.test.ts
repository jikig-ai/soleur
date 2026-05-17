import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import path from "node:path";

// Migration-shape test for 046_runtime_cost_state.sql.
//
// File-parse contract test (mirrors 037 precedent), pinning the SQL
// invariants required by PR-F Phase 1 of:
//   knowledge-base/project/plans/2026-05-17-feat-pr-f-inngest-trigger-layer-plan.md
//
// PR-F Phase 1 invariants (plan v2):
//   1. users.runtime_paused_at + users.runtime_cost_cap_cents columns
//      added (default 2000 cents = $20/hr per data-integrity P2-5).
//   2. record_byok_use_and_check_cap SECURITY DEFINER fn pinned to
//      LANGUAGE plpgsql (Kieran P1.1 / DHH rewrite: snapshot-isolation
//      bug + TOCTOU race in v1 CTE form fixed by explicit FOR UPDATE
//      lock on the users row BEFORE the SUM).
//   3. The FOR UPDATE lock on public.users MUST appear BEFORE the
//      SUM(token_count * unit_cost_cents) — this is the load-bearing
//      ordering invariant. Without it, two concurrent calls at
//      cap-boundary both pass the predicate.
//   4. cq-pg-security-definer-search-path-pin-pg-temp: SET search_path
//      = public, pg_temp on the new fn.
//   5. REVOKE from PUBLIC/anon/authenticated + GRANT EXECUTE to
//      service_role (standard private-RPC pattern; mirrors 037).
//   6. messages_external_tier_status_check CHECK constraint enforces
//      "drafts everywhere, sends nowhere" at DB level for external_*
//      tiers (RV5 promotion from ADR-prose to DB-level invariant).
//   7. cq-supabase-migration-no-concurrently: NO CREATE INDEX
//      CONCURRENTLY (Supabase wraps each migration in a transaction);
//      we rely on the existing audit_byok_use_founder_ts_idx covering
//      index from migration 037 — NO new index in this migration.
//
// Companion live-DB atomicity test:
//   `046-runtime-cost-state.atomicity.integration.test.ts` (this dir)
//   asserts the 10-concurrent-callers-at-cap-boundary contract and
//   the CHECK constraint rejection under live Postgres. Gated on
//   TENANT_INTEGRATION_TEST=1.

const MIGRATION_PATH = path.join(
  __dirname,
  "../../supabase/migrations/046_runtime_cost_state.sql",
);

describe("migration 046_runtime_cost_state", () => {
  const sql = readFileSync(MIGRATION_PATH, "utf8");

  // Strip line comments before pattern checks (mirrors 037).
  const executable = sql.replace(/--[^\n]*/g, "");

  describe("users column additions", () => {
    it("adds runtime_paused_at as nullable timestamptz", () => {
      expect(executable).toMatch(
        /ALTER\s+TABLE\s+public\.users[\s\S]*?ADD\s+COLUMN\s+IF\s+NOT\s+EXISTS\s+runtime_paused_at\s+timestamptz/i,
      );
    });

    it("adds runtime_cost_cap_cents NOT NULL DEFAULT 2000", () => {
      expect(executable).toMatch(
        /ADD\s+COLUMN\s+IF\s+NOT\s+EXISTS\s+runtime_cost_cap_cents\s+int\s+NOT\s+NULL\s+DEFAULT\s+2000/i,
      );
    });

    it("documents both columns with COMMENT", () => {
      // Operator-readable rationale persists in pg_description; mirrors
      // 037's pattern of inline column documentation.
      expect(executable).toMatch(/COMMENT\s+ON\s+COLUMN\s+public\.users\.runtime_paused_at/i);
      expect(executable).toMatch(/COMMENT\s+ON\s+COLUMN\s+public\.users\.runtime_cost_cap_cents/i);
    });
  });

  describe("record_byok_use_and_check_cap function", () => {
    it("declares LANGUAGE plpgsql (Kieran P1.1 / DHH rewrite)", () => {
      // v1 plan prescribed LANGUAGE sql (CTE form). v2 rewrite uses
      // plpgsql to enable the explicit FOR UPDATE lock that closes
      // the TOCTOU race at cap-boundary.
      expect(executable).toMatch(
        /CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.record_byok_use_and_check_cap[\s\S]*?LANGUAGE\s+plpgsql/i,
      );
    });

    it("declares SECURITY DEFINER", () => {
      expect(executable).toMatch(
        /CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.record_byok_use_and_check_cap[\s\S]*?SECURITY\s+DEFINER/i,
      );
    });

    it("pins search_path = public, pg_temp (cq-pg-security-definer-search-path-pin-pg-temp)", () => {
      expect(executable).toMatch(
        /CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.record_byok_use_and_check_cap[\s\S]*?SET\s+search_path\s*=\s*public,\s*pg_temp/i,
      );
    });

    it("returns TABLE(cumulative_cents int, kill_tripped boolean)", () => {
      expect(executable).toMatch(
        /record_byok_use_and_check_cap[\s\S]*?RETURNS\s+TABLE\s*\(\s*cumulative_cents\s+int\s*,\s*kill_tripped\s+boolean\s*\)/i,
      );
    });

    it("locks public.users via FOR UPDATE before the SUM (TOCTOU fix — Kieran P1.1)", () => {
      // Load-bearing ordering invariant. The function body MUST contain
      // a SELECT ... FROM public.users WHERE id = p_founder_id FOR UPDATE
      // AND that lock MUST appear textually BEFORE any
      // SUM(token_count * unit_cost_cents). Without this ordering,
      // two concurrent calls at cap-boundary both pass the predicate.
      const lockIdx = executable.search(
        /FROM\s+public\.users[\s\S]*?WHERE\s+id\s*=\s*p_founder_id[\s\S]*?FOR\s+UPDATE/i,
      );
      const sumIdx = executable.search(
        /SUM\s*\(\s*token_count\s*\*\s*unit_cost_cents\s*\)/i,
      );
      expect(lockIdx, "expected FOR UPDATE lock present").toBeGreaterThan(-1);
      expect(sumIdx, "expected SUM(token_count * unit_cost_cents) present").toBeGreaterThan(-1);
      expect(
        lockIdx,
        `FOR UPDATE (at offset ${lockIdx}) MUST appear before SUM (at offset ${sumIdx}) to prevent TOCTOU race`,
      ).toBeLessThan(sumIdx);
    });

    it("INSERTs into public.audit_byok_use before computing the SUM (cumulative-correctness invariant)", () => {
      const insertIdx = executable.search(
        /INSERT\s+INTO\s+public\.audit_byok_use[\s\S]*?VALUES/i,
      );
      const sumIdx = executable.search(
        /SUM\s*\(\s*token_count\s*\*\s*unit_cost_cents\s*\)/i,
      );
      expect(insertIdx, "expected INSERT INTO audit_byok_use present").toBeGreaterThan(-1);
      // After the INSERT, the next SUM should be the post-insert read.
      // The post-INSERT statement's snapshot WILL include the row
      // because plpgsql statements within a single function call share
      // the same transaction (the surrounding `BEGIN`/`END` block).
      expect(
        insertIdx,
        `INSERT (at offset ${insertIdx}) must appear before SUM (at offset ${sumIdx}) so the just-inserted row is counted`,
      ).toBeLessThan(sumIdx);
    });

    it("flips users.runtime_paused_at when total exceeds cap and was previously NULL", () => {
      // The UPDATE must guard `runtime_paused_at IS NULL` to be idempotent
      // (a second cap-breach should not re-stamp the timestamp).
      expect(executable).toMatch(
        /UPDATE\s+public\.users[\s\S]*?SET\s+runtime_paused_at\s*=\s*now\(\)[\s\S]*?WHERE[\s\S]*?id\s*=\s*p_founder_id[\s\S]*?runtime_paused_at\s+IS\s+NULL/i,
      );
    });
  });

  describe("function privileges", () => {
    it("revokes from PUBLIC, anon, authenticated", () => {
      // Mirrors 037 pattern: explicit-role revoke is required because
      // Supabase's ALTER DEFAULT PRIVILEGES auto-grants new fns to
      // anon/authenticated/service_role.
      expect(executable).toMatch(
        /REVOKE\s+ALL\s+ON\s+FUNCTION\s+public\.record_byok_use_and_check_cap\s*\([\s\S]*?\)[\s\S]*?FROM\s+PUBLIC,\s*anon,\s*authenticated/i,
      );
    });

    it("grants EXECUTE to service_role only", () => {
      expect(executable).toMatch(
        /GRANT\s+EXECUTE\s+ON\s+FUNCTION\s+public\.record_byok_use_and_check_cap\s*\([\s\S]*?\)[\s\S]*?TO\s+service_role/i,
      );
    });
  });

  describe("messages_external_tier_status_check (RV5 — drafts-everywhere CHECK)", () => {
    it("declares the CHECK constraint on public.messages", () => {
      expect(executable).toMatch(
        /ALTER\s+TABLE\s+public\.messages[\s\S]*?ADD\s+CONSTRAINT\s+messages_external_tier_status_check[\s\S]*?CHECK\s*\(/i,
      );
    });

    it("scopes the constraint to external_* tiers via NOT IN guard", () => {
      // Body shape: (tier NOT IN ('external_brand_critical', 'external_low_stakes') OR status IN ('draft', 'archived')).
      // The NOT IN guard ensures non-external rows pass the constraint
      // unconditionally; external rows must be in the draft/archived
      // status set.
      expect(executable).toMatch(
        /tier\s+NOT\s+IN\s*\(\s*'external_brand_critical'\s*,\s*'external_low_stakes'\s*\)/i,
      );
    });

    it("permits only draft + archived statuses for external_* tiers", () => {
      expect(executable).toMatch(
        /status\s+IN\s*\(\s*'draft'\s*,\s*'archived'\s*\)/i,
      );
    });

    it("documents the constraint's amendment contract via COMMENT", () => {
      // ADR-030 I5 says: any future auto-send capability MUST first
      // DROP this constraint explicitly. The COMMENT is the in-DB
      // signal that this is load-bearing for "drafts everywhere".
      expect(executable).toMatch(
        /COMMENT\s+ON\s+CONSTRAINT\s+messages_external_tier_status_check\s+ON\s+public\.messages/i,
      );
    });
  });

  describe("supabase migration discipline", () => {
    it("does NOT use CREATE INDEX CONCURRENTLY (cq-supabase-migration-no-concurrently)", () => {
      // Supabase wraps each migration in a transaction; CONCURRENTLY
      // fails with SQLSTATE 25001. Existing index
      // audit_byok_use_founder_ts_idx from migration 037 covers the
      // 1-hour SUM hot path — no new index needed here.
      expect(executable).not.toMatch(/CREATE\s+INDEX\s+CONCURRENTLY/i);
    });
  });
});
