import { describe, it, expect } from "vitest";
import { mkdtempSync, readdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";

// Guard for apps/web-platform/supabase/verify/*.sql: no executable text may contain a
// double-quoted token, and nothing the guard cannot model may hide behind one.
//
// WHY. In Postgres a double-quoted token is an IDENTIFIER, not a string. `LIKE "%x%"` parses as
// valid syntax and fails only at bind time with `column "%x%" does not exist`, so no SQL parser
// and no file-shape test catches it. verify/154 shipped exactly that in #9283 and went unnoticed
// because verify-migrations is skipped on the workflow_run deploy arm even when migrate succeeds
// (#9471, mechanism unproven); the first release dispatch that executed it failed on it. This test
// is the only pre-merge defence for the class.
//
// RULE. After blanking `--` comments, `/* */` comments (nested, as Postgres counts them),
// `'...'` literals (with `''` escapes) and `$$...$$` / `$tag$...$tag$` dollar-quoted bodies, no
// `"` may remain. The rule has no operator list to drift (`IN ("a")`, `THEN "x"`,
// `COALESCE(x, "")` are caught like `LIKE "x"`).
//
// FAIL LOUD, NEVER SILENT. This is a small hand-written lexer, not Postgres's. Where the two can
// disagree, the lexer REPORTS the construct as "not modelled" instead of guessing, because a wrong
// guess flips quote parity and blanks real code after it, which would turn this guard into a
// silent pass. Reported as problems: `E'..'` backslash strings, unterminated `'` / `/*` /
// dollar-quote regions, lone-CR line endings (Postgres ends a `--` comment at CR, this lexer only
// at LF; a CR inside a literal is flagged too, loudly), `standard_conforming_strings` anywhere
// (it changes what a backslash means inside `'..'`), any backslash in code position (psql treats
// every unquoted backslash as a meta-command: `\i`, `\gexec`, `\!` run text or a shell this guard
// never sees, and SQL has no other use for one), and any non-ASCII character in code position
// (Postgres reads every non-ASCII character as an identifier character, so a curly or full-width
// quote fails like a double quote; non-ASCII also counts as an identifier character for the
// `$`-glue rule below). `$` directly after an identifier character is not a dollar-quote opener
// (Postgres reads `a$b$` as an identifier), which is a lexing rule, not a report.
//
// KNOWN LIMITS (stated, not modelled). Dollar-quoted bodies are blanked wholesale, so plpgsql or
// `EXECUTE '...'` text inside a `DO $$` / function body is NOT checked (no verify file has one
// today; a body that needs checking should be moved out of the sentinel). A bare word used as a
// string (`status = archived`) is the same bind-time failure with no quote at all and cannot be
// detected lexically. A role- or database-level `standard_conforming_strings = off` is invisible
// to any file lexer. A legitimate quoted identifier is flagged; none exists, and the remedy is an
// unquoted lowercase name (no allow-list).
//
// Why this is not `stripSqlNoise` (test/migration-lint/definer-grants.ts): that helper collapses
// block comments, literals and dollar bodies to one space, so multi-line spans lose their
// newlines and the `file:line` reports this guard needs; it models nested comments but has no
// fail-loud reporting. If a third caller needs line-preserving stripping, hoist this lexer next
// to it.
//
// Scope: verify/*.sql only. migrations/*.sql are applied by run-migrations.sh, which fails at
// apply time, a different surface.

const VERIFY_DIR = path.join(__dirname, "../../supabase/verify");

type Problem = { line: number; text: string; reason: string };
type Unmodelled = { index: number; reason: string };

// Every non-ASCII UTF-16 code unit (0x80-0xFFFF, surrogate halves included) is an identifier
// character to Postgres. Built from char codes so no raw non-ASCII or control byte sits in source.
const NON_ASCII_CLASS = String.fromCharCode(0x80) + "-" + String.fromCharCode(0xffff);
const NON_ASCII = new RegExp("[" + NON_ASCII_CLASS + "]");
const IDENT_CHAR = new RegExp("[A-Za-z0-9_$" + NON_ASCII_CLASS + "]");
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
      // Postgres nests block comments. The opener's `*` is consumed by the opener, so scanning
      // restarts at i + 2: `/*/` opens one comment and does not close it.
      let depth = 1;
      let j = i + 2;
      while (j < n && depth > 0) {
        const pair = sql.slice(j, j + 2);
        if (pair === "/*") {
          depth++;
          j += 2;
        } else if (pair === "*/") {
          depth--;
          j += 2;
        } else {
          j++;
        }
      }
      if (depth > 0) unmodelled.push({ index: i, reason: "unterminated /* comment" });
      out.push(blank(sql.slice(i, j)));
      i = j;
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
    if (NON_ASCII.test(l)) {
      add(idx + 1, "non-ASCII character in code (an identifier char to Postgres, e.g. a typographic quote)");
    }
    if (l.includes("\\")) {
      add(idx + 1, "psql meta-command (backslash in code position) not modelled; it executes text this guard never sees");
    }
  });
  for (const u of unmodelled) add(lineOf(u.index), `${u.reason} not modelled`);
  const cr = /\r(?!\n)/.exec(sql);
  if (cr) add(lineOf(cr.index), "lone CR line ending not modelled");
  const scs = /standard_conforming_strings/i.exec(sql);
  if (scs) add(lineOf(scs.index), "standard_conforming_strings changes backslash handling in '..'; not modelled");
  return found.sort((a, b) => a.line - b.line);
}

const lines = (sql: string) => problemsIn(sql).map((p) => p.line);

// The directory walk and the per-file scan are shared by the real-corpus cases and by the
// seeded-directory case below, so a mutation of either one is visible to a case that CAN go red.
const listSql = (dir: string) =>
  readdirSync(dir)
    .filter((f) => f.endsWith(".sql"))
    .sort();
const scanFile = (dir: string, file: string) =>
  problemsIn(readFileSync(path.join(dir, file), "utf8")).map(
    (f) => `${file}:${f.line}: ${f.reason}: ${f.text}`,
  );

describe("supabase/verify/*.sql: no double-quoted or unmodelled tokens in executable text", () => {
  const files = listSql(VERIFY_DIR);

  it("scans a non-empty population (cannot pass over zero files)", () => {
    expect(files.length).toBeGreaterThan(0);
  });

  for (const file of files) {
    it(`${file} has no problem outside comments and literals`, () => {
      expect.assertions(1);
      const report = scanFile(VERIFY_DIR, file);
      expect(report, report.join("\n")).toEqual([]);
    });
  }

  // The real corpus is clean, so the cases above cannot tell a working walk from a dead one.
  // This seeds a directory with one defective .sql, one clean .sql and one non-.sql carrying the
  // same defect: exactly one report, naming the defective file.
  it("walks and scans a seeded directory (the walk is not vacuous)", () => {
    const dir = mkdtempSync(path.join(tmpdir(), "verify-sql-guard-"));
    try {
      writeFileSync(path.join(dir, "bad.sql"), 'SELECT 1 WHERE x LIKE "y";\n');
      writeFileSync(path.join(dir, "ok.sql"), "SELECT 1 WHERE x LIKE 'y';\n");
      writeFileSync(path.join(dir, "notes.txt"), 'SELECT 1 WHERE x LIKE "y";\n');
      const seeded = listSql(dir);
      expect(seeded).toEqual(["bad.sql", "ok.sql"]);
      const reports = seeded.flatMap((f) => scanFile(dir, f));
      expect(reports).toHaveLength(1);
      expect(reports[0]).toMatch(/^bad\.sql:1: double-quoted token/);
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
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
    // `col$x$` would open (and never close) a dollar-quote if the glue rule were removed.
    expect(lines("SELECT col$x$ FROM t WHERE d ~ '\\.git$';")).toEqual([]);
  });

  it("must-PASS: nested block comments hide every quote inside them", () => {
    expect(lines('/* a /* b "x" */ "y" */ SELECT 1;')).toEqual([]);
  });

  it("must-PASS: a comment that OPENS with /*/ is one comment, not an open and a close", () => {
    expect(lines('/*/ "x" */ SELECT 1;')).toEqual([]);
  });

  // `/*/` opens ONE comment (the opener consumes its `*`); a lexer that reads it as open+close
  // closes the comment early and can hide, or invent, a double quote after it.
  it.each([
    ["a /*/ that opens a nested comment", '/* /*/ -- */ */ SELECT 1 WHERE x LIKE "y";', [1]],
    ["a /*/ followed by an apostrophe", "/* a /*/ don't */ y */ SELECT \"x\"; -- it's", [1]],
  ])("reports the defect after %s", (_label, sql, want) => {
    expect(lines(sql)).toEqual(want);
  });

  it("must-PASS: non-ASCII text inside a comment or a literal", () => {
    const dash = String.fromCharCode(0x2014);
    const eacute = String.fromCharCode(0xe9);
    expect(lines(`-- note ${dash} fine\nSELECT '${eacute}${dash}';`)).toEqual([]);
  });

  it("must-PASS: a backslash-led line inside a literal, comment or dollar body", () => {
    expect(lines("SELECT 'a\n\\i x.sql\nb';")).toEqual([]);
    expect(lines("/* a\n\\gexec\n*/ SELECT 1;")).toEqual([]);
    expect(lines("DO $$ a\n\\set x 1\n$$;")).toEqual([]);
  });

  it("the fixed verify/154 spelling passes", () => {
    expect(lines("SELECT 1 WHERE d LIKE '%status = ''archived'' THEN RETURN%';")).toEqual([]);
  });

  // Constructs the lexer cannot model are REPORTED, so a quote-parity flip cannot hide code.
  it.each([
    ["an E'..' backslash string", "SELECT E'\\'';\nSELECT \"x\";\nSELECT 'ok';", "E'..' backslash string"],
    ["a lowercase e'..' string", "SELECT e'a\\'b';\nSELECT 'ok';", "E'..' backslash string"],
    ["an unterminated literal", "SELECT 'oops;\nSELECT 1;", "unterminated ' literal"],
    ["an unterminated block comment", "/* oops\nSELECT 1;", "unterminated /* comment"],
    ["an unterminated NESTED block comment", "/* a /* b */ c\nSELECT 1;", "unterminated /* comment"],
    ["an unterminated dollar-quote", "SELECT $x$ oops;\nSELECT 1;", "unterminated dollar-quote"],
    ["a lone CR line ending", "SELECT 1;\rSELECT 2;", "lone CR line ending"],
    ["a lone CR inside a -- comment", '-- a\rSELECT "x";', "lone CR line ending"],
    ["a psql include", "\\i ../migrations/999_bad.sql\nSELECT 1;", "psql meta-command"],
    ["a psql gexec", "SELECT 1\n\\gexec", "psql meta-command"],
    ["a same-line psql gexec", "SELECT 1 \\gexec", "psql meta-command"],
    ["a same-line psql include", "SELECT 1; \\i x.sql", "psql meta-command"],
    ["a psql shell escape", "\\! echo hi", "psql meta-command"],
    ["a psql statement separator", "SELECT 1 \\; SELECT 2;", "psql meta-command"],
    ["a psql variable set", "\\set pat '\"%x%\"'\nSELECT 1 WHERE d LIKE :pat;", "psql meta-command"],
    ["standard_conforming_strings set", "SET standard_conforming_strings = off;", "standard_conforming_strings"],
    [
      "standard_conforming_strings via set_config",
      "SELECT set_config('standard_conforming_strings', 'off', false);",
      "standard_conforming_strings",
    ],
    [
      "a typographic quote",
      "SELECT 1 WHERE status = " + String.fromCharCode(0x201c) + "archived" + String.fromCharCode(0x201d) + ";",
      "non-ASCII character",
    ],
    [
      "a single typographic quote (U+2018)",
      "SELECT 1 WHERE status = " + String.fromCharCode(0x2018) + "archived;",
      "non-ASCII character",
    ],
    [
      "a full-width quote (U+FF02)",
      "SELECT 1 WHERE status = " + String.fromCharCode(0xff02) + "a" + String.fromCharCode(0xff02) + ";",
      "non-ASCII character",
    ],
    [
      "a guillemet",
      "SELECT 1 WHERE status = " + String.fromCharCode(0xab) + "a" + String.fromCharCode(0xbb) + ";",
      "non-ASCII character",
    ],
    [
      "a non-ASCII identifier char before $$ (not a dollar-quote opener)",
      'SELECT ' + String.fromCharCode(0xe9) + '$$ , "x" , ' + String.fromCharCode(0xe9) + "$$ FROM t;",
      "double-quoted token",
    ],
  ])("reports %s instead of guessing", (_label, sql, reason) => {
    expect(problemsIn(sql).some((p) => p.reason.includes(reason))).toBe(true);
  });

  it("a $ glued to an identifier is not an opener, so a defect after it is still seen", () => {
    // The pair closes (`c$b$`), so a mis-read opener blanks the defect WITHOUT an unterminated
    // report: only the identifier-glue check, not the unterminated check, can see this one.
    expect(lines('SELECT a$b$ WHERE x LIKE "y" AND c$b$ = 1;')).toEqual([1]);
  });

  it("problems from different checks are reported in line order", () => {
    // The code-position check (line 2) runs before the unmodelled report (line 1).
    expect(lines("SELECT E'a';\nSELECT \"x\";")).toEqual([1, 2]);
  });

  it("must-PASS: E and e that are not string prefixes", () => {
    expect(lines("SELECT 1 AS name'' ;")).toEqual([]);
    expect(lines("SELECT 'x' AS e;\nSELECT 1 AS e, 'y';")).toEqual([]);
  });

  it("must-PASS: a psql backslash inside a literal or comment is not a meta-command", () => {
    expect(lines("SELECT 'a\\ib';")).toEqual([]);
    expect(lines("-- \\i ../x.sql\nSELECT 1;")).toEqual([]);
  });
});
