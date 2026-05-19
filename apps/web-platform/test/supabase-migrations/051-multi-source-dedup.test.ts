import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import path from "node:path";

// Migration-shape test for 051_multi_source_dedup.sql.
//
// File-parse contract test (mirrors 046 precedent), pinning the SQL
// invariants required by PR-H Phase 1 of:
//   knowledge-base/project/plans/2026-05-19-feat-daily-priorities-multi-source-pr-h-plan.md
//
// PR-H Phase 1 invariants:
//   1. messages.source_ref column added (nullable for backfill safety).
//   2. Partial-unique index messages_active_draft_dedup_idx on
//      (user_id, source, source_ref) WHERE status='draft' AND
//      source_ref IS NOT NULL.
//   3. audit_github_token_use append-only ledger with RLS + founder
//      SELECT policy + service-role-only INSERT via RPC.
//   4. record_github_token_use SECURITY DEFINER fn pinned to
//      LANGUAGE plpgsql with SET search_path = public, pg_temp
//      (cq-pg-security-definer-search-path-pin-pg-temp); REVOKEd
//      from PUBLIC/anon/authenticated; GRANTed to service_role.
//   5. processed_github_events(delivery_id PRIMARY KEY) with received_at
//      DEFAULT now(); RLS enabled with no founder-facing policies
//      (service-role-only, mirrors processed_stripe_events).

const MIGRATION_PATH = path.join(
  __dirname,
  "../../supabase/migrations/051_multi_source_dedup.sql",
);

describe("migration 051_multi_source_dedup", () => {
  const sql = readFileSync(MIGRATION_PATH, "utf8");
  // Strip line comments before pattern checks (mirrors 046 precedent).
  const executable = sql.replace(/--[^\n]*/g, "");

  describe("messages.source_ref column", () => {
    it("adds source_ref as nullable text", () => {
      expect(executable).toMatch(
        /ALTER\s+TABLE\s+public\.messages[\s\S]*?ADD\s+COLUMN\s+IF\s+NOT\s+EXISTS\s+source_ref\s+text/i,
      );
    });

    it("documents source_ref with COMMENT", () => {
      expect(executable).toMatch(/COMMENT\s+ON\s+COLUMN\s+public\.messages\.source_ref/i);
    });
  });

  describe("messages_active_draft_dedup_idx partial-unique index", () => {
    it("is a UNIQUE INDEX on (user_id, source, source_ref)", () => {
      expect(executable).toMatch(
        /CREATE\s+UNIQUE\s+INDEX\s+(IF\s+NOT\s+EXISTS\s+)?messages_active_draft_dedup_idx[\s\S]*?\(\s*user_id\s*,\s*source\s*,\s*source_ref\s*\)/i,
      );
    });

    it("filters WHERE status='draft' AND source_ref IS NOT NULL", () => {
      expect(executable).toMatch(
        /messages_active_draft_dedup_idx[\s\S]*?WHERE\s+status\s*=\s*'draft'\s+AND\s+source_ref\s+IS\s+NOT\s+NULL/i,
      );
    });

    it("documents the dedup contract via COMMENT ON INDEX", () => {
      expect(executable).toMatch(/COMMENT\s+ON\s+INDEX\s+public\.messages_active_draft_dedup_idx/i);
    });
  });

  describe("audit_github_token_use ledger", () => {
    it("creates the table with founder_id, installation_id, repo_full_name, endpoint, ts, response_status", () => {
      expect(executable).toMatch(/CREATE\s+TABLE\s+(IF\s+NOT\s+EXISTS\s+)?public\.audit_github_token_use/i);
      expect(executable).toMatch(/founder_id\s+uuid/i);
      expect(executable).toMatch(/installation_id\s+bigint/i);
      expect(executable).toMatch(/repo_full_name\s+text/i);
      expect(executable).toMatch(/endpoint\s+text/i);
      expect(executable).toMatch(/ts\s+timestamptz/i);
      expect(executable).toMatch(/response_status\s+int/i);
    });

    it("enables RLS on the table", () => {
      expect(executable).toMatch(
        /ALTER\s+TABLE\s+public\.audit_github_token_use\s+ENABLE\s+ROW\s+LEVEL\s+SECURITY/i,
      );
    });

    it("creates owner SELECT policy gated on auth.uid() = founder_id", () => {
      expect(executable).toMatch(
        /CREATE\s+POLICY\s+audit_github_token_use_owner_select[\s\S]*?FOR\s+SELECT\s+USING\s*\(\s*auth\.uid\(\)\s*=\s*founder_id\s*\)/i,
      );
    });

    it("creates the founder+ts covering index for audit lookups", () => {
      expect(executable).toMatch(
        /CREATE\s+INDEX\s+(IF\s+NOT\s+EXISTS\s+)?audit_github_token_use_founder_ts_idx[\s\S]*?\(\s*founder_id\s*,\s*ts\s+DESC\s*\)/i,
      );
    });
  });

  describe("record_github_token_use RPC", () => {
    it("declares LANGUAGE plpgsql", () => {
      expect(executable).toMatch(
        /CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.record_github_token_use[\s\S]*?LANGUAGE\s+plpgsql/i,
      );
    });

    it("declares SECURITY DEFINER", () => {
      expect(executable).toMatch(
        /CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.record_github_token_use[\s\S]*?SECURITY\s+DEFINER/i,
      );
    });

    it("pins search_path = public, pg_temp (cq-pg-security-definer-search-path-pin-pg-temp)", () => {
      expect(executable).toMatch(
        /CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.record_github_token_use[\s\S]*?SET\s+search_path\s*=\s*public,\s*pg_temp/i,
      );
    });

    it("REVOKEs from PUBLIC, anon, authenticated", () => {
      expect(executable).toMatch(
        /REVOKE\s+ALL\s+ON\s+FUNCTION\s+public\.record_github_token_use[\s\S]*?FROM\s+PUBLIC,\s*anon,\s*authenticated/i,
      );
    });

    it("GRANTs EXECUTE only to service_role", () => {
      expect(executable).toMatch(
        /GRANT\s+EXECUTE\s+ON\s+FUNCTION\s+public\.record_github_token_use[\s\S]*?TO\s+service_role/i,
      );
    });
  });

  describe("processed_github_events table", () => {
    it("creates the table with delivery_id PRIMARY KEY + received_at DEFAULT now()", () => {
      expect(executable).toMatch(/CREATE\s+TABLE\s+(IF\s+NOT\s+EXISTS\s+)?public\.processed_github_events/i);
      expect(executable).toMatch(/delivery_id\s+text\s+PRIMARY\s+KEY/i);
      expect(executable).toMatch(/received_at\s+timestamptz\s+NOT\s+NULL\s+DEFAULT\s+now\(\)/i);
    });

    it("enables RLS on the table", () => {
      expect(executable).toMatch(
        /ALTER\s+TABLE\s+public\.processed_github_events\s+ENABLE\s+ROW\s+LEVEL\s+SECURITY/i,
      );
    });

    it("creates a received_at DESC index for retention scans", () => {
      expect(executable).toMatch(
        /CREATE\s+INDEX\s+(IF\s+NOT\s+EXISTS\s+)?processed_github_events_received_at_idx[\s\S]*?\(\s*received_at\s+DESC\s*\)/i,
      );
    });

    it("documents retention via COMMENT ON TABLE", () => {
      expect(executable).toMatch(/COMMENT\s+ON\s+TABLE\s+public\.processed_github_events/i);
    });
  });

  describe("cq-supabase-migration-no-concurrently", () => {
    // Supabase wraps each migration in a transaction; CONCURRENTLY is
    // illegal there. The CHECK is structural, not regex-trivia.
    it("contains no CREATE INDEX CONCURRENTLY", () => {
      expect(executable).not.toMatch(/CREATE\s+INDEX\s+CONCURRENTLY/i);
    });
  });
});
