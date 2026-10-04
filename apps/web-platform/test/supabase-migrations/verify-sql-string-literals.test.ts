import { describe, it, expect } from "vitest";
import { readdirSync, readFileSync } from "node:fs";
import path from "node:path";

// Guard for apps/web-platform/supabase/verify/*.sql: no executable text may contain a
// double-quoted token.
//
// WHY. In Postgres a double-quoted token is an IDENTIFIER, not a string. `LIKE "%x%"` parses as
// valid syntax and fails only at bind time with `column "%x%" does not exist`, so no SQL parser
// and no file-shape test catches it. verify/154 shipped exactly that in #9283 and went unnoticed
// because verify-migrations does not run on the normal deploy arm; the first release dispatch that
// executed it failed on it. This test is the only pre-merge defence for the class.
//
// RULE. After stripping `--` comments, `/* */` comments, `'...'` literals (with `''` escapes) and
// `$$...$$` dollar-quoted bodies, no `"` may remain. The rule has no operator list to drift
// (`IN ("a")`, `THEN "x"`, `COALESCE(x, "")` are caught the same way as `LIKE "x"`).
//
// DOCUMENTED LIMITS (not modelled, on purpose). `E'..\'..'` backslash strings and nested
// `/* /* */ */` comments are not understood. If a future verify file uses one, the stripper can
// end a region early, which surfaces as a FALSE POSITIVE (loud, fail-closed), never as a silent
// pass of a real defect. No verify file uses either today. A legitimate quoted identifier is also
// flagged; none exists, and the remedy is an unquoted lowercase name (no allow-list).
//
// Scope: verify/*.sql only. migrations/*.sql are applied by run-migrations.sh, which fails at
// apply time, a different surface.

const VERIFY_DIR = path.join(__dirname, "../../supabase/verify");

type Finding = { line: number; text: string };

/**
 * Blank out comments, single-quoted literals and dollar-quoted bodies, keeping every newline so
 * line numbers stay valid, and return the text that is left.
 */
function codeWithoutLiteralsAndComments(sql: string): string {
  const out: string[] = [];
  const n = sql.length;
  let i = 0;
  const blank = (s: string) => s.replace(/[^\n]/g, " ");
  while (i < n) {
    const c = sql[i];
    const two = sql.slice(i, i + 2);
    if (two === "--") {
      const end = sql.indexOf("\n", i);
      const stop = end === -1 ? n : end;
      out.push(blank(sql.slice(i, stop)));
      i = stop;
    } else if (two === "/*") {
      const end = sql.indexOf("*/", i + 2);
      const stop = end === -1 ? n : end + 2;
      out.push(blank(sql.slice(i, stop)));
      i = stop;
    } else if (c === "'") {
      let j = i + 1;
      while (j < n) {
        if (sql[j] === "'") {
          if (sql[j + 1] === "'") {
            j += 2;
            continue;
          }
          break;
        }
        j++;
      }
      const stop = Math.min(j + 1, n);
      out.push(blank(sql.slice(i, stop)));
      i = stop;
    } else if (c === "$") {
      // Dollar-quote opener: `$$` or `$tag$` where tag is identifier-shaped (never `$1`).
      const m = /^\$([A-Za-z_][A-Za-z0-9_]*)?\$/.exec(sql.slice(i));
      if (m) {
        const opener = m[0];
        const end = sql.indexOf(opener, i + opener.length);
        const stop = end === -1 ? n : end + opener.length;
        out.push(blank(sql.slice(i, stop)));
        i = stop;
      } else {
        out.push(c);
        i++;
      }
    } else {
      out.push(c);
      i++;
    }
  }
  return out.join("");
}

function doubleQuoteFindings(sql: string): Finding[] {
  const stripped = codeWithoutLiteralsAndComments(sql).split("\n");
  const original = sql.split("\n");
  const findings: Finding[] = [];
  stripped.forEach((line, idx) => {
    if (line.includes('"')) findings.push({ line: idx + 1, text: (original[idx] ?? "").trim() });
  });
  return findings;
}

const WHY =
  "a double-quoted token is a Postgres IDENTIFIER, not a string; use a single-quoted literal and " +
  "double any inner ' (see verify/154 history, #9283)";

describe("supabase/verify/*.sql: no double-quoted tokens in executable text", () => {
  const files = readdirSync(VERIFY_DIR).filter((f) => f.endsWith(".sql"));

  it("scans a non-empty population (cannot pass over zero files)", () => {
    expect(files.length).toBeGreaterThan(0);
  });

  for (const file of files) {
    it(`${file} has no double-quoted token outside comments and literals`, () => {
      const findings = doubleQuoteFindings(readFileSync(path.join(VERIFY_DIR, file), "utf8"));
      const report = findings.map((f) => `${file}:${f.line}: ${f.text}`).join("\n");
      expect(findings, `${WHY}\n${report}`).toEqual([]);
    });
  }
});

describe("the double-quote check itself (inline fixtures)", () => {
  it("RED: the original verify/154 defect line is reported with its line number", () => {
    const sql = [
      "SELECT CASE WHEN pg_get_functiondef('public.f(uuid)'::regprocedure)",
      "  LIKE \"%status = 'archived' THEN RETURN%\"",
      "  THEN 0 ELSE 1 END AS bad;",
    ].join("\n");
    expect(doubleQuoteFindings(sql).map((f) => f.line)).toEqual([2]);
  });

  it("RED: a compliant first statement does not hide a defective second one", () => {
    const sql = [
      "SELECT 1 WHERE 'a' LIKE '%a%';",
      "",
      'SELECT 2 WHERE name ILIKE "%b%";',
    ].join("\n");
    expect(doubleQuoteFindings(sql).map((f) => f.line)).toEqual([3]);
  });

  it("RED: operators other than LIKE are caught (IN, THEN)", () => {
    expect(doubleQuoteFindings('SELECT 1 WHERE x IN ("a", \'b\');').length).toBe(1);
    expect(doubleQuoteFindings('SELECT CASE WHEN true THEN "x" END;').length).toBe(1);
  });

  it("must-PASS: a double quote inside a single-quoted literal", () => {
    expect(doubleQuoteFindings("SELECT 1 WHERE y LIKE '%\"x\"%';")).toEqual([]);
  });

  it("must-PASS: double quotes inside -- and /* */ comments", () => {
    expect(doubleQuoteFindings('-- = "x"\nSELECT 1;')).toEqual([]);
    expect(doubleQuoteFindings('/* LIKE "x" */ SELECT 1;')).toEqual([]);
    expect(doubleQuoteFindings('/* a\n  "multi-line" \n*/\nSELECT 1;')).toEqual([]);
  });

  it("must-PASS: a double quote inside a dollar-quoted body", () => {
    expect(doubleQuoteFindings('DO $$ BEGIN RAISE NOTICE "x"; END $$;')).toEqual([]);
    expect(doubleQuoteFindings('DO $body$ SELECT "x" $body$;')).toEqual([]);
  });

  it("must-PASS: an escaped single quote does not end the literal early", () => {
    expect(doubleQuoteFindings("SELECT 'it''s \"fine\"';")).toEqual([]);
  });

  it("a positional parameter is not a dollar-quote opener", () => {
    expect(doubleQuoteFindings('SELECT $1, "x";').length).toBe(1);
  });

  it("the fixed verify/154 spelling passes", () => {
    const sql = "SELECT 1 WHERE d LIKE '%status = ''archived'' THEN RETURN%';";
    expect(doubleQuoteFindings(sql)).toEqual([]);
  });
});
