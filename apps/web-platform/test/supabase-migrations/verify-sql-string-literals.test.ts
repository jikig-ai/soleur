import { describe, it, expect } from "vitest";
import { readdirSync, readFileSync } from "node:fs";
import path from "node:path";

// Guard for apps/web-platform/supabase/verify/*.sql: no executable text may contain a
// double-quoted token, and nothing the guard cannot model may hide behind one.
//
// WHY. In Postgres a double-quoted token is an IDENTIFIER, not a string. `LIKE "%x%"` parses as
// valid syntax and fails only at bind time with `column "%x%" does not exist`, so no SQL parser
// and no file-shape test catches it. verify/154 shipped exactly that in #9283 and went unnoticed
// because verify-migrations does not run on the normal deploy arm (#9471); the first release
// dispatch that executed it failed on it. This test is the only pre-merge defence for the class.
//
// RULE. After blanking `--` comments, `/* */` comments, `'...'` literals (with `''` escapes) and
// `$$...$$` / `$tag$...$tag$` dollar-quoted bodies, no `"` may remain. The rule has no operator
// list to drift (`IN ("a")`, `THEN "x"`, `COALESCE(x, "")` are caught like `LIKE "x"`).
//
// FAIL LOUD, NEVER SILENT. This is a small hand-written lexer, not Postgres's. Where the two can
// disagree, the lexer REPORTS the construct as "not modelled" instead of guessing, because a wrong
// guess flips quote parity and blanks real code after it, which would turn this guard into a
// silent pass. Reported as problems: `E'..'` backslash strings, nested `/* /* */ */` comments,
// unterminated `'` / `/*` / dollar-quote regions, `$` directly after an identifier character
// (Postgres reads `a$b$` as an identifier, so it is NOT a dollar-quote opener here either),
// lone-CR line endings (Postgres ends a `--` comment at CR, this lexer only at LF), psql
// backslash meta-commands in code position (`\i` includes, `\gexec`, `\set x '"..."'` plus `:x`
// all execute text this guard never sees), and typographic quotes (a curly quote is an
// identifier character to Postgres, the same failure as a double quote).
//
// KNOWN LIMITS (stated, not modelled). Dollar-quoted bodies are blanked wholesale, so plpgsql or
// `EXECUTE '...'` text inside a `DO $$` / function body is NOT checked (no verify file has one
// today; a body that needs checking should be moved out of the sentinel). A bare word used as a
// string (`status = archived`) is the same bind-time failure with no quote at all and cannot be
// detected lexically. A legitimate quoted identifier is flagged; none exists, and the remedy is an
// unquoted lowercase name (no allow-list).
//
// Why this is not `stripSqlNoise` (test/migration-lint/definer-grants.ts): that helper collapses
// each span to one space and drops newlines, which loses the `file:line` reports this guard
// needs, and it has no fail-loud reporting. If a third caller needs line-preserving stripping,
// hoist this lexer next to it.
//
// Scope: verify/*.sql only. migrations/*.sql are applied by run-migrations.sh, which fails at
// apply time, a different surface.

const VERIFY_DIR = path.join(__dirname, "../../supabase/verify");

type Problem = { line: number; text: string; reason: string };
type Unmodelled = { index: number; reason: string };

const IDENT_CHAR = /[A-Za-z0-9_$]/;
const TYPOGRAPHIC_QUOTE = new RegExp(
  "[" + String.fromCharCode(0x201c, 0x201d, 0x2018, 0x2019) + "]",
);
const REASON_DQ =
  "double-quoted token is a Postgres IDENTIFIER, not a string; use a single-quoted literal and " +
  "double any inner ' (see verify/154 history, #9283)";

/**
 * Blank comments, single-quoted literals and dollar-quoted bodies, keeping every newline so line
 * numbers stay valid, and collect constructs this lexer cannot model.
 */
function lex(sql: string): { code: string; unmodelled: Unmodelled[] } {
  const out: string[] = [];
  const unmodelled: Unmodelled[] = [];
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
      if (end === -1) {
        unmodelled.push({ index: i, reason: "unterminated /* comment" });
        out.push(blank(sql.slice(i)));
        i = n;
      } else {
        if (sql.slice(i + 2, end).includes("/*")) {
          unmodelled.push({ index: i, reason: "nested /* comment" });
        }
        out.push(blank(sql.slice(i, end + 2)));
        i = end + 2;
      }
    } else if (c === "'") {
      const prev = sql[i - 1];
      const prev2 = sql[i - 2];
      if ((prev === "E" || prev === "e") && !(prev2 !== undefined && IDENT_CHAR.test(prev2))) {
        unmodelled.push({ index: i - 1, reason: "E'..' backslash string" });
      }
      let j = i + 1;
      let closed = false;
      while (j < n) {
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
      if (!closed) unmodelled.push({ index: i, reason: "unterminated ' literal" });
      const stop = closed ? j + 1 : n;
      out.push(blank(sql.slice(i, stop)));
      i = stop;
    } else if (c === "$" && !(i > 0 && IDENT_CHAR.test(sql[i - 1]))) {
      // Dollar-quote opener: `$$` or `$tag$`, tag identifier-shaped (never `$1`), and not glued
      // to a preceding identifier character (`a$b$` is an identifier).
      const m = /^\$([A-Za-z_][A-Za-z0-9_]*)?\$/.exec(sql.slice(i));
      if (m) {
        const opener = m[0];
        const end = sql.indexOf(opener, i + opener.length);
        if (end === -1) unmodelled.push({ index: i, reason: "unterminated dollar-quote" });
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
  return { code: out.join(""), unmodelled };
}

function problemsIn(sql: string): Problem[] {
  const { code, unmodelled } = lex(sql);
  const original = sql.split("\n");
  const lineOf = (index: number) => sql.slice(0, index).split("\n").length;
  const found: Problem[] = [];
  const add = (line: number, reason: string) =>
    found.push({ line, text: (original[line - 1] ?? "").trim(), reason });
  code.split("\n").forEach((l, idx) => {
    if (l.includes('"')) add(idx + 1, REASON_DQ);
    if (TYPOGRAPHIC_QUOTE.test(l)) add(idx + 1, "typographic quote (an identifier char to Postgres)");
    if (/^\s*\\[A-Za-z]/.test(l)) add(idx + 1, "psql meta-command not modelled (executes text this guard never sees)");
  });
  for (const u of unmodelled) add(lineOf(u.index), `${u.reason} not modelled`);
  const cr = /\r(?!\n)/.exec(sql);
  if (cr) add(lineOf(cr.index), "lone CR line ending not modelled");
  return found.sort((a, b) => a.line - b.line);
}

const lines = (sql: string) => problemsIn(sql).map((p) => p.line);

describe("supabase/verify/*.sql: no double-quoted or unmodelled tokens in executable text", () => {
  const files = readdirSync(VERIFY_DIR)
    .filter((f) => f.endsWith(".sql"))
    .sort();
  const checked = new Set<string>();
  const reports: string[] = [];

  it("scans a non-empty population (cannot pass over zero files)", () => {
    expect(files.length).toBeGreaterThan(0);
  });

  for (const file of files) {
    it(`${file} has no problem outside comments and literals`, () => {
      const found = problemsIn(readFileSync(path.join(VERIFY_DIR, file), "utf8"));
      checked.add(file);
      const report = found.map((f) => `${file}:${f.line}: ${f.reason}: ${f.text}`).join("\n");
      if (report) reports.push(report);
      expect(found, report).toEqual([]);
    });
  }

  // Runs after the per-file cases (vitest runs a file's tests in order). Counts files actually
  // CHECKED and re-asserts the collected reports, so a per-file body that stops asserting (or
  // stops running) cannot hide behind a non-empty listing: both limbs must be emptied to pass.
  it("checked every file it listed, with no collected problem", () => {
    expect([...checked].sort()).toEqual(files);
    expect(reports).toEqual([]);
  });
});

describe("the check itself (inline fixtures)", () => {
  it("reports the original verify/154 defect with its line number and text", () => {
    const sql = [
      "SELECT CASE WHEN pg_get_functiondef('public.f(uuid)'::regprocedure)",
      "  LIKE \"%status = 'archived' THEN RETURN%\"",
      "  THEN 0 ELSE 1 END AS bad;",
    ].join("\n");
    const found = problemsIn(sql);
    expect(found.map((f) => f.line)).toEqual([2]);
    expect(found[0].text).toBe("LIKE \"%status = 'archived' THEN RETURN%\"");
    expect(found[0].reason).toContain("IDENTIFIER");
  });

  it("a compliant first statement does not hide a defective second one", () => {
    const sql = ["SELECT 1 WHERE 'a' LIKE '%a%';", "", 'SELECT 2 WHERE name ILIKE "%b%";'].join("\n");
    expect(lines(sql)).toEqual([3]);
  });

  it("operators other than LIKE are caught (IN, THEN)", () => {
    expect(lines('SELECT 1 WHERE x IN ("a", \'b\');').length).toBe(1);
    expect(lines('SELECT CASE WHEN true THEN "x" END;').length).toBe(1);
  });

  // A defect AFTER each construct the lexer blanks must still be reported, on the right line.
  it.each([
    ["a line comment", '-- c\nSELECT "x";', [2]],
    ["a block comment", '/* c */ SELECT "x";', [1]],
    ["a multi-line block comment", '/* a\n b\n c */\nSELECT "x";', [4]],
    ["a multi-line literal", "SELECT 'a\nb\nc';\nSELECT \"x\";", [4]],
    ["a literal with an escaped quote", "SELECT 'it''s';\nSELECT \"x\";", [2]],
    ["a dollar body with a $1 inside", 'DO $$ SELECT $1 $$;\nSELECT "x";', [2]],
    ["a dollar body with a different inner tag", 'DO $a$ $b$ y $b$ $a$;\nSELECT "x";', [2]],
    ["a positional parameter", 'SELECT $1, "x";', [1]],
    ["CRLF line endings", "SELECT 1;\r\nSELECT \"x\";\r\n", [2]],
  ])("reports a defect after %s on the right line", (_label, sql, want) => {
    expect(lines(sql)).toEqual(want);
  });

  it("must-PASS: a double quote inside a single-quoted literal", () => {
    expect(lines("SELECT 1 WHERE y LIKE '%\"x\"%';")).toEqual([]);
  });

  it("must-PASS: double quotes inside -- and /* */ comments", () => {
    expect(lines('-- = "x"\nSELECT 1;')).toEqual([]);
    expect(lines('/* LIKE "x" */ SELECT 1;')).toEqual([]);
    expect(lines('/* a\n  "multi-line" \n*/\nSELECT 1;')).toEqual([]);
  });

  it("must-PASS: a double quote inside a dollar-quoted body (a documented limit)", () => {
    expect(lines('DO $$ BEGIN RAISE NOTICE "x"; END $$;')).toEqual([]);
    expect(lines('DO $body$ SELECT "x" $body$;')).toEqual([]);
  });

  it("must-PASS: a $ inside an identifier or a regex literal is not a dollar-quote", () => {
    expect(lines("SELECT col$1 FROM t WHERE d ~ '\\.git$';")).toEqual([]);
  });

  it("the fixed verify/154 spelling passes", () => {
    expect(lines("SELECT 1 WHERE d LIKE '%status = ''archived'' THEN RETURN%';")).toEqual([]);
  });

  // Constructs the lexer cannot model are REPORTED, so a quote-parity flip cannot hide code.
  it.each([
    ["an E'..' backslash string", "SELECT E'\\'';\nSELECT \"x\";\nSELECT 'ok';", "E'..' backslash string"],
    ["a lowercase e'..' string", "SELECT e'a\\'b';\nSELECT 'ok';", "E'..' backslash string"],
    ["a nested block comment", "/* a /* b */ don't */\nSELECT 'x';", "nested /* comment"],
    ["an unterminated literal", "SELECT 'oops;\nSELECT 1;", "unterminated ' literal"],
    ["an unterminated block comment", "/* oops\nSELECT 1;", "unterminated /* comment"],
    ["an unterminated dollar-quote", "SELECT $x$ oops;\nSELECT 1;", "unterminated dollar-quote"],
    ["a lone CR line ending", "SELECT 1;\rSELECT 2;", "lone CR line ending"],
    ["a psql include", "\\i ../migrations/999_bad.sql\nSELECT 1;", "psql meta-command"],
    ["a psql gexec", "SELECT 1\n\\gexec", "psql meta-command"],
    ["a psql variable set", "\\set pat '\"%x%\"'\nSELECT 1 WHERE d LIKE :pat;", "psql meta-command"],
    [
      "a typographic quote",
      "SELECT 1 WHERE status = " + String.fromCharCode(0x201c) + "archived" + String.fromCharCode(0x201d) + ";",
      "typographic quote",
    ],
  ])("reports %s instead of guessing", (_label, sql, reason) => {
    expect(problemsIn(sql).some((p) => p.reason.includes(reason))).toBe(true);
  });

  it("a $ glued to an identifier is not an opener, so a defect after it is still seen", () => {
    expect(lines('SELECT a$b$ FROM t WHERE x LIKE "y";')).toEqual([1]);
  });

  it("must-PASS: E and e that are not string prefixes", () => {
    expect(lines("SELECT 1 AS name'' ;")).toEqual([]);
    expect(lines("SELECT 'x' AS e;\nSELECT 'e' || 'y';")).toEqual([]);
  });

  it("must-PASS: a psql backslash inside a literal or comment is not a meta-command", () => {
    expect(lines("SELECT 'a\\ib';")).toEqual([]);
    expect(lines("-- \\i ../x.sql\nSELECT 1;")).toEqual([]);
  });
});
