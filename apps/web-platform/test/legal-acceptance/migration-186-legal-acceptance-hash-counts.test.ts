import { beforeEach, describe, expect, it } from "vitest";
import { existsSync, readFileSync } from "node:fs";
import path from "node:path";
import { KEY_RE } from "@/server/legal-acceptance/canonical";

// Static shape tests for migration 186 (#12429, ADR-319 amendment 2026-11-08): the credential-free pre-flag aggregate,
// `legal_acceptance_hash_counts(p_key)`. The BEHAVIOURAL proof (service_role succeeds, authenticated gets 42501, two
// hashes across two founders are counted) runs against a real database in
// test/server/legal-acceptance.tenant-isolation.test.ts and supabase/verify/186_legal_acceptance_hash_counts.sql. This file
// is the cheap backstop (Guard 2 of the plan): it strips comments, reads the SQL as text and checks the privacy boundary.
// The MUTATIONS block applies each static mutant to the RAW text and asserts the checker goes RED; a checker that cannot go
// red is vacuous.

const DIR = path.join(__dirname, "../../supabase");
const UP = path.join(DIR, "migrations/186_legal_acceptance_hash_counts.sql");
const DOWN = path.join(DIR, "migrations/186_legal_acceptance_hash_counts.down.sql");
const VERIFY = path.join(DIR, "verify/186_legal_acceptance_hash_counts.sql");

const SERVICE = path.join(__dirname, "../../server/legal-acceptance/service.ts");

const read = (p: string): string => (existsSync(p) ? readFileSync(p, "utf8") : "");
const rawUp = read(UP);

/** HASH_COUNTS_MAX_ROWS read from the service source (importing service.ts would pull the logger and Sentry into a static test). */
const MAX_ROWS = (() => {
  const m = /^export const HASH_COUNTS_MAX_ROWS = (\d+);$/m.exec(read(SERVICE));
  if (!m) throw new Error("extraction found nothing: HASH_COUNTS_MAX_ROWS in service.ts");
  return Number(m[1]);
})();
const norm = (s: string) => s.replace(/\s+/g, " ").trim();

/** Remove line and block comments; single-quoted literals (with '' escapes) are copied through intact. (Same lexer as the 185 test; importing that file would re-register its tests.) */
function stripSql(src: string): string {
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
function fnBody(stripped: string, name: string): string {
  const start = stripped.search(new RegExp(`CREATE OR REPLACE FUNCTION public\\.${name}\\(`, "i"));
  if (start < 0) return "";
  const open = stripped.indexOf("$$", start);
  if (open < 0) return "";
  const close = stripped.indexOf("$$;", open + 2);
  return close < 0 ? "" : norm(stripped.slice(start, close + 3));
}

const FN = "legal_acceptance_hash_counts";
const SIG = "public.legal_acceptance_hash_counts(text)";
/** The 184 shape predicate, built from the canonical regex (never a restated literal): a drifted key shape in 186 must go red here. */
const SHAPE_KEY = `p_key IS NULL OR p_key !~ '${KEY_RE.source}'`;

/** Columns the function must never read or name: who decided, what they decided, when, and the note. */
const FORBIDDEN_COLUMNS = /\b(founder_id|choice|created_at|requested_edit|row_hash|session_id|event_id|reauth_at|reauth_method)\b/i;

/** Every problem the checker finds in one candidate migration text. Empty means the privacy boundary holds. */
export function shapeProblems(sqlText: string, maxRows: number = MAX_ROWS): string[] {
  const p: string[] = [];
  const s = stripSql(sqlText);
  const flat = norm(s);

  if (!/DO \$\$ BEGIN IF to_regclass\('public\.legal_acceptance'\) IS NULL THEN RAISE EXCEPTION/i.test(flat)) p.push("precondition DO block on public.legal_acceptance missing");

  const b = fnBody(s, FN);
  if (!b) {
    p.push(`${FN} missing`);
    return p;
  }
  if (!/\(p_key text\) RETURNS jsonb/i.test(b)) p.push("signature must be (p_key text) RETURNS jsonb");
  if (!/\bSTABLE\b/i.test(b)) p.push("must be STABLE (read-only)");
  if (!/SECURITY DEFINER SET search_path = public, pg_temp/i.test(b)) p.push("search_path not pinned to public, pg_temp");
  if (!/IF auth\.uid\(\) IS NOT NULL THEN RAISE EXCEPTION '[^']*' USING ERRCODE = '42501'/i.test(b)) p.push("must refuse a user identity with 42501");
  if (!b.includes(`IF ${SHAPE_KEY} THEN RAISE EXCEPTION 'legal acceptance: invalid input' USING ERRCODE = '22023'`)) p.push("must validate p_key with the 184 shape predicate and a static 22023 message");
  if (!/FROM ONLY public\.legal_acceptance\b/i.test(b)) p.push("must read ONLY public.legal_acceptance");
  if (/FROM public\.legal_acceptance\b/i.test(b)) p.push("must not read legal_acceptance through its children");
  if (!/WHERE key = p_key/i.test(b)) p.push("must filter by key = p_key");
  if (!/GROUP BY text_hash/i.test(b)) p.push("must group by text_hash");
  if (FORBIDDEN_COLUMNS.test(b)) p.push(`must not name founder_id, choice, created_at, requested_edit or any per-row column (found: ${FORBIDDEN_COLUMNS.exec(b)?.[1]})`);
  if (!/'total'/.test(b) || !/'by_hash'/.test(b) || !/'text_hash'/.test(b) || !/'count'/.test(b)) p.push("must answer exactly total and by_hash [{text_hash, count}]");
  if (!/ORDER BY text_hash/i.test(b)) p.push("by_hash must be ordered by text_hash");
  if (!/LIMIT \d+/i.test(b) || !/ERRCODE = '54000'/i.test(b)) p.push("by_hash must be capped (LIMIT + a static 54000 refusal)");
  // The cap is one number in two layers: the SQL selects MAX + 1 groups and refuses on `> MAX`; service.ts refuses `> MAX` rows.
  const limits = [...b.matchAll(/\bLIMIT (\d+)\b/gi)].map((m) => Number(m[1]));
  const refusals = [...b.matchAll(/\bIF v_groups > (\d+) THEN RAISE EXCEPTION '[^']*' USING ERRCODE = '54000'/gi)].map((m) => Number(m[1]));
  if (limits.length !== 1 || limits[0] !== maxRows + 1) p.push(`the group LIMIT must be HASH_COUNTS_MAX_ROWS + 1 = ${maxRows + 1} (found ${JSON.stringify(limits)})`);
  if (refusals.length !== 1 || refusals[0] !== maxRows) p.push(`the 54000 refusal must be v_groups > HASH_COUNTS_MAX_ROWS = ${maxRows} (found ${JSON.stringify(refusals)})`);
  // p_key must never reach an exception message (it is caller text).
  for (const m of b.matchAll(/RAISE EXCEPTION\s+('(?:[^']|'')*')([^;]*);/gi)) {
    if (/%/.test(m[1])) p.push("exception text must be static: no format placeholders");
    if (/\bp_key\b/.test(m[2].replace(/USING ERRCODE = '[0-9A-Z]+'/i, ""))) p.push("p_key must not appear in an exception");
  }
  if (/set_config|app\.legal_acceptance_rpc/i.test(b)) p.push("must not set or name the write-door setting of legal_acceptance");
  if (/\b(INSERT|UPDATE|DELETE|TRUNCATE)\b/i.test(b.replace(/'[^']*'/g, "''"))) p.push("must be read-only");

  // Grants: revoke from everyone including service_role, then grant to service_role only.
  if (!new RegExp(`REVOKE ALL ON FUNCTION ${SIG.replace(/[\\().]/g, "\\$&")} FROM PUBLIC, anon, authenticated, service_role`, "i").test(flat)) p.push("REVOKE ALL FROM PUBLIC, anon, authenticated, service_role missing");
  const grants = flat.split(";").map((x) => x.trim()).filter((x) => /^GRANT /i.test(x));
  if (JSON.stringify(grants.map((g) => /TO (\w+)$/i.exec(g)?.[1])) !== JSON.stringify(["service_role"]) || !grants.every((g) => /^GRANT EXECUTE ON FUNCTION public\.legal_acceptance_hash_counts\(text\) TO service_role$/i.test(g))) {
    p.push("the only GRANT is EXECUTE on the function to service_role");
  }
  if (!/COMMENT ON FUNCTION public\.legal_acceptance_hash_counts\(text\) IS/i.test(flat)) p.push("COMMENT ON FUNCTION missing");
  if (!/-- LAWFUL_BASIS: legitimate_interests \(Art\. 6\(1\)\(f\)\)/.test(sqlText)) p.push("LAWFUL_BASIS annotation missing");

  // Nothing else may ride along: no new table, no change to legal_acceptance.
  if (/CREATE TABLE/i.test(flat)) p.push("this migration adds a function only: no CREATE TABLE");
  if (/ALTER TABLE|DISABLE ROW LEVEL SECURITY|CREATE POLICY/i.test(flat)) p.push("no ALTER TABLE or policy change is allowed");
  if (/GRANT [^;]* ON ALL (TABLES|FUNCTIONS)/i.test(flat)) p.push("no blanket grant may appear in this migration");
  return p;
}

beforeEach(() => {
  expect.hasAssertions();
});

describe("migration 186 files", () => {
  it("up, down and verify files exist", () => {
    expect(existsSync(UP)).toBe(true);
    expect(existsSync(DOWN)).toBe(true);
    expect(existsSync(VERIFY)).toBe(true);
  });

  it("the up migration has the Guard 2 shape", () => {
    expect(shapeProblems(rawUp)).toEqual([]);
  });

  it("the down file is a plain DROP FUNCTION IF EXISTS of the current signature and touches nothing else", () => {
    const d = norm(stripSql(read(DOWN)));
    expect(d).toContain(`DROP FUNCTION IF EXISTS ${SIG}`);
    expect(d).not.toMatch(/DROP TABLE|DROP FUNCTION IF EXISTS public\.(ack_legal_acceptance|legal_acceptance_ack_state|verify_legal_acceptance)/i);
    expect((d.match(/DROP /gi) ?? []).length).toBe(1);
  });

  it("the down file's header says how to roll back: revert the code, leave 186 in place, and a deliberate drop also deletes the ledger row", () => {
    const raw = read(DOWN);
    expect(raw).toMatch(/ROLLBACK IS BY CODE/);
    expect(raw).toMatch(/-- {3}2\. DELETE FROM public\._schema_migrations WHERE filename = '186_legal_acceptance_hash_counts\.sql';/);
    // ...as comments only: the executable text is the single DROP and no DELETE.
    expect(norm(stripSql(raw))).not.toMatch(/DELETE|_schema_migrations/i);
  });

  it("the cap extracted from service.ts is a positive integer, so the SQL cap rows below compare against a real number", () => {
    expect(Number.isInteger(MAX_ROWS) && MAX_ROWS > 0).toBe(true);
    expect(shapeProblems(rawUp, MAX_ROWS)).toEqual([]);
  });

  it("the verify file asserts the live catalog with a bad column", () => {
    const v = norm(stripSql(read(VERIFY)));
    expect(v).toMatch(/_security_definer_search_path_pinned.*proconfig @> ARRAY\[.search_path=public, pg_temp.\]/);
    expect(v).toMatch(/has_function_privilege\(r\.role, f\.sig, 'EXECUTE'\) = \(r\.role = 'service_role'\)/);
    expect(v).toMatch(/hash_counts_has_no_other_overloads/);
    expect(v).toMatch(/hash_counts_no_execute_for_anon_authenticated_or_public/);
    expect(v).toMatch(/a\.grantee = 0 AND a\.privilege_type = 'EXECUTE'/);
    expect(v).toMatch(/hash_counts_names_no_per_row_column/);
    expect(v).toMatch(/AS bad|::int/);
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
    ["1 drop the REVOKE", () => mutate(/REVOKE ALL ON FUNCTION[^;]*;/, "-- removed"), /REVOKE ALL/],
    ["1b revoke from PUBLIC only", () => mutate(/FROM PUBLIC, anon, authenticated, service_role/, "FROM PUBLIC"), /REVOKE ALL/],
    ["2 grant EXECUTE to authenticated", () => mutate(/(GRANT EXECUTE ON FUNCTION public\.legal_acceptance_hash_counts\(text\)\s+TO) service_role/, "$1 authenticated"), /only GRANT/],
    ["2b grant EXECUTE to anon as well", () => rawUp + "\nGRANT EXECUTE ON FUNCTION public.legal_acceptance_hash_counts(text) TO anon;\n", /only GRANT/],
    ["2c grant EXECUTE to PUBLIC", () => rawUp + "\nGRANT EXECUTE ON FUNCTION public.legal_acceptance_hash_counts(text) TO PUBLIC;\n", /only GRANT/],
    ["3 drop the auth.uid() guard", () => mutate(/IF auth\.uid\(\) IS NOT NULL THEN/, "IF false THEN"), /refuse a user identity/],
    ["4 add founder_id to the output", () => mutate(/'by_hash', v_by/, "'by_hash', v_by, 'founder_id', (SELECT founder_id FROM ONLY public.legal_acceptance LIMIT 1)"), /founder_id/],
    ["4b add choice to the grouping", () => mutate(/GROUP BY text_hash/, "GROUP BY text_hash, choice"), /choice/],
    ["4c add the note", () => mutate(/'by_hash', v_by/, "'by_hash', v_by, 'note', (SELECT requested_edit FROM ONLY public.legal_acceptance LIMIT 1)"), /requested_edit/],
    ["4d add a timestamp", () => mutate(/'by_hash', v_by/, "'by_hash', v_by, 'at', (SELECT max(created_at) FROM ONLY public.legal_acceptance)"), /created_at/],
    ["5 unpin search_path", () => mutate(/SET search_path = public, pg_temp/, ""), /search_path/],
    ["5b pin search_path without pg_temp", () => mutate(/SET search_path = public, pg_temp/, "SET search_path = public"), /search_path/],
    ["6 read through the children", () => mutate(/FROM ONLY public\.legal_acceptance/g, "FROM public.legal_acceptance"), /ONLY/],
    ["7 drop the key validation", () => mutate(/p_key IS NULL OR p_key !~ '\^\[a-z0-9\]\[a-z0-9-\]\{0,62\}\$'/, "p_key IS NULL"), /validate p_key/],
    ["7b widen the key shape to 64 characters", () => mutate(/\{0,62\}\$'/, "{0,63}$'"), /validate p_key/],
    ["7c loosen the key shape to uppercase", () => mutate(/\^\[a-z0-9\]\[a-z0-9-\]\{0,62\}\$/, "^[a-zA-Z0-9][a-zA-Z0-9-]{0,62}$"), /validate p_key/],
    ["8 put p_key in an exception", () => mutate(/RAISE EXCEPTION 'legal acceptance: invalid input'/, "RAISE EXCEPTION 'legal acceptance: invalid input %', p_key"), /exception|validate p_key/],
    ["8b p_key concatenated into the 54000 refusal text (no placeholder)", () => mutate(/RAISE EXCEPTION 'legal acceptance: too many distinct hashes' USING/, "RAISE EXCEPTION 'legal acceptance: too many distinct hashes' || p_key USING"), /p_key must not appear in an exception/],
    ["8d a format placeholder in the 54000 text (no p_key involved)", () => mutate(/'legal acceptance: too many distinct hashes'/, "'legal acceptance: too many distinct hashes %'"), /no format placeholders/],
    ["8c p_key in a DETAIL clause after the refusal's ERRCODE", () => mutate(/USING ERRCODE = '54000'/, "USING ERRCODE = '54000', DETAIL = p_key"), /p_key must not appear in an exception/],
    ["9 drop the row cap", () => mutate(/ERRCODE = '54000'/, "ERRCODE = '22023'"), /capped/],
    ["9b the group LIMIT drifts above the cap + 1 (LIMIT 31)", () => mutate(/LIMIT 21\b/, "LIMIT 31"), /LIMIT must be HASH_COUNTS_MAX_ROWS \+ 1/],
    ["9c the group LIMIT equals the cap (LIMIT 20: a 21st group could never be seen)", () => mutate(/LIMIT 21\b/, "LIMIT 20"), /LIMIT must be HASH_COUNTS_MAX_ROWS \+ 1/],
    ["9d the refusal threshold drifts (> 30)", () => mutate(/IF v_groups > 20 THEN/, "IF v_groups > 30 THEN"), /refusal must be v_groups > HASH_COUNTS_MAX_ROWS/],
    ["9e the refusal threshold drops to the LIMIT (> 21)", () => mutate(/IF v_groups > 20 THEN/, "IF v_groups > 21 THEN"), /refusal must be v_groups > HASH_COUNTS_MAX_ROWS/],
    ["9f the refusal is removed (no IF v_groups > N)", () => mutate(/IF v_groups > 20 THEN/, "IF false THEN"), /refusal must be v_groups > HASH_COUNTS_MAX_ROWS/],
    ["10 write the table", () => mutate(/(CREATE OR REPLACE FUNCTION public\.legal_acceptance_hash_counts\([\s\S]*?BEGIN)/, "$1 UPDATE public.legal_acceptance SET key = key;"), /read-only/],
    ["11 open the write door", () => mutate(/(CREATE OR REPLACE FUNCTION public\.legal_acceptance_hash_counts\([\s\S]*?BEGIN)/, "$1 PERFORM set_config('app.legal_acceptance_rpc', 'on', true);"), /write-door/],
    ["12 make it VOLATILE", () => mutate(/\bSTABLE\b/, "VOLATILE"), /STABLE/],
    ["13 add a table", () => rawUp + "\nCREATE TABLE public.legal_acceptance_counts_cache (k text);\n", /no CREATE TABLE/],
    ["14 alter the record table", () => rawUp + "\nALTER TABLE public.legal_acceptance DISABLE TRIGGER legal_acceptance_guard;\n", /ALTER TABLE/],
    ["15 blanket grant", () => rawUp + "\nGRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO service_role;\n", /blanket|only GRANT/],
    ["16 drop the precondition", () => mutate(/to_regclass\('public\.legal_acceptance'\) IS NULL/, "false"), /precondition/],
    ["17 drop the lawful-basis annotation", () => mutate(/-- LAWFUL_BASIS:/, "-- BASIS:"), /LAWFUL_BASIS/],
    ["18 drop the ordering", () => mutate(/ORDER BY text_hash/g, "ORDER BY count(*)"), /ordered by text_hash/],
  ];

  it("the battery is not silently shrunk (a floor on the number of rows)", () => {
    expect(rows.length).toBeGreaterThanOrEqual(34);
  });

  for (const [name, build, expected] of rows) {
    it(`row ${name}`, () => {
      const problems = shapeProblems(build());
      expect(problems.length, "the checker must notice").toBeGreaterThan(0);
      expect(problems.join(" | ")).toMatch(expected);
    });
  }

  it("a changed HASH_COUNTS_MAX_ROWS (service.ts) against the unchanged SQL is a problem in both directions", () => {
    for (const drifted of [MAX_ROWS + 10, MAX_ROWS - 5, MAX_ROWS + 1]) {
      expect(shapeProblems(rawUp, drifted).join(" | "), `maxRows ${drifted}`).toMatch(/LIMIT must be HASH_COUNTS_MAX_ROWS \+ 1/);
      expect(shapeProblems(rawUp, drifted).join(" | "), `maxRows ${drifted}`).toMatch(/refusal must be v_groups > HASH_COUNTS_MAX_ROWS/);
    }
  });

  it("instrument self-test: an empty text and the real text give different answers", () => {
    expect(shapeProblems("").length).toBeGreaterThan(0);
    expect(shapeProblems(rawUp).length).toBe(0);
  });
});
