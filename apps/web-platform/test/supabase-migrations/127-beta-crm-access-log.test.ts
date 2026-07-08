import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import path from "node:path";

// Migration-shape contract for 127_beta_crm_access_log.sql (feat-beta-crm-ui
// #6172, ADR-102 UI phase). Same two-tier convention as 126: fast file-parse
// SHAPE tests here (the pre-merge CI gate) guard the owner-private RLS posture,
// the append-only invariant, the atomic fail-closed read+audit structure, the
// no-existence-oracle authorization pin, and the down-file. The live-DB
// behavioral proofs (returned contact ⇒ an audit row; audit-INSERT failure
// rolls back the read; foreign contact → 42501) live in the gated
// beta-crm-dsar.integration.test.ts family (SUPABASE_DEV_INTEGRATION=1 on a
// dedicated dev project, hr-dev-prd-distinct-supabase-projects) — never the
// shared dev pre-merge.
//
// Plan: knowledge-base/project/plans/2026-07-08-feat-beta-crm-ui-read-only-board-plan.md

const MIGRATION = path.resolve(
  __dirname,
  "../../supabase/migrations/127_beta_crm_access_log.sql",
);
const DOWN = path.resolve(
  __dirname,
  "../../supabase/migrations/127_beta_crm_access_log.down.sql",
);

const stripComments = (sql: string) => sql.replace(/--[^\n]*/g, "");

// Extract a single CREATE FUNCTION ... $$; body by name.
function fnBody(sql: string, name: string): string {
  const re = new RegExp(
    `CREATE\\s+(?:OR\\s+REPLACE\\s+)?FUNCTION\\s+public\\.${name}\\s*\\([\\s\\S]*?\\$\\$;`,
    "i",
  );
  return sql.match(re)?.[0] ?? "";
}

const TABLE = "beta_contact_access_log";

describe("127_beta_crm_access_log migration shape (ADR-102 UI phase)", () => {
  // Unwrapped: a missing migration throws at module load (RED), per the 079/126
  // shape-test convention.
  const raw = readFileSync(MIGRATION, "utf8");
  const sql = stripComments(raw);
  const downSql = stripComments(readFileSync(DOWN, "utf8"));

  describe("preconditions + table + FK", () => {
    it("guards that beta_contacts (126) and is_jti_denied_from_jwt (068) exist first", () => {
      expect(sql).toMatch(/to_regclass\('public\.beta_contacts'\) IS NULL/i);
      expect(sql).toMatch(/to_regprocedure\('public\.is_jti_denied_from_jwt\(\)'\) IS NULL/i);
    });

    it(`creates ${TABLE}`, () => {
      expect(sql).toMatch(new RegExp(`CREATE TABLE IF NOT EXISTS public\\.${TABLE}\\b`, "i"));
    });

    it("carries the composite FK (contact_id, user_id) -> beta_contacts(id, user_id) ON DELETE CASCADE (auto Art. 17 erase)", () => {
      const block = sql.match(new RegExp(`CREATE TABLE IF NOT EXISTS public\\.${TABLE}[\\s\\S]*?\\);`, "i"))?.[0] ?? "";
      expect(block).not.toBe("");
      expect(block).toMatch(
        /FOREIGN KEY \(contact_id, user_id\)\s*REFERENCES public\.beta_contacts \(id, user_id\)\s+ON DELETE CASCADE/i,
      );
    });

    it("holds only id/user_id/contact_id/accessed_at — NO note body column", () => {
      const block = sql.match(new RegExp(`CREATE TABLE IF NOT EXISTS public\\.${TABLE}[\\s\\S]*?\\);`, "i"))?.[0] ?? "";
      expect(block).toMatch(/\baccessed_at\b\s+timestamptz/i);
      expect(block).not.toMatch(/\bbody\b/i);
      expect(block).not.toMatch(/\blens\b/i);
    });
  });

  describe("RLS posture — SELECT-owner-only + jti-deny RESTRICTIVE; writes REVOKEd", () => {
    it("enables RLS", () => {
      expect(sql).toMatch(new RegExp(`ALTER TABLE public\\.${TABLE}\\s+ENABLE ROW LEVEL SECURITY`, "i"));
    });

    it("REVOKEs INSERT/UPDATE/DELETE from PUBLIC, anon, authenticated AND service_role", () => {
      expect(sql).toMatch(
        new RegExp(
          `REVOKE INSERT, UPDATE, DELETE ON TABLE public\\.${TABLE}\\s+FROM PUBLIC, anon, authenticated, service_role`,
          "i",
        ),
      );
    });

    it("has exactly one FOR SELECT owner policy (USING user_id = auth.uid())", () => {
      const selects = [
        ...sql.matchAll(
          new RegExp(
            `CREATE POLICY \\w+ ON public\\.${TABLE}\\s+FOR SELECT TO authenticated\\s+USING \\(user_id = auth\\.uid\\(\\)\\)`,
            "gi",
          ),
        ),
      ];
      expect(selects.length).toBe(1);
    });

    it("has NO permissive owner write policy (only the RESTRICTIVE FOR ALL jti policy)", () => {
      const policies = [...sql.matchAll(/CREATE POLICY[\s\S]*?;/gi)].map((m) => m[0]);
      // 1 SELECT owner + 1 RESTRICTIVE jti = 2 policies.
      expect(policies.length).toBe(2);
      for (const p of policies) {
        expect(p).not.toMatch(/FOR (INSERT|UPDATE|DELETE)\b/i);
        if (/FOR ALL\b/i.test(p)) expect(p).toMatch(/AS RESTRICTIVE/i);
      }
      expect(policies.filter((p) => /FOR ALL\b/i.test(p)).length).toBe(1);
    });

    it("adds the RESTRICTIVE jti_not_denied policy (068/126 shape)", () => {
      expect(sql).toMatch(
        new RegExp(
          `CREATE POLICY ${TABLE}_jti_not_denied ON public\\.${TABLE}\\s+AS RESTRICTIVE FOR ALL TO authenticated\\s+USING \\(NOT public\\.is_jti_denied_from_jwt\\(\\)\\)`,
          "i",
        ),
      );
    });
  });

  describe("append-only invariant + index safety", () => {
    it("no UPDATE/DELETE statement targets the append-only access log", () => {
      expect(sql).not.toMatch(new RegExp(`UPDATE public\\.${TABLE}\\b`, "i"));
      expect(sql).not.toMatch(new RegExp(`DELETE FROM public\\.${TABLE}\\b`, "i"));
    });

    it("never uses CREATE INDEX CONCURRENTLY (runs inside the migration txn)", () => {
      expect(sql).not.toMatch(/CREATE INDEX CONCURRENTLY/i);
    });
  });

  describe("crm_get_contact_detail — atomic fail-closed read + audit", () => {
    const body = fnBody(sql, "crm_get_contact_detail");

    it("exists, is SECURITY DEFINER, RETURNS jsonb, pins search_path", () => {
      expect(body).not.toBe("");
      expect(body).toMatch(/RETURNS jsonb/i);
      expect(body).toMatch(/SECURITY DEFINER/i);
      expect(body).toMatch(/SET search_path = public, pg_temp/i);
    });

    it("is NOT marked STABLE/IMMUTABLE (must stay VOLATILE — it INSERTs the audit row)", () => {
      expect(body).not.toMatch(/\bSTABLE\b/i);
      expect(body).not.toMatch(/\bIMMUTABLE\b/i);
    });

    it("opens with auth.uid() IS NULL -> 42501", () => {
      expect(body).toMatch(/IF v_uid IS NULL THEN[\s\S]*?ERRCODE = '42501'/i);
    });

    it("scopes the head read on user_id = auth.uid() and raises the SAME 42501 on missing/foreign (no oracle)", () => {
      expect(body).toMatch(/FROM public\.beta_contacts\s+WHERE id = p_contact_id AND user_id = v_uid/i);
      expect(body).toMatch(/IF v_contact IS NULL THEN[\s\S]*?ERRCODE = '42501'/i);
    });

    it("INSERTs the access-log row BEFORE building/returning the payload (fail-closed ordering)", () => {
      const insertPos = body.search(/INSERT INTO public\.beta_contact_access_log/i);
      const returnPos = body.search(/RETURN jsonb_build_object/i);
      expect(insertPos).toBeGreaterThanOrEqual(0);
      expect(returnPos).toBeGreaterThan(insertPos);
      // The audit INSERT must sit after the ownership gate (so a foreign read
      // never writes an audit row) but before the RETURN.
      const gatePos = body.search(/IF v_contact IS NULL THEN/i);
      expect(insertPos).toBeGreaterThan(gatePos);
    });

    it("returns {contact, notes, transitions} jsonb", () => {
      expect(body).toMatch(/'contact',\s*v_contact/i);
      expect(body).toMatch(/'notes',\s*v_notes/i);
      expect(body).toMatch(/'transitions',\s*v_trans/i);
    });

    it("aggregates notes + transitions scoped to owner + contact", () => {
      expect(body).toMatch(/FROM public\.interview_notes\s+WHERE contact_id = p_contact_id AND user_id = v_uid/i);
      expect(body).toMatch(/FROM public\.beta_contact_stage_transitions\s+WHERE contact_id = p_contact_id AND user_id = v_uid/i);
    });

    it("is granted to authenticated and revoked from PUBLIC/anon/service_role", () => {
      expect(sql).toMatch(/REVOKE ALL ON FUNCTION public\.crm_get_contact_detail\(uuid\)\s+FROM PUBLIC, anon, authenticated, service_role/i);
      expect(sql).toMatch(/GRANT EXECUTE ON FUNCTION public\.crm_get_contact_detail\(uuid\)\s+TO authenticated/i);
    });
  });

  describe("down-file", () => {
    it("drops the RPC and the table (CASCADE)", () => {
      expect(downSql).toMatch(/DROP FUNCTION IF EXISTS public\.crm_get_contact_detail\(uuid\)/i);
      expect(downSql).toMatch(new RegExp(`DROP TABLE IF EXISTS public\\.${TABLE} CASCADE`, "i"));
    });

    it("does NOT drop any mig-126 object (127 is additive over 126)", () => {
      expect(downSql).not.toMatch(/DROP TABLE IF EXISTS public\.beta_contacts/i);
      expect(downSql).not.toMatch(/crm_contact_upsert|crm_note_append|crm_erase_contact/i);
    });
  });
});
