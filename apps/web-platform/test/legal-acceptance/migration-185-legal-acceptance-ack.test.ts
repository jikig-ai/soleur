import { beforeEach, describe, expect, it } from "vitest";
import { existsSync, readFileSync } from "node:fs";
import path from "node:path";
import { TABLE_GRANT_REGISTRY } from "../rls-fuzz/table-grants";

// Static shape tests for migration 185 (#12011 PR-D, ADR-319): the acknowledgement table behind the
// `row_without_event` reconciliation and its two service-role RPCs. The BEHAVIOURAL proof runs against a real database
// in test/server/legal-acceptance.tenant-isolation.test.ts (collected by tenant-integration.yml) and
// supabase/verify/185_legal_acceptance_ack.sql. This file is the cheap backstop: it strips comments, reads the SQL as
// text and checks the properties Guard 3 names (rows 7 and 8 are the two mutation rows owned here). The MUTATIONS block
// applies each static mutant to the RAW migration text and asserts the checker goes RED; a checker that cannot go red is
// vacuous. A lexical check cannot prove a function's logic: the DB-backed test is the proof, this is the tripwire.

const DIR = path.join(__dirname, "../../supabase");
const UP = path.join(DIR, "migrations/185_legal_acceptance_ack.sql");
const DOWN = path.join(DIR, "migrations/185_legal_acceptance_ack.down.sql");
const VERIFY = path.join(DIR, "verify/185_legal_acceptance_ack.sql");

const read = (p: string): string => (existsSync(p) ? readFileSync(p, "utf8") : "");
const rawUp = read(UP);
const norm = (s: string) => s.replace(/\s+/g, " ").trim();

/** Remove line and block comments; single-quoted literals (with '' escapes) are copied through intact. */
export function stripSql(src: string): string {
  let out = "";
  let i = 0;
  const n = src.length;
  while (i < n) {
    const two = src.slice(i, i + 2);
    if (two === "--") {
      while (i < n && src[i] !== "\n") i++;
      continue;
    }
    if (two === "/*") {
      const end = src.indexOf("*/", i + 2);
      i = end < 0 ? n : end + 2;
      out += " ";
      continue;
    }
    if (src[i] === "'") {
      let j = i + 1;
      while (j < n) {
        if (src[j] === "'") {
          if (src[j + 1] === "'") {
            j += 2;
            continue;
          }
          break;
        }
        j++;
      }
      out += src.slice(i, j + 1);
      i = j + 1;
      continue;
    }
    out += src[i];
    i++;
  }
  return out;
}

/** Body of one function: from `CREATE OR REPLACE FUNCTION public.<name>(` to the closing `$$;`. Empty when absent. */
export function fnBody(stripped: string, name: string): string {
  const start = stripped.search(new RegExp(`CREATE OR REPLACE FUNCTION public\\.${name}\\(`, "i"));
  if (start < 0) return "";
  const open = stripped.indexOf("$$", start);
  if (open < 0) return "";
  const close = stripped.indexOf("$$;", open + 2);
  return close < 0 ? "" : norm(stripped.slice(start, close + 3));
}

/** A statement (REVOKE / GRANT / CREATE POLICY) from its keyword to the next `;`, normalised. */
function statements(stripped: string, head: RegExp): string[] {
  return stripped
    .split(";")
    .map(norm)
    .filter((s) => head.test(s));
}

const FNS = ["ack_legal_acceptance", "legal_acceptance_ack_state"] as const;
const SHAPE_KEY = "p_key IS NULL OR p_key !~ '^[a-z0-9][a-z0-9-]{0,62}$'";
const SHAPE_HASH = "p_text_hash IS NULL OR p_text_hash !~ '^[0-9a-f]{64}$'";

/** Every problem the checker finds in one candidate migration text. Empty means the shape holds. */
export function shapeProblems(sqlText: string): string[] {
  const p: string[] = [];
  const s = stripSql(sqlText);
  const flat = norm(s);

  // Precondition: the record table exists.
  if (!/DO \$\$ BEGIN IF to_regclass\('public\.legal_acceptance'\) IS NULL THEN RAISE EXCEPTION/i.test(flat)) p.push("precondition DO block on public.legal_acceptance missing");

  // Annotations (kept in comments, so read from the RAW text).
  if (!/-- LAWFUL_BASIS: legitimate_interests \(Art\. 6\(1\)\(f\)\)/.test(sqlText)) p.push("LAWFUL_BASIS annotation missing");
  if (!/-- RETENTION:/.test(sqlText)) p.push("RETENTION annotation missing");
  if (!/-- DSAR:/.test(sqlText)) p.push("DSAR annotation missing");
  if (!/-- soleur:no-data-api: public\.legal_acceptance_ack\b/.test(sqlText)) p.push("soleur:no-data-api comment missing");

  // The ack table: an acceptance id and a time ONLY (Guard 3 row 7), no foreign key, RLS on, nothing granted.
  const tbl = /CREATE TABLE IF NOT EXISTS public\.legal_acceptance_ack \(([\s\S]*?)\n\);/i.exec(s)?.[1] ?? "";
  if (!tbl) p.push("legal_acceptance_ack table missing");
  const cols = [...tbl.matchAll(/^\s{2}([a-z_]+)\s+(?:uuid|text|timestamptz|integer|boolean)\b/gm)].map((m) => m[1]);
  if (JSON.stringify(cols) !== JSON.stringify(["acceptance_id", "acked_at"])) p.push(`the ack table must carry exactly acceptance_id and acked_at (found: ${cols.join(", ")})`);
  if (!/acceptance_id\s+uuid\s+PRIMARY KEY/i.test(tbl)) p.push("acceptance_id must be the primary key");
  if (!/acked_at\s+timestamptz\s+NOT NULL DEFAULT now\(\)/i.test(tbl)) p.push("acked_at must be timestamptz NOT NULL DEFAULT now()");
  if (/REFERENCES|FOREIGN KEY/i.test(tbl) || /ALTER TABLE [^;]*(REFERENCES|FOREIGN KEY)/i.test(flat)) p.push("the ack table must carry no foreign key");
  if (/founder_id|user_id/i.test(tbl)) p.push("the ack table must not carry a founder id");
  if (!/ALTER TABLE public\.legal_acceptance_ack ENABLE ROW LEVEL SECURITY/i.test(flat)) p.push("RLS not enabled on legal_acceptance_ack");
  if (statements(s, /^CREATE POLICY/i).length !== 0) p.push("the ack table must have no policy (RPC-only)");
  if (!/REVOKE ALL ON TABLE public\.legal_acceptance_ack FROM PUBLIC, anon, authenticated, service_role/i.test(flat)) p.push("legal_acceptance_ack: REVOKE ALL missing");
  if (statements(s, /^GRANT .* ON (TABLE )?(public\.)?legal_acceptance_ack\b/i).length !== 0) p.push("no table grant on legal_acceptance_ack is allowed");
  if (/GRANT [^;]* ON ALL TABLES/i.test(flat)) p.push("no blanket ALL TABLES grant may appear in this migration");
  if (/GRANT [^;]*\b(authenticated|anon|service_role)\b[^;]* TO /i.test(flat.replace(/GRANT EXECUTE ON FUNCTION [^;]* TO service_role/gi, ""))) {
    p.push("unexpected GRANT (only EXECUTE on the two functions to service_role is allowed)");
  }

  // Both functions: definer, pinned search_path, service_role only, refuse a user identity, validate arguments.
  const grantFor = (f: string) => statements(s, new RegExp(`^GRANT EXECUTE ON FUNCTION public\\.${f}\\(`, "i")).map((x) => /TO (\w+)$/i.exec(x)?.[1]);
  for (const f of FNS) {
    const b = fnBody(s, f);
    if (!b) {
      p.push(`${f} missing`);
      continue;
    }
    if (!/\(p_founder_id uuid, p_key text, p_text_hash text\)/i.test(b)) p.push(`${f}: signature must be (p_founder_id uuid, p_key text, p_text_hash text)`);
    if (!/RETURNS jsonb/i.test(b)) p.push(`${f}: must return jsonb`);
    if (!/SECURITY DEFINER SET search_path = public, pg_temp/i.test(b)) p.push(`${f}: search_path not pinned`);
    if (!/IF auth\.uid\(\) IS NOT NULL THEN RAISE EXCEPTION '[^']*' USING ERRCODE = '42501'/i.test(b)) p.push(`${f}: must refuse a user identity with 42501`);
    if (!b.includes(`p_founder_id IS NULL OR ${SHAPE_KEY} OR ${SHAPE_HASH}`)) p.push(`${f}: must validate p_founder_id, p_key and p_text_hash with the 184 shape predicates`);
    if (!/FROM ONLY public\.legal_acceptance\b/i.test(b)) p.push(`${f}: must read ONLY public.legal_acceptance`);
    if (JSON.stringify(grantFor(f)) !== JSON.stringify(["service_role"])) p.push(`${f}: EXECUTE must be service_role only`);
    if (!new RegExp(`REVOKE ALL ON FUNCTION public\\.${f}\\(uuid, text, text\\) FROM PUBLIC, anon, authenticated, service_role`, "i").test(flat)) p.push(`${f}: REVOKE ALL missing`);
    // Guard 3 row 8: neither function opens the write door of legal_acceptance, and neither writes it.
    if (/set_config|app\.legal_acceptance_rpc/i.test(b)) p.push(`${f}: must not set or name the write-door setting of legal_acceptance`);
    if (/\b(INSERT\s+INTO|UPDATE|DELETE\s+FROM)\s+(ONLY\s+)?public\.legal_acceptance\b(?!_ack)/i.test(b)) p.push(`${f}: must not write legal_acceptance`);
  }

  // ack: insert into the ack table only, idempotent, answers acked / not_found.
  const ack = fnBody(s, "ack_legal_acceptance");
  if (!/INSERT INTO public\.legal_acceptance_ack \(acceptance_id\) VALUES \(v_id\) ON CONFLICT \(acceptance_id\) DO NOTHING/i.test(ack)) p.push("ack: must insert the acceptance id with ON CONFLICT DO NOTHING");
  if (!/'outcome', 'not_found'/i.test(ack) || !/'outcome', 'acked'/i.test(ack)) p.push("ack: must answer acked or not_found");
  if (!/IF NOT FOUND THEN RETURN jsonb_build_object\('outcome', 'not_found'\)/i.test(ack)) p.push("ack: a missing acceptance row must answer not_found before any insert");

  // ack_state: read-only, age computed by the database.
  const st = fnBody(s, "legal_acceptance_ack_state");
  if (/\b(INSERT|UPDATE|DELETE)\b/i.test(st)) p.push("ack_state must be read-only");
  if (!/\bSTABLE\b/i.test(st)) p.push("ack_state must be STABLE");
  if (!/'outcome', 'none'/i.test(st) || !/'outcome', 'row'/i.test(st) || !/'acked'/i.test(st) || !/'age_seconds'/i.test(st)) p.push("ack_state: must answer none or row with acked and age_seconds");
  if (!/now\(\) - [a-z_.]*created_at/i.test(st)) p.push("ack_state: age must be computed in the database from now()");

  // Nothing later in the file may undo what the earlier statements set up.
  if (/DISABLE ROW LEVEL SECURITY/i.test(flat)) p.push("no statement may disable row level security");
  if (/ALTER TABLE [^;]*public\.legal_acceptance\b(?!_ack)/i.test(flat)) p.push("no statement may alter public.legal_acceptance");
  if (/UPDATE public\.legal_acceptance\b(?!_ack)|DELETE FROM public\.legal_acceptance\b(?!_ack)|INSERT INTO public\.legal_acceptance\b(?!_ack)/i.test(flat)) p.push("no statement may write legal_acceptance");
  if (/anonymise_approval_request/i.test(flat)) p.push("migration must not touch anonymise_approval_request");
  return p;
}

beforeEach(() => {
  expect.hasAssertions();
});

describe("migration 185 files", () => {
  it("up, down and verify files exist", () => {
    expect(existsSync(UP)).toBe(true);
    expect(existsSync(DOWN)).toBe(true);
    expect(existsSync(VERIFY)).toBe(true);
  });

  it("the up migration has the Guard 3 shape", () => {
    expect(shapeProblems(rawUp)).toEqual([]);
  });

  it("the ack table is classified INTERNAL in the rls-fuzz grant registry (the DB-backed parity gate in rls-authz-fuzz.yml reds on an unclassified relation; this is the cheap tripwire)", () => {
    const entry = TABLE_GRANT_REGISTRY.get("legal_acceptance_ack");
    expect(entry?.kind).toBe("INTERNAL");
    expect(entry && "reason" in entry ? entry.reason : "").toMatch(/migration 185/);
  });

  it("the down file locks the ack table, refuses while rows exist, and does both before dropping anything", () => {
    const d = norm(stripSql(read(DOWN)));
    const lock = d.search(/LOCK TABLE public\.legal_acceptance_ack IN ACCESS EXCLUSIVE MODE/i);
    const refuse = d.search(/IF EXISTS \(SELECT 1 FROM public\.legal_acceptance_ack\) THEN RAISE EXCEPTION/i);
    const firstDrop = d.search(/DROP (TABLE|FUNCTION)/i);
    expect(lock).toBeGreaterThanOrEqual(0);
    expect(refuse).toBeGreaterThan(lock);
    expect(firstDrop).toBeGreaterThan(refuse);
  });

  it("the down file is one transaction: BEGIN first, COMMIT last, so the lock holds through the DROPs", () => {
    const d = norm(stripSql(read(DOWN)));
    expect(d).toMatch(/^BEGIN;/);
    expect(d).toMatch(/COMMIT;$/);
    expect(d.search(/DROP (TABLE|FUNCTION)/i)).toBeGreaterThan(d.search(/LOCK TABLE/i));
    expect(d.lastIndexOf("COMMIT;")).toBeGreaterThan(d.lastIndexOf("DROP TABLE"));
    expect(d.match(/\bBEGIN;/g)).toHaveLength(1); // the plpgsql BEGIN has no semicolon directly after it
  });

  it("the down file's header says to apply it with psql -v ON_ERROR_STOP=1 -f (a refusal must exit nonzero)", () => {
    const header = read(DOWN).split("\n").filter((l) => l.startsWith("--")).join(" ");
    expect(header).toMatch(/psql -v ON_ERROR_STOP=1 -f/);
    expect(header).toMatch(/one at a time/);
  });

  it("the down file drops the CURRENT signatures and never touches the 184 objects", () => {
    const d = norm(stripSql(read(DOWN)));
    for (const sig of ["ack_legal_acceptance(uuid, text, text)", "legal_acceptance_ack_state(uuid, text, text)"]) {
      expect(d).toContain(`DROP FUNCTION IF EXISTS public.${sig}`);
    }
    expect(d).toContain("DROP TABLE IF EXISTS public.legal_acceptance_ack");
    expect(d).not.toMatch(/DROP (TABLE|FUNCTION)[^;]*\blegal_acceptance\b(?!_ack)/i);
  });

  it("the verify file asserts the live catalog with a bad column", () => {
    const v = read(VERIFY);
    expect(v).toMatch(/legal_acceptance_ack_rls_enabled/);
    expect(v).toMatch(/legal_acceptance_ack_no_foreign_key/);
    expect(v).toMatch(/legal_acceptance_ack_columns_are_exactly_id_and_time/);
    expect(v).toMatch(/AS bad|::int/);
  });

  it("the verify file fails on a leftover overload and on EXECUTE for anon, authenticated or PUBLIC on any function of either name", () => {
    const v = norm(stripSql(read(VERIFY)));
    expect(v).toMatch(/'ack_functions_have_no_other_overloads'/);
    expect(v).toMatch(/p\.proname IN \('ack_legal_acceptance', 'legal_acceptance_ack_state'\) AND p\.oid NOT IN/);
    expect(v).toMatch(/'ack_functions_no_execute_for_anon_authenticated_or_public'/);
    expect(v).toMatch(/has_function_privilege\('anon', p\.oid, 'EXECUTE'\)/);
    expect(v).toMatch(/has_function_privilege\('authenticated', p\.oid, 'EXECUTE'\)/);
    expect(v).toMatch(/a\.grantee = 0 AND a\.privilege_type = 'EXECUTE'/);
    expect(v).toMatch(/acldefault\('f', p\.proowner\)/);
  });
});

describe("MUTATIONS: each static mutant of the migration is caught", () => {
  const mutate = (re: RegExp | string, to: string): string => {
    const out = rawUp.replace(re, to);
    expect(out, `mutation did not land: ${String(re)}`).not.toBe(rawUp);
    return out;
  };

  it("control: the unmutated migration has no problems (a red baseline voids every row)", () => {
    expect(shapeProblems(rawUp)).toEqual([]);
  });

  const rows: Array<[string, () => string, RegExp]> = [
    // Guard 3 row 7: the ack carries an acceptance id and a time only.
    ["7 add a founder id to the ack table", () => mutate(/(acceptance_id\s+uuid\s+PRIMARY KEY,)/, "$1\n  founder_id     uuid        NOT NULL,"), /exactly acceptance_id and acked_at|founder id/],
    ["7b add a decision field to the ack table", () => mutate(/(acked_at\s+timestamptz\s+NOT NULL DEFAULT now\(\))/, "$1,\n  choice         text"), /exactly acceptance_id and acked_at/],
    ["7c add a foreign key to the ack table", () => mutate(/acceptance_id\s+uuid\s+PRIMARY KEY/, "acceptance_id uuid PRIMARY KEY REFERENCES public.legal_acceptance (id)"), /no foreign key/],
    // Guard 3 row 8: the ack function must not open the write door.
    ["8 let the ack function set the write-door setting", () => mutate(/(CREATE OR REPLACE FUNCTION public\.ack_legal_acceptance\([\s\S]*?BEGIN)/, "$1 PERFORM set_config('app.legal_acceptance_rpc', 'on', true);"), /write-door setting/],
    ["8b let the ack-state function set the write-door setting", () => mutate(/(CREATE OR REPLACE FUNCTION public\.legal_acceptance_ack_state\([\s\S]*?BEGIN)/, "$1 PERFORM set_config('app.legal_acceptance_rpc', 'on', true);"), /write-door setting/],
    ["8c let the ack function write the record table", () => mutate(/(CREATE OR REPLACE FUNCTION public\.ack_legal_acceptance\([\s\S]*?BEGIN)/, "$1 UPDATE public.legal_acceptance SET row_hash = row_hash;"), /must not write legal_acceptance/],
    // Table exposure.
    ["9 grant the ack table to an api role", () => rawUp + "\nGRANT SELECT ON TABLE public.legal_acceptance_ack TO authenticated;\n", /no table grant|unexpected GRANT/],
    ["9b add a policy to the ack table", () => rawUp + "\nCREATE POLICY ack_read ON public.legal_acceptance_ack FOR SELECT TO authenticated USING (true);\n", /no policy/],
    ["9c drop RLS from the ack table", () => mutate(/ALTER TABLE public\.legal_acceptance_ack ENABLE ROW LEVEL SECURITY/, "-- removed"), /RLS not enabled/],
    ["9d drop the table REVOKE", () => mutate(/REVOKE ALL ON TABLE public\.legal_acceptance_ack FROM PUBLIC, anon, authenticated, service_role/, "-- removed"), /REVOKE ALL missing/],
    ["9e append a blanket grant", () => rawUp + "\nGRANT ALL ON ALL TABLES IN SCHEMA public TO service_role;\n", /ALL TABLES/],
    // Function hardening.
    ["10 drop the search_path pin from ack", () => mutate(/(FUNCTION public\.ack_legal_acceptance\([\s\S]*?)SET search_path = public, pg_temp/, "$1"), /ack_legal_acceptance: search_path not pinned/],
    ["10b drop the search_path pin from ack_state", () => mutate(/(FUNCTION public\.legal_acceptance_ack_state\([\s\S]*?)SET search_path = public, pg_temp/, "$1"), /legal_acceptance_ack_state: search_path not pinned/],
    ["11 let ack accept a user identity", () => mutate(/(FUNCTION public\.ack_legal_acceptance\([\s\S]*?)IF auth\.uid\(\) IS NOT NULL THEN/, "$1IF false THEN"), /ack_legal_acceptance: must refuse a user identity/],
    ["11b let ack_state accept a user identity", () => mutate(/(FUNCTION public\.legal_acceptance_ack_state\([\s\S]*?)IF auth\.uid\(\) IS NOT NULL THEN/, "$1IF false THEN"), /legal_acceptance_ack_state: must refuse a user identity/],
    ["12 let ack skip the hash validation", () => mutate(/(FUNCTION public\.ack_legal_acceptance\([\s\S]*?)OR p_text_hash IS NULL OR p_text_hash !~ '\^\[0-9a-f\]\{64\}\$'/, "$1"), /ack_legal_acceptance: must validate/],
    ["12b let ack_state skip the key validation", () => mutate(/(FUNCTION public\.legal_acceptance_ack_state\([\s\S]*?)OR p_key IS NULL OR p_key !~ '\^\[a-z0-9\]\[a-z0-9-\]\{0,62\}\$'/, "$1"), /legal_acceptance_ack_state: must validate/],
    ["13 grant EXECUTE on ack to authenticated", () => mutate(/(GRANT EXECUTE ON FUNCTION public\.ack_legal_acceptance\(uuid, text, text\)\s+TO) service_role/, "$1 authenticated"), /ack_legal_acceptance: EXECUTE must be service_role only/],
    ["13b grant EXECUTE on ack_state to anon as well", () => rawUp + "\nGRANT EXECUTE ON FUNCTION public.legal_acceptance_ack_state(uuid, text, text) TO anon;\n", /EXECUTE must be service_role only|unexpected GRANT/],
    ["14 ack acknowledges a row that does not exist", () => mutate(/IF NOT FOUND THEN\s+RETURN jsonb_build_object\('outcome', 'not_found'\);/, "IF false THEN RETURN jsonb_build_object('outcome', 'not_found');"), /not_found before any insert/],
    ["15 ack overwrites the first ack time", () => mutate(/ON CONFLICT \(acceptance_id\) DO NOTHING/, "ON CONFLICT (acceptance_id) DO UPDATE SET acked_at = now()"), /ON CONFLICT DO NOTHING/],
    ["16 ack_state takes the age from a caller-supplied time", () => mutate(/now\(\) - v_row\.created_at/, "now() - now()"), /age must be computed in the database/],
    ["17 ack_state writes", () => mutate(/(CREATE OR REPLACE FUNCTION public\.legal_acceptance_ack_state\([\s\S]*?BEGIN)/, "$1 INSERT INTO public.legal_acceptance_ack (acceptance_id) VALUES (gen_random_uuid());"), /ack_state must be read-only/],
    ["18 read the record table through its children", () => mutate(/(FUNCTION public\.legal_acceptance_ack_state\([\s\S]*?)FROM ONLY public\.legal_acceptance/, "$1FROM public.legal_acceptance"), /must read ONLY/],
    ["19 touch the record table's guard", () => rawUp + "\nALTER TABLE public.legal_acceptance DISABLE TRIGGER legal_acceptance_guard;\n", /no statement may alter public\.legal_acceptance/],
    ["20 add the ack table to the erasure scrub", () => rawUp + "\nSELECT public.anonymise_approval_request(gen_random_uuid());\nDELETE FROM public.legal_acceptance_ack;\n", /anonymise_approval_request/],
    ["21 drop the lawful-basis annotation", () => mutate(/-- LAWFUL_BASIS:/, "-- BASIS:"), /LAWFUL_BASIS/],
    ["22 drop the retention annotation", () => mutate(/-- RETENTION:/, "-- KEPT:"), /RETENTION/],
    ["23 drop the precondition", () => mutate(/to_regclass\('public\.legal_acceptance'\) IS NULL/, "false"), /precondition/],
  ];

  it("the battery is not silently shrunk (a floor on the number of rows)", () => {
    expect(rows.length).toBeGreaterThanOrEqual(25);
  });

  for (const [name, build, expected] of rows) {
    it(`row ${name}`, () => {
      const problems = shapeProblems(build());
      expect(problems.length, "the checker must notice").toBeGreaterThan(0);
      expect(problems.join(" | ")).toMatch(expected);
    });
  }

  it("instrument self-test: a clean text and a broken text give different answers", () => {
    expect(shapeProblems("").length).toBeGreaterThan(10);
    expect(shapeProblems(rawUp).length).toBe(0);
  });
});
