import { describe, it, expect } from "vitest";
import { readFileSync, readdirSync } from "node:fs";
import path from "node:path";

// Source-side pin for 179_delete_oauth_credential.sql (#11524, ADR-048).
//
// The ONLY thing protecting the user's `anthropic` api_key fallback row from
// this RPC is the hardcoded provider literal inside the DELETE, and the only
// thing keeping it off the API roles is the REVOKE/GRANT set. A future
// CREATE OR REPLACE that widens either must fail here.
//
// SCOPE: this file pins 179 ONLY. A later migration that redefines or
// re-grants the function is caught by the cross-migration scan at the bottom
// (no other migration may mention the function at all).
//
// File-parse test. Pipeline: strip comments -> blank every single-quoted
// string literal (the COMMENT ON text and any '' escapes), so prose can never
// satisfy a header/GRANT contract -> match on STATEMENT FORM. The function
// body is read from the comment-stripped (but NOT blanked) text because its
// 'anthropic_oauth' literal is the thing being pinned. Each contract has an
// in-test mutation (applied to an in-memory COPY; the file on disk is never
// touched) that must change the executable SQL and flip the check red.

const MIG_DIR = path.join(__dirname, "../../supabase/migrations");
const MIG_PATH = path.join(MIG_DIR, "179_delete_oauth_credential.sql");

const stripComments = (sql: string) =>
  sql.replace(/\/\*[\s\S]*?\*\//g, "").replace(/--[^\n]*/g, "");

/** Replace every single-quoted literal (with '' escapes) by ''. */
const blankStrings = (sql: string) => sql.replace(/'(?:[^']|'')*'/g, "''");

interface Prepared {
  /** Comments removed; string literals intact. */
  stripped: string;
  /** Comments removed AND string literals blanked. */
  blanked: string;
  /** CREATE ... FUNCTION up to (excluding) `AS $$`, blanked; null if absent. */
  header: string | null;
  /** Text between `AS $$` and `$$`, literals intact; null if absent. */
  body: string | null;
}

function prep(rawSql: string): Prepared {
  const stripped = stripComments(rawSql);
  const blanked = blankStrings(stripped);
  const head = /CREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\s+public\.delete_oauth_credential[\s\S]*?(?=\bAS\s+\$\$)/i.exec(
    blanked,
  );
  const body = /\bAS\s+\$\$([\s\S]*?)\$\$/i.exec(stripped);
  return {
    stripped,
    blanked,
    header: head ? head[0] : null,
    body: body ? body[1] : null,
  };
}

const FN = "public\\.delete_oauth_credential\\s*\\(\\s*uuid\\s*\\)";
const count = (s: string, re: RegExp) => (s.match(re) ?? []).length;

/** Every GRANT statement that touches this function (or ALL FUNCTIONS in a schema). */
function grantees(blanked: string): { statements: number; set: Set<string> } {
  const set = new Set<string>();
  let statements = 0;
  for (const stmt of blanked.split(";")) {
    if (!/^\s*GRANT\b/i.test(stmt)) continue;
    const touchesFn =
      new RegExp(FN, "i").test(stmt) ||
      /\bdelete_oauth_credential\b/i.test(stmt) ||
      /\bON\s+ALL\s+FUNCTIONS\s+IN\s+SCHEMA\b/i.test(stmt);
    if (!touchesFn) continue;
    statements++;
    const to = /\bTO\s+([\s\S]+)$/i.exec(stmt);
    if (!to) {
      set.add("<unparseable>");
      continue;
    }
    const list = to[1].replace(/\bWITH\s+GRANT\s+OPTION\b/i, "");
    for (const g of list.split(",")) {
      const name = g
        .replace(/["\s]/g, "")
        .replace(/^GROUP/i, "")
        .toLowerCase();
      if (name) set.add(name);
    }
  }
  return { statements, set };
}

/** name -> predicate over the RAW source text. */
const CONTRACTS: Record<string, (raw: string) => boolean> = {
  "defined as CREATE [OR REPLACE] FUNCTION public.delete_oauth_credential(p_user_id uuid)": (r) =>
    /CREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\s+public\.delete_oauth_credential\s*\(\s*p_user_id\s+uuid\s*\)/.test(
      prep(r).blanked,
    ),
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
    const sets = [...header.matchAll(/\bSET\s+search_path\s*(?:=|\bTO\b)\s*([^\n]*)/gi)];
    if (sets.length !== 1) return false;
    const parts = sets[0][1].split(",").map((p) => p.trim().toLowerCase());
    return parts.length === 2 && parts[0] === "public" && parts[1] === "pg_temp";
  },
  "exactly one DELETE FROM and exactly one string literal, 'anthropic_oauth'": (r) => {
    const { stripped, body } = prep(r);
    if (body === null) return false;
    return (
      count(stripped, /\bDELETE\s+FROM\b/gi) === 1 &&
      count(body, /\bDELETE\s+FROM\b/gi) === 1 &&
      count(body, /'(?:[^']|'')*'/g) === 1 &&
      count(body, /'anthropic_oauth'/g) === 1
    );
  },
  "DELETE FROM public.api_keys ... provider = 'anthropic_oauth' is the only provider predicate": (r) => {
    const { body } = prep(r);
    if (body === null) return false;
    return (
      /DELETE\s+FROM\s+public\.api_keys\s+WHERE\s+user_id\s*=\s*p_user_id\s+AND\s+provider\s*=\s*'anthropic_oauth'\s+RETURNING/i.test(
        body,
      ) && count(body, /\bprovider\b/gi) === 1
    );
  },
  "never touches the 'anthropic' provider": (r) => {
    const { body } = prep(r);
    return body !== null && !/'anthropic'/i.test(body) && !/provider\s*=\s*'anthropic'/i.test(prep(r).stripped);
  },
  "REVOKE EXECUTE FROM PUBLIC": (r) =>
    new RegExp(`REVOKE\\s+EXECUTE\\s+ON\\s+FUNCTION\\s+${FN}\\s+FROM\\s+PUBLIC\\s*;`, "i").test(prep(r).blanked),
  "REVOKE EXECUTE FROM authenticated": (r) =>
    new RegExp(`REVOKE\\s+EXECUTE\\s+ON\\s+FUNCTION\\s+${FN}\\s+FROM\\s+authenticated\\s*;`, "i").test(
      prep(r).blanked,
    ),
  "REVOKE EXECUTE FROM anon": (r) =>
    new RegExp(`REVOKE\\s+EXECUTE\\s+ON\\s+FUNCTION\\s+${FN}\\s+FROM\\s+anon\\s*;`, "i").test(prep(r).blanked),
  "GRANT EXECUTE TO service_role": (r) =>
    new RegExp(`GRANT\\s+EXECUTE\\s+ON\\s+FUNCTION\\s+${FN}\\s+TO\\s+service_role\\s*;`, "i").test(
      prep(r).blanked,
    ),
  "every GRANT touching the function (EXECUTE|ALL, ON FUNCTION|ON ALL FUNCTIONS) grants to exactly {service_role}": (r) => {
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
const FN_SIG = "public.delete_oauth_credential(uuid)";

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
    mutate: (r) => r + `\nGRANT EXECUTE ON FUNCTION ${FN_SIG} TO authenticated;\n`,
  },
  {
    label: "multi-role GRANT TO authenticated, anon",
    breaks: GRANT_ALL_TARGET,
    mutate: (r) => r + `\nGRANT EXECUTE ON FUNCTION ${FN_SIG} TO authenticated, anon;\n`,
  },
  {
    label: "GRANT ALL ON FUNCTION",
    breaks: GRANT_ALL_TARGET,
    mutate: (r) => r + `\nGRANT ALL ON FUNCTION ${FN_SIG} TO authenticated;\n`,
  },
  {
    label: "GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA",
    breaks: GRANT_ALL_TARGET,
    mutate: (r) => r + "\nGRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO anon;\n",
  },
  {
    label: "ALTER DEFAULT PRIVILEGES",
    breaks: "no ALTER DEFAULT PRIVILEGES",
    mutate: (r) =>
      r +
      "\nALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT EXECUTE ON FUNCTIONS TO authenticated;\n",
  },
];

const raw = readFileSync(MIG_PATH, "utf8");

describe("179_delete_oauth_credential.sql — source contract", () => {
  for (const [name, check] of Object.entries(CONTRACTS)) {
    it(name, () => {
      expect(check(raw)).toBe(true);
    });
  }

  it("comment prose cannot satisfy a contract (the function removed, comments left)", () => {
    const commentsOnly = raw.replace(/CREATE OR REPLACE FUNCTION[\s\S]*?\$\$;\n/, "");
    expect(CONTRACTS[SEC_DEF](commentsOnly)).toBe(false);
    expect(CONTRACTS[ONE_DELETE](commentsOnly)).toBe(false);
    expect(CONTRACTS[PROVIDER_ONLY](commentsOnly)).toBe(false);
  });

  describe("mutation proof (in-memory copy; each mutation must change executable SQL and go red)", () => {
    for (const { label, breaks, mutate } of MUTATIONS) {
      it(`${label} breaks: ${breaks}`, () => {
        const mutated = mutate(raw);
        // The mutation landed in EXECUTABLE SQL (not just a comment).
        expect(prep(mutated).stripped).not.toBe(prep(raw).stripped);
        expect(CONTRACTS[breaks](mutated)).toBe(false);
        expect(CONTRACTS[breaks](raw)).toBe(true); // and it is green unmutated
      });
    }

    it("every contract has at least one mutation that flips it", () => {
      const covered = new Set(MUTATIONS.map((m) => m.breaks));
      const sets = [
        "REVOKE EXECUTE FROM authenticated",
        SEC_DEF,
        SEARCH_PATH,
        ONE_DELETE,
        PROVIDER_ONLY,
        GRANT_ALL_TARGET,
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

  it("the down migration only drops the function", () => {
    const down = stripComments(
      readFileSync(path.join(MIG_DIR, "179_delete_oauth_credential.down.sql"), "utf8"),
    ).trim();
    expect(down).toBe(`DROP FUNCTION IF EXISTS ${FN_SIG};`);
  });
});
