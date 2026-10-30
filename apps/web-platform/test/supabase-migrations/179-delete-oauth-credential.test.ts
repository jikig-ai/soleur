import { describe, it, expect } from "vitest";
import { readFileSync, readdirSync } from "node:fs";
import path from "node:path";

// Source-side pin for 179_delete_oauth_credential.sql (#11524, ADR-048).
//
// The ONLY thing protecting the user's `anthropic` api_key fallback row from
// this RPC is the hardcoded provider literal inside the DELETE, and the only
// thing keeping it off the API roles is the REVOKE/GRANT set. A future
// CREATE OR REPLACE / ALTER FUNCTION / GRANT that widens either must fail here.
//
// SCOPE: this file pins 179 ONLY. A later migration that redefines or
// re-grants the function is caught by the cross-migration scan at the bottom
// (no other migration may mention the function at all; no later migration may
// grant ON ALL FUNCTIONS|ROUTINES IN SCHEMA to anon/authenticated/PUBLIC).
//
// File-parse test. ONE string-aware lexer pass (`lex`) understands '...' (with
// '' and E'\'' escapes), "quoted identifiers", $tag$...$tag$ bodies, `--` and
// nested block comments TOGETHER, so a `--` or `/*` inside a literal can never
// hide a GRANT, and a quote inside a comment can never open a literal. It
// yields: `code` (comments removed, literals blanked to '', each dollar-quoted
// body replaced by a $$#n$$ marker -> statement-level checks) and `kept`
// (comments removed, everything else intact -> body/literal checks). The
// central contract is a CLOSED SET: the file's statements must equal the
// reviewed list, in order; anything else (ALTER FUNCTION, DO/dynamic SQL, extra
// GRANT/REVOKE, TRUNCATE, a second CREATE...) fails by name. Each contract has
// in-test mutations (applied to an in-memory COPY; the file on disk is never
// touched) that must change the executable SQL and flip the check red.

const MIG_DIR = path.join(__dirname, "../../supabase/migrations");
const MIG_PATH = path.join(MIG_DIR, "179_delete_oauth_credential.sql");

// ---------------------------------------------------------------------------
// The single lexer pass.
// ---------------------------------------------------------------------------

interface Lexed {
  /** Comments removed, string literals blanked, dollar bodies -> $$#n$$. */
  code: string;
  /** Comments removed; literals and (recursively lexed) bodies intact. */
  kept: string;
  /** Dollar-quoted bodies, each lexed as SQL (index = n of its $$#n$$ marker). */
  bodies: Lexed[];
  errors: string[];
}

const IDENT_CHAR = /[A-Za-z0-9_$\u0080-￿]/;
const DOLLAR_TAG = /\$(?:[A-Za-z_\u0080-￿][A-Za-z0-9_\u0080-￿]*)?\$/y;

function lex(sql: string, depth = 0): Lexed {
  let code = "";
  let kept = "";
  const bodies: Lexed[] = [];
  const errors: string[] = [];
  const n = sql.length;
  let i = 0;
  while (i < n) {
    const c = sql[i];
    const c2 = sql[i + 1];
    if (c === "-" && c2 === "-") {
      const e = sql.indexOf("\n", i);
      i = e === -1 ? n : e; // newline itself is kept by the next iteration
      code += " ";
      kept += " ";
      continue;
    }
    if (c === "/" && c2 === "*") {
      let d = 1;
      let j = i + 2;
      while (j < n && d > 0) {
        if (sql[j] === "/" && sql[j + 1] === "*") {
          d++;
          j += 2;
        } else if (sql[j] === "*" && sql[j + 1] === "/") {
          d--;
          j += 2;
        } else j++;
      }
      if (d > 0) errors.push("unterminated block comment");
      i = j;
      code += " ";
      kept += " ";
      continue;
    }
    if (c === "'") {
      const escapes = i > 0 && /[eE]/.test(sql[i - 1]) && (i < 2 || !IDENT_CHAR.test(sql[i - 2]));
      let j = i + 1;
      let closed = false;
      while (j < n) {
        if (escapes && sql[j] === "\\") {
          j += 2;
          continue;
        }
        if (sql[j] === "'") {
          if (sql[j + 1] === "'") {
            j += 2;
            continue;
          }
          closed = true;
          break;
        }
        j++;
      }
      if (!closed) errors.push("unterminated string literal");
      const end = Math.min(j + 1, n);
      kept += sql.slice(i, end);
      code += "''";
      i = end;
      continue;
    }
    if (c === '"') {
      let j = i + 1;
      while (j < n) {
        if (sql[j] === '"') {
          if (sql[j + 1] === '"') {
            j += 2;
            continue;
          }
          break;
        }
        j++;
      }
      if (j >= n) errors.push("unterminated quoted identifier");
      const end = Math.min(j + 1, n);
      const t = sql.slice(i, end);
      kept += t;
      code += t;
      i = end;
      continue;
    }
    if (c === "$" && (i === 0 || !IDENT_CHAR.test(sql[i - 1]))) {
      DOLLAR_TAG.lastIndex = i;
      const m = DOLLAR_TAG.exec(sql);
      if (m) {
        const tag = m[0];
        const close = sql.indexOf(tag, i + tag.length);
        const rawBody = close === -1 ? sql.slice(i + tag.length) : sql.slice(i + tag.length, close);
        if (close === -1) errors.push(`unterminated dollar-quoted body ${tag}`);
        const inner: Lexed =
          depth < 8 ? lex(rawBody, depth + 1) : { code: rawBody, kept: rawBody, bodies: [], errors: [] };
        code += `$$#${bodies.length}$$`;
        bodies.push(inner);
        kept += tag + inner.kept + (close === -1 ? "" : tag);
        i = close === -1 ? n : close + tag.length;
        continue;
      }
    }
    code += c;
    kept += c;
    i++;
  }
  return { code, kept, bodies, errors };
}

const normalize = (s: string) => s.replace(/\s+/g, " ").trim();
const statementsOf = (code: string) => code.split(";").map(normalize).filter(Boolean);
const trunc = (s: string) => (s.length > 140 ? `${s.slice(0, 140)}...` : s);

// ---------------------------------------------------------------------------
// Prepared view of one migration file.
// ---------------------------------------------------------------------------

interface Prepared {
  lexed: Lexed;
  /** Comments removed; literals and bodies intact. */
  stripped: string;
  /** Comments removed, literals blanked, bodies -> markers. */
  blanked: string;
  stmts: string[];
  /** Number of CREATE [OR REPLACE] FUNCTION statements (any function). */
  createCount: number;
  /** First CREATE FUNCTION public.delete_oauth_credential, up to (excluding) `AS $$#n$$`. */
  header: string | null;
  /** The lexed dollar body that header's AS clause points at. */
  body: Lexed | null;
}

function prep(rawSql: string): Prepared {
  const lexed = lex(rawSql);
  const stmts = statementsOf(lexed.code);
  const create = stmts.find((s) => /^CREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\s+public\.delete_oauth_credential\b/i.test(s));
  const asm = create ? /\s+AS\s+\$\$#(\d+)\$\$$/i.exec(create) : null;
  return {
    lexed,
    stripped: lexed.kept,
    blanked: lexed.code,
    stmts,
    createCount: stmts.filter((s) => /^CREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\b/i.test(s)).length,
    header: create && asm ? create.slice(0, asm.index) : null,
    body: asm ? (lexed.bodies[Number(asm[1])] ?? null) : null,
  };
}

const FN = "public\\.delete_oauth_credential\\s*\\(\\s*uuid\\s*\\)";
const count = (s: string, re: RegExp) => (s.match(re) ?? []).length;

// ---------------------------------------------------------------------------
// Closed set: the reviewed statement list, in order.
// ---------------------------------------------------------------------------

const EXPECTED_STATEMENTS: Array<{ name: string; re: RegExp }> = [
  {
    name: "CREATE [OR REPLACE] FUNCTION public.delete_oauth_credential(p_user_id uuid)",
    re: /^CREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\s+public\.delete_oauth_credential\s*\(\s*p_user_id\s+uuid\s*\)\s[\s\S]*\sAS\s+\$\$#\d+\$\$$/i,
  },
  {
    name: "COMMENT ON FUNCTION public.delete_oauth_credential(uuid)",
    // Adjacent literals ('a' 'b') concatenate in SQL, so the blanked form is one or more ''.
    re: new RegExp(`^COMMENT\\s+ON\\s+FUNCTION\\s+${FN}\\s+IS\\s+''(?:\\s+'')*$`, "i"),
  },
  ...["PUBLIC", "authenticated", "anon"].map((role) => ({
    name: `REVOKE EXECUTE ... FROM ${role}`,
    re: new RegExp(`^REVOKE\\s+EXECUTE\\s+ON\\s+FUNCTION\\s+${FN}\\s+FROM\\s+${role}$`, "i"),
  })),
  {
    name: "GRANT EXECUTE ... TO service_role",
    re: new RegExp(`^GRANT\\s+EXECUTE\\s+ON\\s+FUNCTION\\s+${FN}\\s+TO\\s+service_role$`, "i"),
  },
];

/** Empty array == the file's statements are exactly the reviewed list. */
function closedSetViolations(p: Prepared): string[] {
  const v: string[] = p.lexed.errors.map((e) => `lexer: ${e}`);
  p.stmts.forEach((s, idx) => {
    const exp = EXPECTED_STATEMENTS[idx];
    if (!exp) v.push(`unexpected extra statement #${idx + 1}: ${trunc(s)}`);
    else if (!exp.re.test(s)) v.push(`statement #${idx + 1} is not the reviewed "${exp.name}": ${trunc(s)}`);
  });
  if (p.stmts.length < EXPECTED_STATEMENTS.length) {
    v.push(`missing reviewed statement "${EXPECTED_STATEMENTS[p.stmts.length].name}"`);
  }
  return v;
}

// ---------------------------------------------------------------------------
// GRANT tokenizer.
// ---------------------------------------------------------------------------

const cleanRole = (g: string) =>
  g
    .replace(/["\s]/g, "")
    .replace(/^GROUP/i, "")
    .toLowerCase();

/** Every GRANT that touches this function, ALL FUNCTIONS|ROUTINES IN SCHEMA, or is a role-membership grant. */
function grantees(code: string): { statements: number; set: Set<string> } {
  const set = new Set<string>();
  let statements = 0;
  for (const stmt of statementsOf(code)) {
    if (!/^GRANT\b/i.test(stmt)) continue;
    const membership = !/\bON\b/i.test(stmt); // GRANT <role> TO <role>
    const touchesFn =
      new RegExp(FN, "i").test(stmt) ||
      /\bdelete_oauth_credential\b/i.test(stmt) ||
      /\bON\s+ALL\s+(?:FUNCTIONS|ROUTINES)\s+IN\s+SCHEMA\b/i.test(stmt);
    if (!membership && !touchesFn) continue;
    statements++;
    if (membership) {
      set.add("<role-membership>");
      continue;
    }
    const to = /\bTO\s+([\s\S]+)$/i.exec(stmt);
    if (!to) {
      set.add("<unparseable>");
      continue;
    }
    for (const g of to[1].replace(/\bWITH\s+GRANT\s+OPTION\b/i, "").split(",")) {
      const name = cleanRole(g);
      if (name) set.add(name);
    }
  }
  return { statements, set };
}

/** Statements granting ON ALL FUNCTIONS|ROUTINES IN SCHEMA to anon/authenticated/PUBLIC. */
function broadFunctionGrants(sql: string): string[] {
  const out: string[] = [];
  for (const s of statementsOf(lex(sql).code)) {
    if (!/^GRANT\b/i.test(s)) continue;
    const m = /\bON\s+ALL\s+(?:FUNCTIONS|ROUTINES)\s+IN\s+SCHEMA\b[\s\S]*?\bTO\s+([\s\S]+)$/i.exec(s);
    if (!m) continue;
    const roles = m[1].replace(/\bWITH\s+GRANT\s+OPTION\b/i, "").split(",").map(cleanRole);
    if (roles.some((r) => r === "anon" || r === "authenticated" || r === "public")) out.push(trunc(s));
  }
  return out;
}

// ---------------------------------------------------------------------------
// Contracts.
// ---------------------------------------------------------------------------

const BODY_FORBIDDEN =
  /\b(?:INSERT|UPDATE|MERGE|TRUNCATE|ALTER|DROP|CREATE|GRANT|REVOKE|COPY|EXECUTE|CALL|DO)\b/i;

/** name -> predicate over the RAW source text. */
const CONTRACTS: Record<string, (raw: string) => boolean> = {
  "defined as CREATE [OR REPLACE] FUNCTION public.delete_oauth_credential(p_user_id uuid)": (r) =>
    prep(r).stmts.some((s) =>
      /^CREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\s+public\.delete_oauth_credential\s*\(\s*p_user_id\s+uuid\s*\)/i.test(s),
    ),
  "exactly one CREATE FUNCTION statement in the file": (r) => prep(r).createCount === 1,
  "CLOSED SET: statements are exactly [CREATE, COMMENT, REVOKE x3 (PUBLIC, authenticated, anon), GRANT service_role]": (r) =>
    closedSetViolations(prep(r)).length === 0,
  "LANGUAGE sql exactly (function header)": (r) => {
    const { header } = prep(r);
    if (header === null) return false;
    const langs = [...header.matchAll(/\bLANGUAGE\s+([A-Za-z_]\w*|'')/gi)].map((m) => m[1].toLowerCase());
    return langs.length === 1 && langs[0] === "sql";
  },
  "SECURITY DEFINER (function header only)": (r) => {
    const { header } = prep(r);
    return (
      header !== null &&
      /\bSECURITY\s+DEFINER\b/i.test(header) &&
      !/\bSECURITY\s+INVOKER\b/i.test(header)
    );
  },
  "SET search_path = public, pg_temp (function header, exact)": (r) => {
    const { header } = prep(r);
    if (header === null) return false;
    const sets = [...header.matchAll(/\bSET\s+search_path\s*(?:=|\bTO\b)\s*(.*)$/gi)];
    if (sets.length !== 1) return false;
    const parts = sets[0][1].split(",").map((p) => p.trim().toLowerCase());
    return parts.length === 2 && parts[0] === "public" && parts[1] === "pg_temp";
  },
  "body is one read-only-shaped statement (no INSERT/UPDATE/MERGE/TRUNCATE/ALTER/DDL/dynamic SQL)": (r) => {
    const { body } = prep(r);
    if (body === null || body.errors.length > 0) return false;
    const stmts = statementsOf(body.code);
    return stmts.length === 1 && /^(?:WITH|SELECT)\b/i.test(stmts[0]) && !BODY_FORBIDDEN.test(stmts[0]);
  },
  "exactly one DELETE FROM and exactly one string literal, 'anthropic_oauth'": (r) => {
    const { stripped, body } = prep(r);
    if (body === null) return false;
    return (
      count(stripped, /\bDELETE\s+FROM\b/gi) === 1 &&
      count(body.kept, /\bDELETE\s+FROM\b/gi) === 1 &&
      count(body.kept, /'(?:[^']|'')*'/g) === 1 &&
      count(body.kept, /'anthropic_oauth'/g) === 1
    );
  },
  "DELETE FROM public.api_keys ... provider = 'anthropic_oauth' is the only provider predicate": (r) => {
    const { body } = prep(r);
    if (body === null) return false;
    return (
      /DELETE\s+FROM\s+public\.api_keys\s+WHERE\s+user_id\s*=\s*p_user_id\s+AND\s+provider\s*=\s*'anthropic_oauth'\s+RETURNING/i.test(
        body.kept,
      ) && count(body.kept, /\bprovider\b/gi) === 1
    );
  },
  "never touches the 'anthropic' provider": (r) => {
    const { body, stripped } = prep(r);
    return body !== null && !/'anthropic'/i.test(body.kept) && !/provider\s*=\s*'anthropic'/i.test(stripped);
  },
  "REVOKE EXECUTE FROM PUBLIC": (r) =>
    new RegExp(`(?:^|;)\\s*REVOKE\\s+EXECUTE\\s+ON\\s+FUNCTION\\s+${FN}\\s+FROM\\s+PUBLIC\\s*;`, "i").test(prep(r).blanked),
  "REVOKE EXECUTE FROM authenticated": (r) =>
    new RegExp(`(?:^|;)\\s*REVOKE\\s+EXECUTE\\s+ON\\s+FUNCTION\\s+${FN}\\s+FROM\\s+authenticated\\s*;`, "i").test(
      prep(r).blanked,
    ),
  "REVOKE EXECUTE FROM anon": (r) =>
    new RegExp(`(?:^|;)\\s*REVOKE\\s+EXECUTE\\s+ON\\s+FUNCTION\\s+${FN}\\s+FROM\\s+anon\\s*;`, "i").test(prep(r).blanked),
  "GRANT EXECUTE TO service_role": (r) =>
    new RegExp(`(?:^|;)\\s*GRANT\\s+EXECUTE\\s+ON\\s+FUNCTION\\s+${FN}\\s+TO\\s+service_role\\s*;`, "i").test(
      prep(r).blanked,
    ),
  "every GRANT touching the function (EXECUTE|ALL, ON FUNCTION|ON ALL FUNCTIONS|ROUTINES, role-membership) grants to exactly {service_role}": (r) => {
    const { statements, set } = grantees(prep(r).blanked);
    return statements >= 1 && set.size === 1 && set.has("service_role");
  },
  "no ALTER DEFAULT PRIVILEGES": (r) => !/\bALTER\s+DEFAULT\s+PRIVILEGES\b/i.test(prep(r).blanked),
};

const DEL = "DELETE FROM and exactly one string literal";
const key = (frag: string) => {
  const k = Object.keys(CONTRACTS).find((n) => n.includes(frag));
  if (!k) throw new Error(`no contract containing ${frag}`);
  return k;
};

const GRANT_ALL_TARGET = key("every GRANT touching");
const ONE_DELETE = key(DEL);
const SEC_DEF = key("SECURITY DEFINER");
const SEARCH_PATH = key("SET search_path");
const PROVIDER_ONLY = key("only provider predicate");
const CLOSED_SET = key("CLOSED SET");
const ONE_CREATE = key("exactly one CREATE FUNCTION");
const LANG_SQL = key("LANGUAGE sql exactly");
const BODY_SHAPE = key("body is one read-only-shaped");
const FN_SIG = "public.delete_oauth_credential(uuid)";

const append = (sql: string) => (r: string) => `${r}\n${sql}\n`;
const prependToBody = (sql: string) => (r: string) => r.replace("AS $$\n  WITH d AS (", `AS $$\n  ${sql}\n  WITH d AS (`);

/** contract name -> mutation of the RAW source that must break it. */
const MUTATIONS: Array<{ label: string; breaks: string; mutate: (raw: string) => string }> = [
  {
    label: "provider literal anthropic_oauth -> anthropic",
    breaks: PROVIDER_ONLY,
    mutate: (r) => r.replace("AND provider = 'anthropic_oauth'", "AND provider = 'anthropic'"),
  },
  {
    label: "provider IN ('anthropic_oauth', 'anthropic')",
    breaks: PROVIDER_ONLY,
    mutate: (r) =>
      r.replace(
        "AND provider = 'anthropic_oauth'",
        "AND provider IN ('anthropic_oauth', 'anthropic')",
      ),
  },
  {
    label: "second DELETE CTE touching anthropic",
    breaks: ONE_DELETE,
    mutate: (r) =>
      r.replace(
        "    RETURNING 1\n  )\n  SELECT EXISTS (SELECT 1 FROM d);",
        "    RETURNING 1\n  ), d2 AS (\n    DELETE FROM public.api_keys\n    WHERE user_id = p_user_id\n      AND provider = 'anthropic'\n    RETURNING 1\n  )\n  SELECT EXISTS (SELECT 1 FROM d);",
      ),
  },
  {
    label: "drop REVOKE FROM authenticated",
    breaks: "REVOKE EXECUTE FROM authenticated",
    mutate: (r) =>
      r.replace(`REVOKE EXECUTE ON FUNCTION ${FN_SIG} FROM authenticated;\n`, ""),
  },
  {
    label: "drop REVOKE FROM authenticated (closed set sees it too)",
    breaks: CLOSED_SET,
    mutate: (r) =>
      r.replace(`REVOKE EXECUTE ON FUNCTION ${FN_SIG} FROM authenticated;\n`, ""),
  },
  {
    label: "drop SET search_path",
    breaks: SEARCH_PATH,
    mutate: (r) => r.replace("SET search_path = public, pg_temp\n", ""),
  },
  {
    label: "search_path = public, pg_temp, extensions",
    breaks: SEARCH_PATH,
    mutate: (r) =>
      r.replace(
        "SET search_path = public, pg_temp\n",
        "SET search_path = public, pg_temp, extensions\n",
      ),
  },
  {
    label: "drop SECURITY DEFINER",
    breaks: SEC_DEF,
    mutate: (r) => r.replace("SECURITY DEFINER\n", ""),
  },
  {
    label: "SECURITY INVOKER with SECURITY DEFINER / search_path only in the COMMENT text",
    breaks: SEC_DEF,
    mutate: (r) =>
      r
        .replace("SECURITY DEFINER\n", "SECURITY INVOKER\n")
        .replace(
          "See #11524, ADR-048.';",
          "See #11524, ADR-048. SECURITY DEFINER SET search_path = public, pg_temp';",
        ),
  },
  {
    label: "GRANT EXECUTE ... TO authenticated (extra single-role GRANT)",
    breaks: GRANT_ALL_TARGET,
    mutate: append(`GRANT EXECUTE ON FUNCTION ${FN_SIG} TO authenticated;`),
  },
  {
    label: "multi-role GRANT TO authenticated, anon",
    breaks: GRANT_ALL_TARGET,
    mutate: append(`GRANT EXECUTE ON FUNCTION ${FN_SIG} TO authenticated, anon;`),
  },
  {
    label: "GRANT ALL ON FUNCTION",
    breaks: GRANT_ALL_TARGET,
    mutate: append(`GRANT ALL ON FUNCTION ${FN_SIG} TO authenticated;`),
  },
  {
    label: "GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA",
    breaks: GRANT_ALL_TARGET,
    mutate: append("GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO anon;"),
  },
  {
    label: "GRANT EXECUTE ON ALL ROUTINES IN SCHEMA",
    breaks: GRANT_ALL_TARGET,
    mutate: append("GRANT EXECUTE ON ALL ROUTINES IN SCHEMA public TO anon;"),
  },
  {
    label: "role-membership GRANT service_role TO authenticated",
    breaks: GRANT_ALL_TARGET,
    mutate: append("GRANT service_role TO authenticated;"),
  },
  {
    label: "GRANT hidden behind a string literal containing '--'",
    breaks: GRANT_ALL_TARGET,
    mutate: append(`SELECT '--'; GRANT EXECUTE ON FUNCTION ${FN_SIG} TO authenticated;`),
  },
  {
    label: "GRANT hidden between string literals containing '/*' and '*/'",
    breaks: GRANT_ALL_TARGET,
    mutate: append(`SELECT '/*'; GRANT EXECUTE ON FUNCTION ${FN_SIG} TO authenticated; SELECT '*/';`),
  },
  {
    label: "ALTER DEFAULT PRIVILEGES",
    breaks: "no ALTER DEFAULT PRIVILEGES",
    mutate: append("ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT EXECUTE ON FUNCTIONS TO authenticated;"),
  },
  // Trailing statements the header/GRANT contracts never see: only the closed set does.
  {
    label: "trailing ALTER FUNCTION ... SECURITY INVOKER",
    breaks: CLOSED_SET,
    mutate: append(`ALTER FUNCTION ${FN_SIG} SECURITY INVOKER;`),
  },
  {
    label: "trailing ALTER FUNCTION ... SET search_path = public",
    breaks: CLOSED_SET,
    mutate: append(`ALTER FUNCTION ${FN_SIG} SET search_path = public;`),
  },
  {
    label: "trailing REVOKE EXECUTE ... FROM service_role",
    breaks: CLOSED_SET,
    mutate: append(`REVOKE EXECUTE ON FUNCTION ${FN_SIG} FROM service_role;`),
  },
  {
    label: "trailing ALTER FUNCTION ... OWNER TO anon",
    breaks: CLOSED_SET,
    mutate: append(`ALTER FUNCTION ${FN_SIG} OWNER TO anon;`),
  },
  {
    label: "dynamic SQL: DO $x$ BEGIN EXECUTE 'GRANT ... TO authenticated'; END $x$",
    breaks: CLOSED_SET,
    mutate: append(
      `DO $x$ BEGIN EXECUTE 'GRANT EXECUTE ON FUNCTION ${FN_SIG} TO authenticated'; END $x$;`,
    ),
  },
  {
    label: "TRUNCATE appended to the file",
    breaks: CLOSED_SET,
    mutate: append("TRUNCATE public.api_keys;"),
  },
  {
    label: "second CREATE OR REPLACE (SECURITY INVOKER, no DELETE) appended",
    breaks: ONE_CREATE,
    mutate: append(
      "CREATE OR REPLACE FUNCTION public.delete_oauth_credential(\n  p_user_id uuid\n) RETURNS boolean\nLANGUAGE sql\nSECURITY INVOKER\nAS $$ SELECT true; $$;",
    ),
  },
  {
    label: "second CREATE OR REPLACE appended (closed set sees it too)",
    breaks: CLOSED_SET,
    mutate: append(
      "CREATE OR REPLACE FUNCTION public.delete_oauth_credential(\n  p_user_id uuid\n) RETURNS boolean\nLANGUAGE sql\nSECURITY INVOKER\nAS $$ SELECT true; $$;",
    ),
  },
  {
    label: "LANGUAGE sql -> plpgsql",
    breaks: LANG_SQL,
    mutate: (r) => r.replace("LANGUAGE sql\n", "LANGUAGE plpgsql\n"),
  },
  {
    label: "body: TRUNCATE statement before the CTE",
    breaks: BODY_SHAPE,
    mutate: prependToBody("TRUNCATE public.api_keys;"),
  },
  {
    label: "body: UPDATE statement before the CTE",
    breaks: BODY_SHAPE,
    mutate: prependToBody("UPDATE public.api_keys SET user_id = user_id;"),
  },
  {
    label: "body: MERGE statement before the CTE",
    breaks: BODY_SHAPE,
    mutate: prependToBody(
      "MERGE INTO public.api_keys t USING public.api_keys s ON t.id = s.id WHEN MATCHED THEN DO NOTHING;",
    ),
  },
  {
    label: "body: INSERT statement before the CTE",
    breaks: BODY_SHAPE,
    mutate: prependToBody("INSERT INTO public.api_keys SELECT * FROM public.api_keys;"),
  },
  {
    label: "body: data-modifying UPDATE CTE inside the single statement",
    breaks: BODY_SHAPE,
    mutate: (r) =>
      r.replace(
        "    RETURNING 1\n  )\n  SELECT EXISTS (SELECT 1 FROM d);",
        "    RETURNING 1\n  ), u AS (\n    UPDATE public.api_keys SET user_id = user_id RETURNING 1\n  )\n  SELECT EXISTS (SELECT 1 FROM d);",
      ),
  },
];

const raw = readFileSync(MIG_PATH, "utf8");

describe("179_delete_oauth_credential.sql — source contract", () => {
  for (const [name, check] of Object.entries(CONTRACTS)) {
    it(name, () => {
      expect(check(raw)).toBe(true);
    });
  }

  it("closed set reports no violations (message names any offending statement)", () => {
    expect(closedSetViolations(prep(raw))).toEqual([]);
  });

  it("comment prose cannot satisfy a contract (the function removed, comments left)", () => {
    const commentsOnly = raw.replace(/CREATE OR REPLACE FUNCTION[\s\S]*?\$\$;\n/, "");
    expect(CONTRACTS[SEC_DEF](commentsOnly)).toBe(false);
    expect(CONTRACTS[ONE_DELETE](commentsOnly)).toBe(false);
    expect(CONTRACTS[PROVIDER_ONLY](commentsOnly)).toBe(false);
    expect(CONTRACTS[CLOSED_SET](commentsOnly)).toBe(false);
  });

  describe("lexer (one pass: comments, string literals and dollar bodies together)", () => {
    it("a '--' or '/*' inside a literal does not eat the following GRANT", () => {
      expect(lex("SELECT '--'; GRANT x TO y;").code).toContain("GRANT x TO y");
      expect(lex("SELECT '/*'; GRANT x TO y; SELECT '*/';").code).toContain("GRANT x TO y");
    });
    it("a quote inside a comment does not open a literal; nested block comments close", () => {
      expect(lex("-- it's\nGRANT x TO y;").code).toContain("GRANT x TO y");
      expect(lex("/* a /* b */ c */ GRANT x TO y;").code).toContain("GRANT x TO y");
    });
    it("'' escapes, E'\\'' escapes and quoted identifiers stay inside their token", () => {
      expect(lex("SELECT 'it''s -- x'; GRANT a TO b;").code).toContain("GRANT a TO b");
      expect(lex("SELECT E'a\\' -- x'; GRANT a TO b;").code).toContain("GRANT a TO b");
      expect(lex('SELECT "a--b"; GRANT a TO b;').code).toContain("GRANT a TO b");
    });
    it("dollar bodies become markers; their content never leaks into statement text", () => {
      const l = lex("DO $x$ BEGIN EXECUTE 'GRANT g TO r'; END $x$; SELECT 1;");
      expect(l.code).not.toMatch(/GRANT|EXECUTE/);
      expect(statementsOf(l.code)).toEqual(["DO $$#0$$", "SELECT 1"]);
      expect(l.bodies[0].kept).toContain("GRANT g TO r");
    });
    it("unterminated tokens are reported", () => {
      expect(lex("SELECT 'abc").errors.length).toBe(1);
      expect(lex("/* abc").errors.length).toBe(1);
      expect(lex("DO $x$ abc").errors.length).toBe(1);
    });
  });

  describe("mutation proof (in-memory copy; each mutation must change executable SQL and go red)", () => {
    for (const { label, breaks, mutate } of MUTATIONS) {
      it(`${label} breaks: ${breaks}`, () => {
        const mutated = mutate(raw);
        // The mutation landed in EXECUTABLE SQL (not just a comment).
        expect(mutated).not.toBe(raw);
        expect(prep(mutated).stripped).not.toBe(prep(raw).stripped);
        expect(CONTRACTS[breaks](mutated)).toBe(false);
        expect(CONTRACTS[breaks](raw)).toBe(true); // and it is green unmutated
      });
    }

    it("closed-set failure names the offending statement", () => {
      const v = closedSetViolations(prep(`${raw}\nALTER FUNCTION ${FN_SIG} OWNER TO anon;\n`));
      expect(v.length).toBe(1);
      expect(v[0]).toMatch(/unexpected extra statement #7: ALTER FUNCTION .*OWNER TO anon/);
    });

    it("every contract has at least one mutation that flips it", () => {
      const covered = new Set(MUTATIONS.map((m) => m.breaks));
      const sets = [
        "REVOKE EXECUTE FROM authenticated",
        SEC_DEF,
        SEARCH_PATH,
        ONE_DELETE,
        PROVIDER_ONLY,
        GRANT_ALL_TARGET,
        CLOSED_SET,
        ONE_CREATE,
        LANG_SQL,
        BODY_SHAPE,
        "no ALTER DEFAULT PRIVILEGES",
      ];
      for (const s of sets) expect(covered.has(s)).toBe(true);
    });
  });
});

describe("179 is the only migration that defines or re-grants delete_oauth_credential", () => {
  it("no other migration mentions the function (a later CREATE OR REPLACE / GRANT / REVOKE would be a silent widening)", () => {
    const offenders = readdirSync(MIG_DIR)
      .filter((f) => f.endsWith(".sql") && !f.startsWith("179_delete_oauth_credential"))
      .filter((f) => /delete_oauth_credential/i.test(readFileSync(path.join(MIG_DIR, f), "utf8")));
    expect(offenders).toEqual([]);
  });

  it("no later migration (ordinal > 179) grants ON ALL FUNCTIONS|ROUTINES IN SCHEMA to anon/authenticated/PUBLIC", () => {
    const offenders: string[] = [];
    for (const f of readdirSync(MIG_DIR)) {
      const ord = /^(\d+)_/.exec(f);
      if (!f.endsWith(".sql") || !ord || Number(ord[1]) <= 179) continue;
      const sql = readFileSync(path.join(MIG_DIR, f), "utf8");
      if (!/ALL\s+(?:FUNCTIONS|ROUTINES)\s+IN\s+SCHEMA/i.test(sql)) continue; // cheap pre-filter
      for (const s of broadFunctionGrants(sql)) offenders.push(`${f}: ${s}`);
    }
    expect(offenders).toEqual([]);
  });

  it("the broad-grant scanner flags anon/authenticated/PUBLIC and ignores service_role-only grants and string/comment prose", () => {
    expect(broadFunctionGrants("GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO anon;").length).toBe(1);
    expect(broadFunctionGrants("grant all on all routines in schema public to postgres, \"authenticated\";").length).toBe(1);
    expect(broadFunctionGrants("GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO PUBLIC;").length).toBe(1);
    expect(broadFunctionGrants("SELECT '--'; GRANT EXECUTE ON ALL ROUTINES IN SCHEMA public TO anon;").length).toBe(1);
    expect(broadFunctionGrants("GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO service_role;")).toEqual([]);
    expect(broadFunctionGrants("-- GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO anon;\nSELECT 'GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO anon';")).toEqual([]);
  });

  it("the down migration only drops the function", () => {
    const down = lex(
      readFileSync(path.join(MIG_DIR, "179_delete_oauth_credential.down.sql"), "utf8"),
    ).code.trim();
    expect(down).toBe(`DROP FUNCTION IF EXISTS ${FN_SIG};`);
  });
});
