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

function stripComments(src: string): string {
  return src
    .replace(/\/\*[\s\S]*?\*\//g, "")
    .replace(/^\s*\/\/.*$/gm, "");
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

describe("exportSqlTable read-failure sites", () => {
  it("finds every table-read error site (floor guards the matcher against going vacuous)", () => {
    expect(READ_FAILED.length).toBeGreaterThanOrEqual(40);
  });

  it("builds every 'read failed' message through describeDbError with the status of the SAME result", () => {
    const bad: string[] = [];
    for (const { expr } of READ_FAILED) {
      const m = /^describeDbError\(\s*([\w.]+)\s*,\s*([\w.]+)\s*,\s*([\w.]+)\s*\)$/.exec(
        expr,
      );
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

  it("declares the status names it passes (an undeclared `status` resolves to window.status)", () => {
    const bad: string[] = [];
    for (const { expr, index } of READ_FAILED) {
      const m = /^describeDbError\(\s*([\w.]+)\s*,\s*([\w.]+)\s*,\s*([\w.]+)\s*\)$/.exec(
        expr,
      );
      if (!m) continue;
      const [, errArg, statusArg] = m;
      if (errArg.includes(".")) continue; // `byInvitee.status` reads a bound result object
      const before = TABLE_FN.slice(0, index);
      const decl = before.lastIndexOf("const {");
      const declText = before.slice(decl, before.indexOf("} =", decl));
      const wantBinding =
        statusArg === "status" ? "status" : `status: ${statusArg}`;
      if (decl === -1 || !declText.includes(wantBinding)) {
        bad.push(`${errArg}: no \`${wantBinding}\` in its destructure`);
      }
    }
    expect(bad).toEqual([]);
  });

  it("leaves no bare `.message` interpolation in any 'read failed' message", () => {
    // Storage listing/download sites in the same function throw StorageError
    // text (a different shape, no HTTP result object) and are out of scope.
    const bare = [
      ...TABLE_FN.matchAll(/`[^`]*read failed[^`]*\$\{[^}]*\.message[^}]*\}[^`]*`/g),
    ];
    expect(bare.map((m) => m[0])).toEqual([]);
  });

  it("also covers the job-management reads and writes", () => {
    for (const anchor of [
      "dsar idempotency lookup failed: ${describeDbError(lookupErr, lookupErrStatus, lookupErrStatusText)}",
      "dsar_export_jobs insert failed: ${insertErr ? describeDbError(insertErr, insertErrStatus, insertErrStatusText) : \"no row\"}",
      "job complete update failed: ${describeDbError(updateErr, updateErrStatus, updateErrStatusText)}",
    ]) {
      expect(CODE.split(anchor).length - 1, anchor).toBe(1);
    }
  });
});
