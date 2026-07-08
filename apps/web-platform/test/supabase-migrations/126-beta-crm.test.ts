import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import path from "node:path";

// Migration-shape contract for 126_beta_crm.sql (feat-beta-conversation-capture
// #6165, ADR-102). Two tiers, mirroring the 079/102 convention:
//
//   (1) file-parse SHAPE tests (below) — fast, run every CI pass; guard the RLS
//       posture, composite-FK shape, SECURITY-DEFINER authorization pins, PII-
//       safe CHECK design, append-only invariant, and retention idiom against a
//       later edit silently weakening them.
//   (2) a gated BEHAVIORAL block (describe.skip at the bottom) — the live-DB
//       proofs (empty-lens reject, cross-tenant deny with a positive owner-read
//       control, composite-FK mis-stamp reject, CASCADE erasure, concurrent
//       stage change). Activates with TENANT_INTEGRATION_TEST=1 + a live Doppler
//       DATABASE_URL_POOLER on a DEDICATED dev Supabase project
//       (hr-dev-prd-distinct-supabase-projects; NEVER the shared dev pre-merge).
//
// Plan: knowledge-base/project/plans/2026-07-07-feat-beta-conversation-capture-plan.md
// ADR:  knowledge-base/engineering/architecture/decisions/ADR-102-beta-crm-capture-store-per-tenant-owner-private-agent-native.md

const MIGRATION = path.resolve(__dirname, "../../supabase/migrations/126_beta_crm.sql");
const DOWN = path.resolve(__dirname, "../../supabase/migrations/126_beta_crm.down.sql");

const stripComments = (sql: string) => sql.replace(/--[^\n]*/g, "");

// Canonical pipeline stage set — the single source of truth is
// server/crm/stage-probability.ts (asserted equal in crm-tools.test.ts AC8).
const STAGE_ENUM = [
  "new",
  "contacted",
  "qualified",
  "evaluating",
  "committed",
  "closed_won",
  "closed_lost",
];

const HISTORY_TABLES = ["interview_notes", "beta_contact_stage_transitions"];
const ALL_TABLES = ["beta_contacts", ...HISTORY_TABLES];

// Extract a single CREATE FUNCTION ... $$; body by name.
function fnBody(sql: string, name: string): string {
  const re = new RegExp(
    `CREATE\\s+(?:OR\\s+REPLACE\\s+)?FUNCTION\\s+public\\.${name}\\s*\\([\\s\\S]*?\\$\\$;`,
    "i",
  );
  return sql.match(re)?.[0] ?? "";
}

describe("126_beta_crm migration shape (ADR-102)", () => {
  // Unwrapped: a missing migration throws at module load (RED), per the 079
  // shape-test convention.
  const raw = readFileSync(MIGRATION, "utf8");
  const sql = stripComments(raw);
  const downSql = stripComments(readFileSync(DOWN, "utf8"));

  describe("tables + keys", () => {
    it("creates all three tables", () => {
      for (const t of ALL_TABLES) {
        expect(sql).toMatch(new RegExp(`CREATE TABLE IF NOT EXISTS public\\.${t}\\b`, "i"));
      }
    });

    it("beta_contacts.user_id references public.users(id) ON DELETE CASCADE", () => {
      expect(sql).toMatch(
        /user_id\s+uuid\s+NOT NULL\s+REFERENCES public\.users\(id\)\s+ON DELETE CASCADE/i,
      );
    });

    it("beta_contacts has UNIQUE (id, user_id) — the composite-FK target", () => {
      expect(sql).toMatch(/UNIQUE\s*\(\s*id\s*,\s*user_id\s*\)/i);
    });

    it("both child tables carry the composite FK (contact_id, user_id) -> beta_contacts(id, user_id) ON DELETE CASCADE", () => {
      for (const t of HISTORY_TABLES) {
        const block = sql.match(new RegExp(`CREATE TABLE IF NOT EXISTS public\\.${t}[\\s\\S]*?\\);`, "i"))?.[0] ?? "";
        expect(block).not.toBe("");
        expect(block).toMatch(
          /FOREIGN KEY \(contact_id, user_id\)\s*REFERENCES public\.beta_contacts \(id, user_id\)\s+ON DELETE CASCADE/i,
        );
      }
    });
  });

  describe("PII-safe CHECK design", () => {
    it("interview_notes.lens uses cardinality() (NOT array_length) + subset guard", () => {
      expect(sql).toMatch(/lens\s*<@\s*ARRAY\['sales',\s*'product'\]\s*AND\s*cardinality\(lens\)\s*>=\s*1/i);
      expect(sql).not.toMatch(/array_length\(\s*lens/i);
    });

    it("beta_contacts enforces amount => currency (no amount without a unit)", () => {
      expect(sql).toMatch(/CHECK \(amount IS NULL OR currency IS NOT NULL\)/i);
    });

    it("currency is ISO-4217-shaped; amount_basis is a closed enum", () => {
      expect(sql).toMatch(/currency\s+text\s+NULL\s+CHECK \(currency ~ '\^\[A-Z\]\{3\}\$'\)/i);
      expect(sql).toMatch(/amount_basis IN \('hypothetical_acv', 'committed', 'unknown'\)/i);
    });

    it("every stage-enum list in the file is byte-identical (no internal drift)", () => {
      const lists = [...sql.matchAll(/\(\s*('new'[^)]*'closed_lost')\s*\)/gi)].map((m) =>
        m[1].replace(/\s+/g, " ").trim(),
      );
      // beta_contacts.stage CHECK, to_stage CHECK, upsert validation, set_stage validation.
      expect(lists.length).toBeGreaterThanOrEqual(4);
      expect(new Set(lists).size).toBe(1);
      // And the canonical list equals STAGE_ENUM in order.
      const canonical = lists[0].replace(/'/g, "").split(",").map((s) => s.trim());
      expect(canonical).toEqual(STAGE_ENUM);
    });
  });

  describe("RLS posture — SELECT-owner-only + jti-deny RESTRICTIVE; writes REVOKEd", () => {
    it("enables RLS on all three tables", () => {
      for (const t of ALL_TABLES) {
        expect(sql).toMatch(new RegExp(`ALTER TABLE public\\.${t}\\s+ENABLE ROW LEVEL SECURITY`, "i"));
      }
    });

    it("REVOKEs INSERT/UPDATE/DELETE from PUBLIC, anon, authenticated AND service_role on all three", () => {
      for (const t of ALL_TABLES) {
        expect(sql).toMatch(
          new RegExp(
            `REVOKE INSERT, UPDATE, DELETE ON TABLE public\\.${t}\\s+FROM PUBLIC, anon, authenticated, service_role`,
            "i",
          ),
        );
      }
    });

    it("has exactly one FOR SELECT owner policy per table (USING user_id = auth.uid())", () => {
      for (const t of ALL_TABLES) {
        const selects = [
          ...sql.matchAll(new RegExp(`CREATE POLICY \\w+ ON public\\.${t}\\s+FOR SELECT TO authenticated\\s+USING \\(user_id = auth\\.uid\\(\\)\\)`, "gi")),
        ];
        expect(selects.length).toBe(1);
      }
    });

    it("has NO permissive owner write policy (no FOR INSERT/UPDATE/DELETE; only the RESTRICTIVE FOR ALL jti policy)", () => {
      // Inspect each CREATE POLICY statement in isolation (they contain no
      // internal ';', so lazy-match-to-';' scopes cleanly and avoids catching a
      // `... FOR UPDATE` row-lock inside an RPC body).
      const policies = [...sql.matchAll(/CREATE POLICY[\s\S]*?;/gi)].map((m) => m[0]);
      // 3 SELECT owner + 3 RESTRICTIVE jti = 6 policies.
      expect(policies.length).toBe(6);
      for (const p of policies) {
        // No single-verb write policy.
        expect(p).not.toMatch(/FOR (INSERT|UPDATE|DELETE)\b/i);
        // A FOR ALL policy must be AS RESTRICTIVE (the jti deny), never a
        // permissive owner-write convenience policy.
        if (/FOR ALL\b/i.test(p)) expect(p).toMatch(/AS RESTRICTIVE/i);
      }
      // Exactly the three RESTRICTIVE FOR ALL jti policies.
      expect(policies.filter((p) => /FOR ALL\b/i.test(p)).length).toBe(3);
    });

    it("adds the RESTRICTIVE <table>_jti_not_denied policy on all three (068/077 shape)", () => {
      for (const t of ALL_TABLES) {
        expect(sql).toMatch(
          new RegExp(
            `CREATE POLICY ${t}_jti_not_denied ON public\\.${t}\\s+AS RESTRICTIVE FOR ALL TO authenticated\\s+USING \\(NOT public\\.is_jti_denied_from_jwt\\(\\)\\)`,
            "i",
          ),
        );
      }
    });
  });

  describe("write RPCs — SECURITY DEFINER authorization pins", () => {
    for (const fn of ["crm_contact_upsert", "crm_note_append", "crm_contact_set_stage"]) {
      describe(fn, () => {
        const body = fnBody(sql, fn);
        it("exists, is SECURITY DEFINER, pins search_path", () => {
          expect(body).not.toBe("");
          expect(body).toMatch(/SECURITY DEFINER/i);
          expect(body).toMatch(/SET search_path = public, pg_temp/i);
        });
        it("opens with auth.uid() IS NULL -> 42501", () => {
          expect(body).toMatch(/IF v_uid IS NULL THEN[\s\S]*?ERRCODE = '42501'/i);
        });
        it("locks with FOR UPDATE and rejects missing/foreign row with the same 42501 (no oracle)", () => {
          expect(body).toMatch(/SELECT \* INTO v_row FROM public\.beta_contacts WHERE id = \w+ FOR UPDATE/i);
          expect(body).toMatch(/IF NOT FOUND OR v_row\.user_id <> v_uid THEN[\s\S]*?ERRCODE = '42501'/i);
        });
        it("is granted to authenticated and revoked from PUBLIC/anon/service_role", () => {
          expect(sql).toMatch(new RegExp(`REVOKE ALL ON FUNCTION public\\.${fn}\\([\\s\\S]*?\\)\\s+FROM PUBLIC, anon, authenticated, service_role`, "i"));
          expect(sql).toMatch(new RegExp(`GRANT EXECUTE ON FUNCTION public\\.${fn}\\([\\s\\S]*?\\)\\s+TO authenticated`, "i"));
        });
      });
    }

    it("crm_contact_upsert stamps child user_id from auth.uid()/parent, never a param", () => {
      const body = fnBody(sql, "crm_contact_upsert");
      // child inserts reference v_uid, and there is no p_user_id parameter.
      expect(body).not.toMatch(/p_user_id/i);
      expect(body).toMatch(/INSERT INTO public\.beta_contact_stage_transitions \(contact_id, user_id, from_stage, to_stage\)/i);
    });

    it("crm_erase_contact is service_role-ONLY (no auth.uid() caller)", () => {
      const body = fnBody(sql, "crm_erase_contact");
      expect(body).toMatch(/SECURITY DEFINER/i);
      expect(body).toMatch(/DELETE FROM public\.beta_contacts WHERE id = p_contact_id/i);
      expect(sql).toMatch(/REVOKE ALL ON FUNCTION public\.crm_erase_contact\(uuid\)\s+FROM PUBLIC, anon, authenticated, service_role/i);
      expect(sql).toMatch(/GRANT EXECUTE ON FUNCTION public\.crm_erase_contact\(uuid\)\s+TO service_role/i);
      // NOT authenticated-callable.
      expect(sql).not.toMatch(/GRANT EXECUTE ON FUNCTION public\.crm_erase_contact\(uuid\)\s+TO authenticated/i);
    });
  });

  describe("append-only invariant + index safety", () => {
    it("no UPDATE/DELETE statement targets the append-only history tables", () => {
      for (const t of HISTORY_TABLES) {
        expect(sql).not.toMatch(new RegExp(`UPDATE public\\.${t}\\b`, "i"));
        expect(sql).not.toMatch(new RegExp(`DELETE FROM public\\.${t}\\b`, "i"));
      }
    });

    it("never uses CREATE INDEX CONCURRENTLY (runs inside the migration txn)", () => {
      expect(sql).not.toMatch(/CREATE INDEX CONCURRENTLY/i);
    });

    it("beta_contacts has a BEFORE UPDATE updated_at trigger (search_path pinned)", () => {
      expect(fnBody(sql, "beta_contacts_set_updated_at")).toMatch(/SET search_path = public, pg_temp/i);
      expect(sql).toMatch(/CREATE TRIGGER beta_contacts_updated_at\s+BEFORE UPDATE ON public\.beta_contacts/i);
    });
  });

  describe("retention (pg_cron) + down-file", () => {
    it("schedules a 24-month sweep on COALESCE(last_contact, created_at) with a undefined_table guard", () => {
      expect(sql).toMatch(/cron\.schedule\(\s*'beta_contacts_retention'/i);
      expect(sql).toMatch(/COALESCE\(last_contact, created_at::date\) < now\(\)::date - interval '24 months'/i);
      expect(sql).toMatch(/WHEN undefined_table THEN/i);
    });

    it("down-file unschedules cron, drops all four functions + three tables", () => {
      expect(downSql).toMatch(/cron\.unschedule\('beta_contacts_retention'\)/i);
      for (const fn of ["crm_erase_contact", "crm_contact_set_stage", "crm_note_append", "crm_contact_upsert", "beta_contacts_set_updated_at"]) {
        expect(downSql).toMatch(new RegExp(`DROP FUNCTION IF EXISTS public\\.${fn}`, "i"));
      }
      for (const t of ALL_TABLES) {
        expect(downSql).toMatch(new RegExp(`DROP TABLE IF EXISTS public\\.${t} CASCADE`, "i"));
      }
    });
  });
});

// ---------------------------------------------------------------------
// Behavioral integration proofs — skipped until applied to a DEDICATED dev
// Supabase project with TENANT_INTEGRATION_TEST=1 + a live Doppler
// DATABASE_URL_POOLER (hr-dev-prd-distinct-supabase-projects; NEVER the shared
// dev pre-merge). Kept concrete so wiring a role-switched pg client suffices.
//
// Fixtures (synthesized, two tenants A & B; valid UUIDs):
//   userA, userB in public.users; contactA owned by A.
// ---------------------------------------------------------------------
describe.skip("126 beta-crm — behavioral (applied dev project)", () => {
  it("rejects an empty-lens note live ('{}' fails cardinality; array_length would have passed)", () => {
    //   SET request.jwt.claim.sub = userA;
    //   await expect(pg.query("SELECT public.crm_note_append($1,$2,$3)", [contactA, "hi", []]))
    //     .rejects.toThrow(/lens must be a non-empty subset/);
  });

  it("cross-tenant read deny with a positive owner-read control (policy is load-bearing)", () => {
    //   as A: SELECT ... WHERE id = contactA -> 1 row (positive control)
    //   as B: SELECT ... WHERE id = contactA -> 0 rows
    //   Dropping beta_contacts_owner_select must break the positive control (A -> 0).
  });

  it("cross-tenant write isolation: B's upsert/set_stage/note_append vs A's contact raises 42501 and leaves A unchanged", () => {
    //   as B: crm_contact_upsert(p_id := contactA, p_name := 'x') -> 42501 not authorized
    //   as B: crm_contact_set_stage(contactA, 'qualified')       -> 42501
    //   as B: crm_note_append(contactA, 'x', ARRAY['sales'])     -> 42501
    //   then as A: contactA.name/stage unchanged.
  });

  it("composite-FK mis-stamp reject: a child with a user_id != parent's owner fails the FK", () => {
    //   INSERT INTO interview_notes(contact_id, user_id, ...) VALUES (contactA, userB, ...) -> FK violation
  });

  it("stage transitions: INSERT-at-non-default + each change appends exactly one row; a stage-omitting partial upsert appends none", () => {
    //   crm_contact_upsert(p_stage := 'qualified') on a fresh contact -> 1 transition (NULL -> qualified)
    //   crm_contact_upsert(p_id := c, p_name := 'x')                  -> 0 new transitions, stage intact
    //   concurrent double set_stage via FOR UPDATE -> two consecutive rows, not two claiming the same from_stage
  });

  it("Art. 17: crm_erase_contact + account-delete CASCADE both empty all three tables", () => {
    //   service-role crm_erase_contact(contactA) -> notes + transitions gone
    //   auth.admin.deleteUser(userA) -> public.users CASCADE empties A's rows in all three
  });
});
