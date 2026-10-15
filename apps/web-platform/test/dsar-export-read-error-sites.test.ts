import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import { join } from "node:path";

// The unit tests for `describeDbError` pin the helper, and
// `dsar-export-read-error.test.ts` drives one read through it. Neither can see
// whether the OTHER read sites call it: restoring a bare `${error.message}` at
// any of them leaves both green. This asserts the wire at every site, over the
// comment-stripped source of the function, anchored on the template literal
// that builds the thrown message (the file's comments quote the bare form).

const SOURCE = readFileSync(
  join(__dirname, "..", "server", "dsar-export.ts"),
  "utf8",
);

// Strips `//` and `/* */` comments while leaving string, template and regex-free
// code alone. A scanner, not a regex: a `/*` inside a `//` comment (this file
// has one, in a path glob) must not open a block comment.
function stripComments(src: string): string {
  let out = "";
  let i = 0;
  let quote: string | null = null;
  while (i < src.length) {
    const c = src[i];
    const n = src[i + 1];
    if (quote) {
      out += c;
      if (c === "\\") {
        out += n ?? "";
        i += 2;
        continue;
      }
      if (c === quote) quote = null;
      i += 1;
    } else if (c === "/" && n === "/") {
      while (i < src.length && src[i] !== "\n") i += 1;
    } else if (c === "/" && n === "*") {
      const end = src.indexOf("*/", i + 2);
      i = end === -1 ? src.length : end + 2;
    } else {
      if (c === '"' || c === "'" || c === "`") quote = c;
      out += c;
      i += 1;
    }
  }
  return out;
}

const CODE = stripComments(SOURCE);

function functionBody(code: string, name: string): string {
  const start = code.indexOf(`export async function ${name}(`);
  expect(start, `${name} not found`).toBeGreaterThanOrEqual(0);
  const rest = code.slice(start + 1);
  const next = rest.search(/\nexport /);
  return next === -1 ? rest : rest.slice(0, next);
}

const TABLE_FN = functionBody(CODE, "exportSqlTable");

// One entry per table read in `exportSqlTable`. Adding a table read means
// bumping this on purpose; a site that stops matching fails the count below.
const EXPECTED_TABLE_READ_SITES = 42;

const CALL_RE =
  /^describeDbError\(\s*([\w.]+)\s*,\s*([\w.]+)\s*,\s*([\w.]+)\s*\)$/;

// `<label> read failed: ${<expr>}` template literals, with the expression.
const READ_FAILED = [
  ...TABLE_FN.matchAll(/`[^`$]*read failed: \$\{([^}]*)\}`/g),
].map((m) => ({ expr: m[1].trim(), index: m.index ?? 0 }));

function expectedStatusNames(errArg: string): [string, string] {
  if (errArg === "error") return ["status", "statusText"];
  if (errArg.endsWith(".error")) {
    const base = errArg.slice(0, -".error".length);
    return [`${base}.status`, `${base}.statusText`];
  }
  return [`${errArg}Status`, `${errArg}StatusText`];
}

describe("comment stripping", () => {
  it("does not let a `/*` inside a line comment swallow code", () => {
    const out = stripComments("// a/*b\nconst x = 1;\n/* c */ const y = 2;\n");
    expect(out).toContain("const x = 1;");
    expect(out).toContain("const y = 2;");
    expect(out).not.toContain("c */");
  });

  it("keeps the whole file: imports above and functions below the path-glob comment survive", () => {
    expect(CODE).toContain('import { describeDbError } from "@/server/dsar-db-error";');
    expect(CODE).toContain("export async function enqueueExport(");
  });
});

describe("exportSqlTable read-failure sites", () => {
  it("has exactly the expected number of table-read error sites, found two independent ways", () => {
    expect(READ_FAILED.length).toBe(EXPECTED_TABLE_READ_SITES);
    // Independent of the 'read failed' wording: every site calls the helper.
    const calls = TABLE_FN.match(/\bdescribeDbError\(/g) ?? [];
    expect(calls.length).toBe(EXPECTED_TABLE_READ_SITES);
  });

  it("builds every 'read failed' message through describeDbError with the status of the SAME result", () => {
    const bad: string[] = [];
    for (const { expr } of READ_FAILED) {
      const m = CALL_RE.exec(expr);
      if (!m) {
        bad.push(`not a describeDbError(e, s, t) call: ${expr}`);
        continue;
      }
      const [, errArg, statusArg, textArg] = m;
      const [wantStatus, wantText] = expectedStatusNames(errArg);
      if (statusArg !== wantStatus || textArg !== wantText) {
        bad.push(`${expr} (want ${errArg}, ${wantStatus}, ${wantText})`);
      }
    }
    expect(bad).toEqual([]);
  });

  it("binds the names it passes in the destructure of its own result (an undeclared `status` resolves to window.status)", () => {
    const bad: string[] = [];
    for (const { expr, index } of READ_FAILED) {
      const m = CALL_RE.exec(expr);
      if (!m) continue;
      const [, errArg, statusArg, textArg] = m;
      if (errArg.includes(".")) continue; // `byInvitee.*`: pinned by anchor below
      const before = TABLE_FN.slice(0, index);
      const decl = before.lastIndexOf("const {");
      const close = decl === -1 ? -1 : before.indexOf("} =", decl);
      if (decl === -1 || close === -1) {
        bad.push(`${errArg}: no destructure found before the site`);
        continue;
      }
      const declText = before.slice(decl, close);
      const bare = errArg === "error";
      const errBinding = bare
        ? /(^|[\s{,])error\s*[,}\s]/
        : new RegExp(`\\berror:\\s*${errArg}\\b`);
      const statusBinding = bare
        ? /\bstatus\b(?!\s*:)/
        : new RegExp(`\\bstatus:\\s*${statusArg}\\b`);
      const textBinding = bare
        ? /\bstatusText\b(?!\s*:)/
        : new RegExp(`\\bstatusText:\\s*${textArg}\\b`);
      for (const [what, re] of [
        ["error", errBinding],
        ["status", statusBinding],
        ["statusText", textBinding],
      ] as const) {
        if (!re.test(declText)) bad.push(`${errArg}: destructure lacks ${what}`);
      }
    }
    expect(bad).toEqual([]);
  });

  it("binds the Promise.all pair's messages to their own results", () => {
    for (const anchor of [
      "workspace_invitations (invitee) read failed: ${describeDbError(byInvitee.error, byInvitee.status, byInvitee.statusText)}",
      "workspace_invitations (inviter) read failed: ${describeDbError(byInviter.error, byInviter.status, byInviter.statusText)}",
    ]) {
      expect(TABLE_FN.split(anchor).length - 1, anchor).toBe(1);
    }
  });

  it("leaves no bare `.message` interpolation in any 'read failed' message", () => {
    // Storage listing/download sites in the same function throw StorageError
    // text (a different shape, no HTTP result object) and are out of scope.
    const bare = [
      ...TABLE_FN.matchAll(/`[^`]*read failed[^`]*\$\{[^}]*\.message[^}]*\}[^`]*`/g),
    ];
    expect(bare.map((m) => m[0])).toEqual([]);
  });
});

describe("job-management and worker sites", () => {
  it("builds each message or log field through describeDbError, exactly once", () => {
    for (const anchor of [
      "dsar idempotency lookup failed: ${describeDbError(lookupErr, lookupErrStatus, lookupErrStatusText)}",
      "dsar_export_jobs insert failed: ${insertErr ? describeDbError(insertErr, insertErrStatus, insertErrStatusText) : \"no row\"}",
      "job complete update failed: ${describeDbError(updateErr, updateErrStatus, updateErrStatusText)}",
      "err: describeDbError(auditErr, auditErrStatus, auditErrStatusText)",
      "err: describeDbError(resetErr, resetErrStatus, resetErrStatusText)",
      "err: describeDbError(error, status, statusText)",
    ]) {
      expect(CODE.split(anchor).length - 1, anchor).toBe(1);
    }
  });

  it("leaves no bare `.message` on a PostgREST result outside the storage sites", () => {
    const bare = [...CODE.matchAll(/\b(\w+Err|error)\.message\b/g)].map(
      (m) => m[0],
    );
    // The three storage sites (listErr, innerErr, download `error`) throw
    // StorageError text; nothing else may read `.message` off a result error.
    expect(bare.sort()).toEqual(["error.message", "innerErr.message", "listErr.message"]);
  });
});
