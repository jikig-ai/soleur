import { describe, expect, it } from "vitest";
import { existsSync, readdirSync, readFileSync } from "node:fs";
import path from "node:path";

// Static shape tests for migration 184 (#12011 PR-B, ADR-318). The BEHAVIOURAL proof of every Guard 3 mutation row
// runs against a real database in test/server/legal-acceptance.tenant-isolation.test.ts (collected by
// tenant-integration.yml) and supabase/verify/184_legal_acceptance.sql. This file is the cheap backstop: it strips
// comments, reads the SQL as text and checks the properties Guard 3 names. The MUTATIONS block applies each static
// mutant to the RAW migration text and asserts the checker goes RED; a checker that cannot go red is vacuous.

const DIR = path.join(__dirname, "../../supabase");
const UP = path.join(DIR, "migrations/184_legal_acceptance.sql");
const DOWN = path.join(DIR, "migrations/184_legal_acceptance.down.sql");
const VERIFY = path.join(DIR, "verify/184_legal_acceptance.sql");
const MIGRATIONS = path.join(DIR, "migrations");

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

/** A statement (REVOKE / GRANT / CREATE TRIGGER / CREATE POLICY) from its keyword to the next `;`, normalised. */
function statements(stripped: string, head: RegExp): string[] {
  return stripped
    .split(";")
    .map(norm)
    .filter((s) => head.test(s));
}

const DEFINER_FNS = [
  "legal_acceptance_guard",
  "legal_acceptance_row_hash",
  "issue_legal_reauth",
  "claim_legal_reauth_attempt",
  "mark_legal_reauth_verified",
  "record_legal_acceptance",
  "verify_legal_acceptance",
] as const;

/** Every problem the checker finds in one candidate migration text. Empty means the shape holds. */
export function shapeProblems(sqlText: string): string[] {
  const p: string[] = [];
  const s = stripSql(sqlText);
  const flat = norm(s);

  // Preconditions.
  if (!/DO \$\$ BEGIN IF .*to_regclass\('public\.users'\)/i.test(flat)) p.push("precondition DO block missing");
  if (!/is_jti_denied_from_jwt\(\)'\) IS NULL/i.test(flat)) p.push("precondition on is_jti_denied_from_jwt missing");

  // legal_acceptance table: no foreign key, fixed method, unique triple, RLS on.
  const tbl = /CREATE TABLE IF NOT EXISTS public\.legal_acceptance \(([\s\S]*?)\n\);/i.exec(s)?.[1] ?? "";
  if (!tbl) p.push("legal_acceptance table missing");
  if (/REFERENCES/i.test(tbl)) p.push("legal_acceptance must carry no foreign key (erasure must not cascade into it)");
  if (!/method\s+text\s+NOT NULL\s+DEFAULT 'web-session'\s+CHECK \(method = 'web-session'\)/i.test(tbl)) p.push("method not fixed to web-session");
  if (!/UNIQUE \(founder_id, key, text_hash\)/i.test(tbl)) p.push("unique (founder_id, key, text_hash) missing");
  if (!/ALTER TABLE public\.legal_acceptance ENABLE ROW LEVEL SECURITY/i.test(flat)) p.push("RLS not enabled on legal_acceptance");
  if (!/ALTER TABLE public\.legal_reauth_event ENABLE ROW LEVEL SECURITY/i.test(flat)) p.push("RLS not enabled on legal_reauth_event");

  // Grants: no api role writes; authenticated SELECT only on legal_acceptance; nothing on the event table.
  const tableGrants = statements(s, /^GRANT .* ON TABLE public\.legal_(acceptance|reauth_event)/i);
  if (tableGrants.length !== 1 || !/^GRANT SELECT ON TABLE public\.legal_acceptance TO authenticated$/i.test(tableGrants[0] ?? "")) {
    p.push("table grants must be exactly SELECT on legal_acceptance to authenticated");
  }
  for (const t of ["legal_acceptance", "legal_reauth_event"]) {
    if (!new RegExp(`REVOKE ALL ON TABLE public\\.${t} FROM PUBLIC, anon, authenticated, service_role`, "i").test(flat)) p.push(`${t}: REVOKE ALL missing`);
  }

  // Policies: one permissive owner SELECT, one restrictive jti deny.
  const pols = statements(s, /^CREATE POLICY/i);
  const permissive = pols.filter((x) => !/AS RESTRICTIVE/i.test(x));
  if (permissive.length !== 1 || !/FOR SELECT TO authenticated USING \(founder_id = auth\.uid\(\)\)/i.test(permissive[0] ?? "")) p.push("exactly one permissive policy: SELECT where founder_id = auth.uid()");
  if (!pols.some((x) => /AS RESTRICTIVE/i.test(x) && /NOT public\.is_jti_denied_from_jwt\(\)/i.test(x))) p.push("restrictive jti-deny policy missing");

  // Guard trigger: all three events, plus truncate.
  const trig = statements(s, /^CREATE TRIGGER legal_acceptance_guard\b/i)[0] ?? "";
  if (!/BEFORE INSERT OR UPDATE OR DELETE ON public\.legal_acceptance FOR EACH ROW EXECUTE FUNCTION public\.legal_acceptance_guard\(\)/i.test(trig)) p.push("guard trigger must fire BEFORE INSERT OR UPDATE OR DELETE");
  if (!statements(s, /^CREATE TRIGGER legal_acceptance_no_truncate\b/i).some((x) => /BEFORE TRUNCATE ON public\.legal_acceptance FOR EACH STATEMENT/i.test(x))) p.push("truncate trigger missing");

  // Guard function: UPDATE and DELETE always refuse; INSERT needs the GUC and computes the hash in the database.
  const guard = fnBody(s, "legal_acceptance_guard");
  if (!/TG_OP = 'UPDATE'/i.test(guard) || !/TG_OP = 'DELETE'/i.test(guard)) p.push("guard must refuse UPDATE and DELETE");
  if (!/current_setting\('app\.legal_acceptance_rpc', true\)/i.test(guard)) p.push("guard INSERT is not GUC-gated");
  if (!/NEW\.row_hash := public\.legal_acceptance_row_hash\(NEW\)/i.test(guard)) p.push("row_hash must be database-computed in the guard");

  // Row hash: length-prefixed columns, text_hash included.
  const hash = fnBody(s, "legal_acceptance_row_hash");
  if (!/int4send/i.test(hash)) p.push("row_hash must length-prefix columns (int4send)");
  for (const col of ["founder_id", "key", "text_hash", "version", "choice", "requested_edit", "method", "reauth_method", "reauth_at", "session_id", "surface", "created_at"]) {
    if (!new RegExp(`r\\.${col}\\b`, "i").test(hash)) p.push(`row_hash omits ${col}`);
  }

  // Every definer function pins search_path; grant sets are exact.
  for (const f of DEFINER_FNS) {
    const b = fnBody(s, f);
    if (!b) p.push(`${f} missing`);
    else if (!/SECURITY DEFINER SET search_path = public, pg_temp/i.test(b)) p.push(`${f}: search_path not pinned`);
  }
  const grantFor = (f: string) => statements(s, new RegExp(`^GRANT EXECUTE ON FUNCTION public\\.${f}\\(`, "i")).map((x) => /TO (\w+)$/i.exec(x)?.[1]);
  for (const f of ["issue_legal_reauth", "claim_legal_reauth_attempt", "mark_legal_reauth_verified", "verify_legal_acceptance"]) {
    if (JSON.stringify(grantFor(f)) !== JSON.stringify(["service_role"])) p.push(`${f}: EXECUTE must be service_role only`);
  }
  if (JSON.stringify(grantFor("record_legal_acceptance")) !== JSON.stringify(["authenticated"])) p.push("record_legal_acceptance: EXECUTE must be authenticated only");
  for (const f of ["legal_acceptance_guard", "legal_acceptance_row_hash"]) {
    if (grantFor(f).length !== 0) p.push(`${f}: must be EXECUTE-able by nobody`);
  }

  // record_legal_acceptance: actor from the verified session, denied jti, no runtime audience, event consumed under lock.
  const rec = fnBody(s, "record_legal_acceptance");
  if (!/IF auth\.uid\(\) IS NULL THEN RAISE EXCEPTION/i.test(rec)) p.push("record: auth.uid() check missing");
  if (!/IF public\.is_jti_denied_from_jwt\(\) THEN RAISE EXCEPTION/i.test(rec)) p.push("record: jti-deny check missing");
  if (!/'aud'\) = 'soleur-runtime'/i.test(rec)) p.push("record: runtime-audience check missing");
  if (!/set_config\('app\.legal_acceptance_rpc', 'on', true\)/i.test(rec)) p.push("record: must open the GUC for its own insert");
  if (!/FROM public\.legal_reauth_event[^;]*WHERE user_id = auth\.uid\(\) AND key = p_key AND session_id = v_session[^;]*FOR UPDATE/i.test(rec)) p.push("record: event lookup must be bound to user, key and session under FOR UPDATE");
  if (!/v_event\.text_hash <> p_text_hash/i.test(rec)) p.push("record: event bound to another text hash must not be accepted");
  if (!/SET consumed_at = now\(\)/i.test(rec)) p.push("record: Yes must consume the event");
  if (/auth\.uid\(\)\s*=\s*p_/i.test(rec) || /p_user_id|p_founder_id/i.test(rec)) p.push("record: actor must not be a parameter");

  // Read-only verify never opens the write door.
  const ver = fnBody(s, "verify_legal_acceptance");
  if (/set_config\('app\.legal_acceptance_rpc'/i.test(ver)) p.push("verify must not set the GUC");
  if (/\b(INSERT|UPDATE|DELETE)\b/i.test(ver)) p.push("verify must be read-only");

  // service_role RPCs refuse any user identity.
  for (const f of ["issue_legal_reauth", "claim_legal_reauth_attempt", "mark_legal_reauth_verified", "verify_legal_acceptance"]) {
    if (!/IF auth\.uid\(\) IS NOT NULL THEN RAISE EXCEPTION/i.test(fnBody(s, f))) p.push(`${f}: must refuse a user identity`);
  }

  // The erasure scrub must not know this table.
  if (/anonymise_approval_request/i.test(flat)) p.push("migration must not touch anonymise_approval_request");
  if (/UPDATE public\.legal_acceptance|DELETE FROM public\.legal_acceptance/i.test(flat)) p.push("no statement may write legal_acceptance outside the insert path");
  return p;
}

describe("migration 184 files", () => {
  it("up, down and verify files exist", () => {
    expect(existsSync(UP)).toBe(true);
    expect(existsSync(DOWN)).toBe(true);
    expect(existsSync(VERIFY)).toBe(true);
  });

  it("the up migration has the Guard 3 shape", () => {
    expect(shapeProblems(rawUp)).toEqual([]);
  });

  it("the down file refuses while rows exist, before dropping anything", () => {
    const d = norm(stripSql(read(DOWN)));
    const refuse = d.search(/IF EXISTS \(SELECT 1 FROM public\.legal_acceptance\) THEN RAISE EXCEPTION/i);
    const firstDrop = d.search(/DROP (TABLE|FUNCTION)/i);
    expect(refuse).toBeGreaterThanOrEqual(0);
    expect(firstDrop).toBeGreaterThan(refuse);
  });

  it("the verify file asserts the live catalog with a bad column", () => {
    const v = read(VERIFY);
    expect(v).toMatch(/legal_acceptance_rls_enabled/);
    expect(v).toMatch(/legal_acceptance_guard_trigger_enabled/);
    expect(v).toMatch(/AS bad|::int/);
  });

  it("no other migration mentions the table (erasure scrub, grants, policies stay out of it)", () => {
    const others = readdirSync(MIGRATIONS).filter((f) => f.endsWith(".sql") && !f.startsWith("184_"));
    const hits = others.filter((f) => /legal_acceptance|legal_reauth_event/.test(stripSql(read(path.join(MIGRATIONS, f)))));
    expect(hits).toEqual([]);
  });

  it("a second row for a new text version of the same key is not blocked by the unique triple", () => {
    // Must-PASS input: the unique key includes text_hash, so a new version is a new key.
    expect(norm(stripSql(rawUp))).toMatch(/UNIQUE \(founder_id, key, text_hash\)/);
    expect(norm(stripSql(rawUp))).not.toMatch(/UNIQUE \(founder_id, key\)/);
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
    ["1 remove DELETE from the trigger events", () => mutate("BEFORE INSERT OR UPDATE OR DELETE ON public.legal_acceptance", "BEFORE INSERT OR UPDATE ON public.legal_acceptance"), /guard trigger must fire/],
    ["2 set the GUC in the verify function", () => mutate(/(CREATE OR REPLACE FUNCTION public\.verify_legal_acceptance\([\s\S]*?BEGIN)/, "$1 PERFORM set_config('app.legal_acceptance_rpc', 'on', true);"), /verify must not set the GUC/],
    ["3 add the table to the erasure scrub", () => rawUp + "\nCREATE OR REPLACE FUNCTION public.x() RETURNS void LANGUAGE sql AS $$ SELECT 1; $$;\n-- anonymise_approval_request scrub\nDELETE FROM public.legal_acceptance WHERE founder_id = $1;\n", /no statement may write legal_acceptance|must not touch anonymise/],
    ["4 compute row_hash without text_hash", () => mutate(/\n\s*r\.text_hash,[^\n]*/, ""), /row_hash omits text_hash/],
    ["5 skip the reauth-event consumption for Yes", () => mutate(/SET consumed_at = now\(\)/, "SET verified_at = verified_at"), /record: Yes must consume the event/],
    ["6 accept an event bound to another text hash", () => mutate(/(FUNCTION public\.record_legal_acceptance\([\s\S]*?)v_event\.text_hash <> p_text_hash/, "$1false"), /event bound to another text hash/],
    ["7a drop the auth.uid() check", () => mutate(/IF auth\.uid\(\) IS NULL THEN/, "IF false THEN"), /record: auth\.uid\(\) check missing/],
    ["7b drop the runtime-audience check", () => mutate(/'aud'\) = 'soleur-runtime'/, "'aud') = 'never'"), /runtime-audience check missing/],
    ["8 add a client write grant", () => rawUp + "\nGRANT INSERT ON TABLE public.legal_acceptance TO authenticated;\n", /table grants must be exactly/],
    ["9 add a foreign key on founder_id", () => mutate(/founder_id\s+uuid\s+NOT NULL/, "founder_id uuid NOT NULL REFERENCES public.users(id) ON DELETE SET NULL"), /no foreign key/],
    ["10 drop the search_path pin from record", () => mutate(/(FUNCTION public\.record_legal_acceptance\([\s\S]*?)SET search_path = public, pg_temp/, "$1"), /record_legal_acceptance: search_path not pinned/],
  ];

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
