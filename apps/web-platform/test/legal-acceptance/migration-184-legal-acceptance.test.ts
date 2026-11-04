import { beforeEach, describe, expect, it } from "vitest";
import { existsSync, readdirSync, readFileSync } from "node:fs";
import path from "node:path";

// Static shape tests for migration 184 (#12011 PR-B, ADR-319). The BEHAVIOURAL proof of every Guard 3 mutation row
// runs against a real database in test/server/legal-acceptance.tenant-isolation.test.ts (collected by
// tenant-integration.yml) and supabase/verify/184_legal_acceptance.sql. This file is the cheap backstop: it strips
// comments, reads the SQL as text and checks the properties Guard 3 names. The MUTATIONS block applies each static
// mutant to the RAW migration text and asserts the checker goes RED; a checker that cannot go red is vacuous. A lexical
// check cannot prove a function's logic: the DB-backed test is the proof, this is the tripwire.

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
const SERVICE_FNS = ["issue_legal_reauth", "claim_legal_reauth_attempt", "mark_legal_reauth_verified", "verify_legal_acceptance"] as const;

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
  if (!/session_id\s+text\s+NOT NULL/i.test(tbl)) p.push("session_id must be NOT NULL (every decision comes from a web session)");
  for (const c of ["legal_acceptance_yes_has_reauth", "legal_acceptance_reauth_only_for_yes", "legal_acceptance_reauth_paired", "legal_acceptance_edit_only_with_request"]) {
    if (!new RegExp(`CONSTRAINT ${c}\\b`, "i").test(tbl)) p.push(`constraint ${c} missing`);
  }
  if (!/ALTER TABLE public\.legal_acceptance ENABLE ROW LEVEL SECURITY/i.test(flat)) p.push("RLS not enabled on legal_acceptance");
  if (!/ALTER TABLE public\.legal_reauth_event ENABLE ROW LEVEL SECURITY/i.test(flat)) p.push("RLS not enabled on legal_reauth_event");

  // Grants: no api role writes; authenticated SELECT only on legal_acceptance; nothing on the event table. The TABLE
  // keyword is optional in SQL, the schema prefix too, and a column list or ALL TABLES is still a grant.
  const tableGrants = statements(s, /^GRANT .* ON (TABLE )?(public\.)?legal_(acceptance|reauth_event)\b/i);
  if (tableGrants.length !== 1 || !/^GRANT SELECT ON TABLE public\.legal_acceptance TO authenticated$/i.test(tableGrants[0] ?? "")) {
    p.push("table grants must be exactly SELECT on legal_acceptance to authenticated");
  }
  if (/GRANT [^;]* ON ALL TABLES/i.test(flat)) p.push("no blanket ALL TABLES grant may appear in this migration");
  if (/GRANT [^;]*\b(authenticated|anon|service_role)\b[^;]* TO /i.test(flat.replace(/GRANT (SELECT|EXECUTE) ON [^;]* TO (authenticated|service_role)/gi, ""))) {
    p.push("unexpected GRANT (a role membership or a privilege outside the expected set)");
  }
  for (const t of ["legal_acceptance", "legal_reauth_event"]) {
    if (!new RegExp(`REVOKE ALL ON TABLE public\\.${t} FROM PUBLIC, anon, authenticated, service_role`, "i").test(flat)) p.push(`${t}: REVOKE ALL missing`);
  }

  // Policies: one permissive owner SELECT (not through a runtime audience), one restrictive jti deny.
  const pols = statements(s, /^CREATE POLICY/i);
  const permissive = pols.filter((x) => !/AS RESTRICTIVE/i.test(x));
  if (
    permissive.length !== 1 ||
    !/FOR SELECT TO authenticated USING \(founder_id = auth\.uid\(\) AND \(auth\.jwt\(\) ->> 'aud'\) = 'authenticated'\)/i.test(permissive[0] ?? "")
  ) {
    p.push("exactly one permissive policy: SELECT where founder_id = auth.uid() and the audience is exactly 'authenticated'");
  }
  if (!pols.some((x) => /AS RESTRICTIVE/i.test(x) && /NOT public\.is_jti_denied_from_jwt\(\)/i.test(x))) p.push("restrictive jti-deny policy missing");

  // Guard trigger: all three events, plus truncate; both ENABLE ALWAYS (they also fire in replica mode).
  const trig = statements(s, /^CREATE TRIGGER legal_acceptance_guard\b/i)[0] ?? "";
  if (!/BEFORE INSERT OR UPDATE OR DELETE ON public\.legal_acceptance FOR EACH ROW EXECUTE FUNCTION public\.legal_acceptance_guard\(\)/i.test(trig)) p.push("guard trigger must fire BEFORE INSERT OR UPDATE OR DELETE");
  if (!statements(s, /^CREATE TRIGGER legal_acceptance_no_truncate\b/i).some((x) => /BEFORE TRUNCATE ON public\.legal_acceptance FOR EACH STATEMENT/i.test(x))) p.push("truncate trigger missing");
  for (const t of ["legal_acceptance_guard", "legal_acceptance_no_truncate"]) {
    if (!new RegExp(`ALTER TABLE public\\.legal_acceptance ENABLE ALWAYS TRIGGER ${t}\\b`, "i").test(flat)) p.push(`${t}: must be ENABLE ALWAYS (fires in replica mode too)`);
  }

  // Guard function: UPDATE and DELETE always refuse (the raise is INSIDE the condition); INSERT needs the GUC AND a
  // consumed intent; the hash is database-computed.
  const guard = fnBody(s, "legal_acceptance_guard");
  if (!/IF TG_OP = 'UPDATE' OR TG_OP = 'DELETE' OR TG_OP = 'TRUNCATE' THEN RAISE EXCEPTION/i.test(guard)) p.push("guard must refuse UPDATE, DELETE and TRUNCATE");
  if (!/IF COALESCE\(current_setting\('app\.legal_acceptance_rpc', true\), ''\) <> 'on' THEN RAISE EXCEPTION/i.test(guard)) p.push("guard INSERT is not GUC-gated");
  if (!/FROM public\.legal_reauth_event e WHERE e\.id = NEW\.event_id AND e\.user_id = NEW\.founder_id/i.test(guard) || !/e\.consumed_at IS NOT NULL/i.test(guard)) {
    p.push("guard INSERT must also require a consumed intent for the same event, user, key, text hash and session");
  }
  if (!/NEW\.row_hash := public\.legal_acceptance_row_hash\(NEW\)/i.test(guard)) p.push("row_hash must be database-computed in the guard");

  // Row hash: length-prefixed, and the hashed list equals the table's column set (a column added later must be added).
  const hash = fnBody(s, "legal_acceptance_row_hash");
  if (!/int4send/i.test(hash)) p.push("row_hash must length-prefix columns (int4send)");
  const tableCols = [...tbl.matchAll(/^\s{2}([a-z_]+)\s+(?:uuid|text|timestamptz|integer)\b/gm)].map((m) => m[1]).filter((c) => c !== "row_hash");
  if (tableCols.length < 14) p.push(`could not read the table's columns (${tableCols.length})`);
  for (const col of tableCols) {
    const hashed =
      col === "reauth_at" || col === "created_at"
        ? new RegExp(`to_char\\(r\\.${col} AT TIME ZONE 'UTC'`, "i").test(hash)
        : new RegExp(`(?:\\[|,)\\s*r\\.${col}(::text)?\\s*,`, "i").test(hash);
    if (!hashed) p.push(`row_hash omits ${col}`);
  }

  // Every definer function pins search_path; grant sets are exact.
  for (const f of DEFINER_FNS) {
    const b = fnBody(s, f);
    if (!b) p.push(`${f} missing`);
    else if (!/SECURITY DEFINER SET search_path = public, pg_temp/i.test(b)) p.push(`${f}: search_path not pinned`);
  }
  const grantFor = (f: string) => statements(s, new RegExp(`^GRANT EXECUTE ON FUNCTION public\\.${f}\\(`, "i")).map((x) => /TO (\w+)$/i.exec(x)?.[1]);
  for (const f of SERVICE_FNS) {
    if (JSON.stringify(grantFor(f)) !== JSON.stringify(["service_role"])) p.push(`${f}: EXECUTE must be service_role only`);
  }
  if (JSON.stringify(grantFor("record_legal_acceptance")) !== JSON.stringify(["authenticated"])) p.push("record_legal_acceptance: EXECUTE must be authenticated only");
  for (const f of ["legal_acceptance_guard", "legal_acceptance_row_hash"]) {
    if (grantFor(f).length !== 0) p.push(`${f}: must be EXECUTE-able by nobody`);
  }

  // record_legal_acceptance: actor from the verified session, denied jti, web-session audience only, a live intent
  // consumed under lock for EVERY choice, the version taken from the intent.
  const rec = fnBody(s, "record_legal_acceptance");
  if (!/IF auth\.uid\(\) IS NULL THEN RAISE EXCEPTION/i.test(rec)) p.push("record: auth.uid() check missing");
  if (!/IF public\.is_jti_denied_from_jwt\(\) THEN RAISE EXCEPTION/i.test(rec)) p.push("record: jti-deny check missing");
  if (!/\(auth\.jwt\(\) ->> 'aud'\) IS DISTINCT FROM 'authenticated' THEN RAISE EXCEPTION/i.test(rec)) p.push("record: audience must be exactly 'authenticated'");
  if (!/IF v_session IS NULL THEN RAISE EXCEPTION/i.test(rec)) p.push("record: a web session id is required for every choice");
  if (!/pg_advisory_xact_lock\(hashtextextended\(auth\.uid\(\)::text/i.test(rec)) p.push("record: two tabs must be serialised (advisory lock)");
  if (!/set_config\('app\.legal_acceptance_rpc', 'on', true\)/i.test(rec)) p.push("record: must open the GUC for its own insert");
  if (!/FROM public\.legal_reauth_event[^;]*WHERE user_id = auth\.uid\(\) AND key = p_key AND session_id = v_session[^;]*FOR UPDATE/i.test(rec)) p.push("record: event lookup must be bound to user, key and session under FOR UPDATE");
  if (!/v_event\.text_hash <> p_text_hash/i.test(rec)) p.push("record: event bound to another text hash must not be accepted");
  if (!/SET consumed_at = now\(\)/i.test(rec)) p.push("record: every decision must consume its intent");
  if (!/v_event\.verified_at IS NULL THEN RAISE EXCEPTION/i.test(rec) || !/interval '5 minutes'/i.test(rec)) p.push("record: a Yes needs a code confirmed in the last 5 minutes");
  if (/auth\.uid\(\)\s*=\s*p_/i.test(rec) || /p_user_id|p_founder_id|p_version/i.test(rec)) p.push("record: actor and version must not be parameters");

  // issue: input validation incl. version, lock, purge before any early return.
  const iss = fnBody(s, "issue_legal_reauth");
  if (!/p_version/i.test(iss) || !/pg_advisory_xact_lock/i.test(iss)) p.push("issue: version binding and the per-user lock are required");
  if (!(iss.search(/DELETE FROM public\.legal_reauth_event WHERE created_at < now\(\) - interval '30 days'/i) >= 0 && iss.search(/DELETE FROM public\.legal_reauth_event/i) < iss.search(/RETURN jsonb_build_object\('outcome', 'already_recorded'/i))) {
    p.push("issue: the 30-day purge must run before any early return");
  }
  // claim / mark: validate every argument; mark is bound to the event id.
  for (const f of ["claim_legal_reauth_attempt", "mark_legal_reauth_verified"]) {
    if (!/p_text_hash !~ '\^\[0-9a-f\]\{64\}\$'/i.test(fnBody(s, f))) p.push(`${f}: must validate p_text_hash (a NULL must not skip the replaced branch)`);
  }
  if (!/WHERE id = p_event_id AND user_id = p_user_id/i.test(fnBody(s, "mark_legal_reauth_verified"))) p.push("mark: must be bound to the event id returned by claim");

  // Read-only verify never opens the write door and fails closed.
  const ver = fnBody(s, "verify_legal_acceptance");
  if (/set_config\('app\.legal_acceptance_rpc'/i.test(ver)) p.push("verify must not set the GUC");
  if (/\b(INSERT|UPDATE|DELETE)\b/i.test(ver)) p.push("verify must be read-only");
  if (!/WHEN NOT v_ok THEN 'invalid'/i.test(ver) || !/FROM ONLY public\.legal_acceptance/i.test(ver)) p.push("verify must fail closed (status invalid) and read ONLY the table");

  // service_role RPCs refuse any user identity.
  for (const f of SERVICE_FNS) {
    if (!/IF auth\.uid\(\) IS NOT NULL THEN RAISE EXCEPTION/i.test(fnBody(s, f))) p.push(`${f}: must refuse a user identity`);
  }

  // Nothing later in the file may undo what the earlier statements set up ("present somewhere" is not "in effect last").
  if (/ALTER TABLE [^;]*legal_acceptance[^;]*\b(DISABLE|NO FORCE)\b/i.test(flat) || /DISABLE ROW LEVEL SECURITY/i.test(flat)) p.push("no statement may disable the guard trigger or row level security");
  const lastIdx = (re: RegExp) => [...flat.matchAll(new RegExp(re.source, "gi"))].map((m) => m.index ?? -1).pop() ?? -1;
  if (lastIdx(/DROP TRIGGER [^;]*legal_acceptance_guard/) > lastIdx(/CREATE TRIGGER legal_acceptance_guard/)) p.push("a DROP TRIGGER comes after the guard trigger is created");
  if (lastIdx(/DROP TRIGGER [^;]*legal_acceptance_no_truncate/) > lastIdx(/CREATE TRIGGER legal_acceptance_no_truncate/)) p.push("a DROP TRIGGER comes after the truncate trigger is created");
  for (const pol of ["legal_acceptance_founder_select", "legal_acceptance_jti_not_denied"]) {
    if (lastIdx(new RegExp(`DROP POLICY [^;]*${pol}`)) > lastIdx(new RegExp(`CREATE POLICY ${pol}`))) p.push(`a DROP POLICY comes after ${pol} is created`);
  }
  // The time predicates and the consume statement are pinned in full (a flipped comparison or an OR true is a different program).
  if (!/IF v_event\.verified_at < now\(\) - interval '5 minutes' THEN RETURN jsonb_build_object\('outcome', 'code_expired'\)/i.test(rec)) p.push("record: the 5-minute code freshness predicate is not the reviewed one");
  if (!/UPDATE public\.legal_reauth_event SET consumed_at = now\(\) WHERE id = v_event\.id AND consumed_at IS NULL AND superseded_at IS NULL; IF NOT FOUND THEN/i.test(rec)) p.push("record: the consume statement is not the reviewed one");
  if (!/AND \(verified_at IS NULL OR verified_at >= now\(\) - interval '5 minutes'\)/i.test(iss) || !/AND version = p_version/i.test(iss)) p.push("issue: a reused intent must match the version and carry a still-fresh code");
  if (!/IF v_event\.verified_at IS NOT NULL AND v_event\.verified_at < now\(\) - interval '5 minutes' THEN RETURN jsonb_build_object\('outcome', 'code_stale'\)/i.test(fnBody(s, "claim_legal_reauth_attempt"))) p.push("claim: a stale confirmed code must be its own outcome and burn no attempt");
  if (!/v_ok := COALESCE\(/i.test(ver)) p.push("verify: a NULL checksum comparison must read as not ok");

  // The erasure scrub must not know this table.
  if (/anonymise_approval_request/i.test(flat)) p.push("migration must not touch anonymise_approval_request");
  if (/UPDATE public\.legal_acceptance|DELETE FROM public\.legal_acceptance/i.test(flat)) p.push("no statement may write legal_acceptance outside the insert path");
  return p;
}

beforeEach(() => {
  expect.hasAssertions();
});

describe("migration 184 files", () => {
  it("up, down and verify files exist", () => {
    expect(existsSync(UP)).toBe(true);
    expect(existsSync(DOWN)).toBe(true);
    expect(existsSync(VERIFY)).toBe(true);
  });

  it("the up migration has the Guard 3 shape", () => {
    expect(shapeProblems(rawUp)).toEqual([]);
  });

  it("the down file locks the table, refuses while rows exist, and does both before dropping anything", () => {
    const d = norm(stripSql(read(DOWN)));
    const lock = d.search(/LOCK TABLE public\.legal_acceptance IN ACCESS EXCLUSIVE MODE/i);
    const refuse = d.search(/IF EXISTS \(SELECT 1 FROM public\.legal_acceptance\) THEN RAISE EXCEPTION/i);
    const firstDrop = d.search(/DROP (TABLE|FUNCTION)/i);
    expect(lock).toBeGreaterThanOrEqual(0);
    expect(refuse).toBeGreaterThan(lock);
    expect(firstDrop).toBeGreaterThan(refuse);
  });

  it("the down file drops the CURRENT signatures (and the pre-review ones for a dev reset)", () => {
    const d = norm(stripSql(read(DOWN)));
    for (const sig of [
      "verify_legal_acceptance(uuid, text, text)",
      "record_legal_acceptance(text, text, text, text)",
      "mark_legal_reauth_verified(uuid, uuid, text, text, text)",
      "claim_legal_reauth_attempt(uuid, text, text, text)",
      "issue_legal_reauth(uuid, text, text, text, text, boolean)",
    ]) {
      expect(d).toContain(`DROP FUNCTION IF EXISTS public.${sig}`);
    }
  });

  it("the verify file asserts the live catalog with a bad column", () => {
    const v = read(VERIFY);
    expect(v).toMatch(/legal_acceptance_rls_enabled/);
    expect(v).toMatch(/legal_acceptance_guard_trigger_enabled/);
    expect(v).toMatch(/AS bad|::int/);
  });

  it("no other migration mentions the table (erasure scrub, grants, policies stay out of it) up to the migration after this one", () => {
    // Bounded to numbers below 185 so PR-D's own migration (if it needs one) is not red by construction.
    const others = readdirSync(MIGRATIONS).filter((f) => f.endsWith(".sql") && !f.startsWith("184_") && Number.parseInt(f, 10) < 185);
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
    ["3 add the table to the erasure scrub", () => rawUp + "\nCREATE OR REPLACE FUNCTION public.x() RETURNS void LANGUAGE sql AS $$ SELECT 1; $$;\n-- anonymise_approval_request scrub\nDELETE FROM public.legal_acceptance WHERE founder_id = $1;\n", /no statement may write legal_acceptance/],
    ["4 compute row_hash without text_hash", () => mutate(/\n\s*r\.text_hash,[^\n]*/, ""), /row_hash omits text_hash/],
    ["4b replace text_hash in the hash by a constant expression that still names it", () => mutate(/\n\s*r\.text_hash,/, "\n        CASE WHEN false THEN r.text_hash END,"), /row_hash omits text_hash/],
    ["4c compute row_hash without the row id", () => mutate(/\n\s*r\.id::text,[^\n]*/, ""), /row_hash omits id/],
    ["4d compute row_hash without the intent id", () => mutate(/\n\s*r\.event_id::text,[^\n]*/, ""), /row_hash omits event_id/],
    ["5 skip the intent consumption", () => mutate(/SET consumed_at = now\(\)/, "SET verified_at = verified_at"), /every decision must consume its intent/],
    ["6 accept an event bound to another text hash", () => mutate(/v_event\.text_hash <> p_text_hash/, "false"), /event bound to another text hash/],
    ["7a drop the auth.uid() check", () => mutate(/IF auth\.uid\(\) IS NULL THEN/, "IF false THEN"), /record: auth\.uid\(\) check missing/],
    ["7b weaken the audience check to a blocklist of the runtime audience", () => mutate(/\(auth\.jwt\(\) ->> 'aud'\) IS DISTINCT FROM 'authenticated' THEN/, "(auth.jwt() ->> 'aud') = 'soleur-runtime' THEN"), /audience must be exactly 'authenticated'/],
    ["7c drop the web-session requirement", () => mutate(/IF v_session IS NULL THEN/, "IF false THEN"), /a web session id is required/],
    ["7d drop the user/key/session binding of the intent lookup", () => mutate(/AND session_id = v_session\n/, "AND true\n"), /event lookup must be bound/],
    ["7e drop the two-tab lock", () => mutate(/PERFORM pg_advisory_xact_lock\(hashtextextended\(auth\.uid\(\)/, "PERFORM 1 WHERE hashtextextended(auth.uid()"), /two tabs must be serialised/],
    ["8 add a client write grant", () => rawUp + "\nGRANT INSERT ON TABLE public.legal_acceptance TO authenticated;\n", /table grants must be exactly/],
    ["8b add a client write grant without the TABLE keyword", () => rawUp + "\nGRANT INSERT ON public.legal_acceptance TO anon;\n", /table grants must be exactly|unexpected GRANT/],
    ["8c add a blanket grant", () => rawUp + "\nGRANT ALL ON ALL TABLES IN SCHEMA public TO service_role;\n", /ALL TABLES/],
    ["9 add a foreign key on founder_id", () => mutate(/founder_id\s+uuid\s+NOT NULL/, "founder_id uuid NOT NULL REFERENCES public.users(id) ON DELETE SET NULL"), /no foreign key/],
    ["10 drop the search_path pin from record", () => mutate(/(FUNCTION public\.record_legal_acceptance\([\s\S]*?)SET search_path = public, pg_temp/, "$1"), /record_legal_acceptance: search_path not pinned/],
    ["11 make the triggers origin-only again", () => mutate("ENABLE ALWAYS TRIGGER legal_acceptance_guard", "ENABLE TRIGGER legal_acceptance_guard"), /must be ENABLE ALWAYS/],
    ["12 neuter the guard's refusal", () => mutate(/RAISE EXCEPTION 'legal acceptance: records are write-once[^;]*;/, "NULL;"), /guard must refuse UPDATE/],
    ["13 drop the guard's consumed-intent requirement", () => mutate(/AND e\.consumed_at IS NOT NULL/, "AND true"), /consumed intent/],
    ["14 let a tampered row read as accepted", () => mutate(/WHEN NOT v_ok THEN 'invalid'/, "WHEN false THEN 'invalid'"), /verify must fail closed/],
    ["15 let claim skip hash validation", () => mutate(/(FUNCTION public\.claim_legal_reauth_attempt\([\s\S]*?)OR p_text_hash IS NULL OR p_text_hash !~ '\^\[0-9a-f\]\{64\}\$'/, "$1"), /claim_legal_reauth_attempt: must validate p_text_hash/],
    ["16 unbind mark from the event id", () => mutate(/WHERE id = p_event_id AND user_id = p_user_id/, "WHERE user_id = p_user_id"), /mark: must be bound to the event id/],
    ["17 move the purge after the early return", () => mutate(/\n\s*-- Challenge rows are transient[^\n]*\n\s*DELETE FROM public\.legal_reauth_event WHERE created_at < now\(\) - interval '30 days';/, ""), /30-day purge must run before any early return/],
    ["18 let a runtime-audience token read the record", () => mutate(/ AND \(auth\.jwt\(\) ->> 'aud'\) = 'authenticated'\);/, ");"), /exactly one permissive policy/],
    ["18b turn the audience whitelist back into a blocklist in the policy", () => mutate(/\(auth\.jwt\(\) ->> 'aud'\) = 'authenticated'\);/, "(auth.jwt() ->> 'aud') IS DISTINCT FROM 'soleur-runtime');"), /exactly one permissive policy/],
    ["19 add a column that the hash does not cover", () => mutate(/  surface        text        NOT NULL DEFAULT 'web'/, "  extra_note     text,\n  surface        text        NOT NULL DEFAULT 'web'"), /row_hash omits extra_note/],
    ["20 hash a constant instead of the choice column", () => mutate(/\n(\s*)r\.choice,/, "\n$1left(r.choice, 0),"), /row_hash omits choice/],
    ["21 append a statement that disables the guard trigger", () => rawUp + "\nALTER TABLE public.legal_acceptance DISABLE TRIGGER legal_acceptance_guard;\n", /disable the guard trigger/],
    ["22 append a statement that disables row level security", () => rawUp + "\nALTER TABLE public.legal_acceptance DISABLE ROW LEVEL SECURITY;\n", /disable the guard trigger or row level security/],
    ["23 append a DROP TRIGGER for the guard", () => rawUp + "\nDROP TRIGGER legal_acceptance_guard ON public.legal_acceptance;\n", /DROP TRIGGER comes after/],
    ["24 append a DROP POLICY for the jti deny", () => rawUp + "\nDROP POLICY legal_acceptance_jti_not_denied ON public.legal_acceptance;\n", /DROP POLICY comes after/],
    ["25 flip the 5-minute code freshness comparison", () => mutate(/v_event\.verified_at < now\(\) - interval '5 minutes' THEN\n      RETURN jsonb_build_object\('outcome', 'code_expired'\)/, "v_event.verified_at > now() - interval '5 minutes' THEN\n      RETURN jsonb_build_object('outcome', 'code_expired')"), /5-minute code freshness predicate/],
    ["26 widen the consume statement with an OR true", () => mutate(/WHERE id = v_event\.id AND consumed_at IS NULL AND superseded_at IS NULL;\n  IF NOT FOUND THEN\n    RAISE EXCEPTION 'legal acceptance: concurrent/, "WHERE id = v_event.id OR true AND consumed_at IS NULL AND superseded_at IS NULL;\n  IF NOT FOUND THEN\n    RAISE EXCEPTION 'legal acceptance: concurrent"), /consume statement is not the reviewed one/],
    ["27 reuse a stale-code intent again", () => mutate(/\n\s*AND \(verified_at IS NULL OR verified_at >= now\(\) - interval '5 minutes'\)/, ""), /reused intent must match the version/],
    ["28 reuse an intent of another version", () => mutate(/\n\s*AND version = p_version/, ""), /reused intent must match the version/],
    ["29 let claim burn attempts on a stale confirmed code", () => mutate(/'outcome', 'code_stale'/, "'outcome', 'allowed'"), /stale confirmed code must be its own outcome/],
    ["30 let a NULL checksum comparison read as accepted", () => mutate(/v_ok := COALESCE\(([^;]*), false\);/, "v_ok := $1;"), /NULL checksum comparison/],
  ];

  it("the battery is not silently shrunk (a floor on the number of rows)", () => {
    expect(rows.length).toBeGreaterThanOrEqual(40);
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
