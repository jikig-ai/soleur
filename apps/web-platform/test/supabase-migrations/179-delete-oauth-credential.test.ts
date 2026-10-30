import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import path from "node:path";

// Source-side pin for 179_delete_oauth_credential.sql (#11524, ADR-048).
//
// The ONLY thing protecting the user's `anthropic` api_key fallback row from
// this RPC is the hardcoded provider literal inside the DELETE, and the only
// thing keeping it off the API roles is the REVOKE/GRANT set. A future
// CREATE OR REPLACE that widens either must fail here.
//
// File-parse test: the SQL is comment-stripped, then each contract is matched
// on its STATEMENT FORM (not a bare token), so prose in comments or the
// COMMENT ON string cannot satisfy it. Each contract has an in-test mutation
// (applied to an in-memory COPY of the source; the file on disk is never
// touched) that must flip the check red, and the mutation must actually land.

const MIG_PATH = path.join(
  __dirname,
  "../../supabase/migrations/179_delete_oauth_credential.sql",
);

const stripComments = (sql: string) =>
  sql.replace(/\/\*[\s\S]*?\*\//g, "").replace(/--[^\n]*/g, "");

const FN = "public\\.delete_oauth_credential\\s*\\(\\s*uuid\\s*\\)";

/** name -> predicate over the comment-stripped SQL. */
const CONTRACTS: Record<string, (sql: string) => boolean> = {
  "defined as CREATE [OR REPLACE] FUNCTION public.delete_oauth_credential(p_user_id uuid)": (s) =>
    /CREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\s+public\.delete_oauth_credential\s*\(\s*p_user_id\s+uuid\s*\)/.test(s),
  "SECURITY DEFINER": (s) => /\bSECURITY\s+DEFINER\b/.test(s),
  "SET search_path = public, pg_temp": (s) =>
    /\bSET\s+search_path\s*=\s*public\s*,\s*pg_temp\b/.test(s),
  "DELETE FROM public.api_keys ... provider = 'anthropic_oauth' (hardcoded)": (s) =>
    /DELETE\s+FROM\s+public\.api_keys\s+WHERE\s+user_id\s*=\s*p_user_id\s+AND\s+provider\s*=\s*'anthropic_oauth'\s+RETURNING/.test(
      s,
    ),
  "never touches the 'anthropic' provider": (s) => !/provider\s*=\s*'anthropic'/.test(s),
  "REVOKE EXECUTE FROM PUBLIC": (s) =>
    new RegExp(`REVOKE\\s+EXECUTE\\s+ON\\s+FUNCTION\\s+${FN}\\s+FROM\\s+PUBLIC\\s*;`).test(s),
  "REVOKE EXECUTE FROM authenticated": (s) =>
    new RegExp(`REVOKE\\s+EXECUTE\\s+ON\\s+FUNCTION\\s+${FN}\\s+FROM\\s+authenticated\\s*;`).test(s),
  "REVOKE EXECUTE FROM anon": (s) =>
    new RegExp(`REVOKE\\s+EXECUTE\\s+ON\\s+FUNCTION\\s+${FN}\\s+FROM\\s+anon\\s*;`).test(s),
  "GRANT EXECUTE TO service_role": (s) =>
    new RegExp(`GRANT\\s+EXECUTE\\s+ON\\s+FUNCTION\\s+${FN}\\s+TO\\s+service_role\\s*;`).test(s),
  "GRANTs to no other role": (s) =>
    [...s.matchAll(/GRANT\s+EXECUTE\s+ON\s+FUNCTION[^;]*?\s+TO\s+([a-z_]+)\s*;/gi)].every(
      (m) => m[1] === "service_role",
    ),
};

/** contract name -> mutation of the RAW source that must break exactly it. */
const MUTATIONS: Array<{ breaks: string; mutate: (raw: string) => string }> = [
  {
    breaks: "DELETE FROM public.api_keys ... provider = 'anthropic_oauth' (hardcoded)",
    mutate: (r) => r.replace("AND provider = 'anthropic_oauth'", "AND provider = 'anthropic'"),
  },
  {
    breaks: "REVOKE EXECUTE FROM authenticated",
    mutate: (r) =>
      r.replace(
        /REVOKE EXECUTE ON FUNCTION public\.delete_oauth_credential\(uuid\) FROM authenticated;\n/,
        "",
      ),
  },
  {
    breaks: "SET search_path = public, pg_temp",
    mutate: (r) => r.replace("SET search_path = public, pg_temp\n", ""),
  },
  {
    breaks: "SECURITY DEFINER",
    mutate: (r) => r.replace("SECURITY DEFINER\n", ""),
  },
  {
    breaks: "GRANTs to no other role",
    mutate: (r) => r + "\nGRANT EXECUTE ON FUNCTION public.delete_oauth_credential(uuid) TO authenticated;\n",
  },
];

const raw = readFileSync(MIG_PATH, "utf8");
const exec = stripComments(raw);

describe("179_delete_oauth_credential.sql — source contract", () => {
  for (const [name, check] of Object.entries(CONTRACTS)) {
    it(name, () => {
      expect(check(exec)).toBe(true);
    });
  }

  it("comment prose cannot satisfy a contract (the comment-stripper removes it)", () => {
    // The header comment mentions the provider and the function; a file with
    // the code lines deleted but the comments intact must fail.
    const commentsOnly = stripComments(
      raw.replace(/CREATE OR REPLACE FUNCTION[\s\S]*?\$\$;\n/, ""),
    );
    expect(CONTRACTS["SECURITY DEFINER"](commentsOnly)).toBe(false);
    expect(
      CONTRACTS["DELETE FROM public.api_keys ... provider = 'anthropic_oauth' (hardcoded)"](
        commentsOnly,
      ),
    ).toBe(false);
  });

  describe("mutation proof (in-memory copy; each mutation must land and go red)", () => {
    for (const { breaks, mutate } of MUTATIONS) {
      it(`mutating the source breaks: ${breaks}`, () => {
        const mutated = mutate(raw);
        // The mutation landed in EXECUTABLE SQL (not just a comment).
        expect(stripComments(mutated)).not.toBe(exec);
        expect(CONTRACTS[breaks](stripComments(mutated))).toBe(false);
        expect(CONTRACTS[breaks](exec)).toBe(true); // and it is green unmutated
      });
    }
  });
});
