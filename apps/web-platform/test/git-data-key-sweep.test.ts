import { describe, expect, it } from "vitest";
import { readdirSync, readFileSync, statSync } from "node:fs";
import path from "node:path";
import ts from "typescript";
import { stripComments } from "./helpers/strip-comments";

// #8211 PR-G: the three git-data SSH key variables reach the app as a docker env-file
// one-liner (literal backslash-n pairs). server/git-data-key.ts is the ONE place they are
// read and repaired; a bare read anywhere else would hand ssh an unparseable key again
// (the rehearsal-2 `auth_refused`). Comments are stripped by the TypeScript parser and the
// patterns are anchored on READ forms (member access, element access, destructuring), so a
// comment or a string naming the variable is not a hit.
const APP = path.resolve(__dirname, "..");
// The whole app root: a new top-level directory (or a file beside next.config.ts) is covered
// without anyone remembering to add it here.
const SCAN_ROOTS = ["."];
const SKIP_DIRS = new Set(["node_modules", ".next"]);
const ALLOWED = new Set(["server/git-data-key.ts"]);
const NAMES = "GIT_(?:TRANSPORT|PROVISION|REMOVE)_SSH_PRIVATE_KEY";
const NAME_RE = new RegExp(NAMES);
// Callees that take a key variable NAME and read it through the normaliser.
const SANCTIONED_CALLEES = new Set(["readGitDataKeyEnv", "requireEnvKey"]);

const READ_PATTERNS: Array<[string, RegExp]> = [
  ["process.env.<KEY>", new RegExp(`\\b(?:process\\.)?env\\s*\\??\\.\\s*${NAMES}\\b`)],
  ["env[\"<KEY>\"]", new RegExp(`\\benv\\s*\\??\\.?\\s*\\[\\s*["'\`]${NAMES}["'\`]\\s*\\]`)],
  ["destructured from env", new RegExp(`\\{[^}]*\\b${NAMES}\\b[^}]*\\}\\s*=\\s*(?:process\\.)?env\\b`)],
];
// A computed env read is only suspect in a file that handles the key variables at all.
const COMPUTED_ENV_RE = /\bprocess\.env\s*\[\s*(?!["'`])/;

function walk(rel: string, out: string[]): void {
  const abs = path.join(APP, rel);
  let st;
  try {
    st = statSync(abs);
  } catch {
    return;
  }
  if (st.isFile()) {
    if (/\.(ts|tsx|js|mjs|cjs)$/.test(rel) && !/\.test\.[tj]sx?$/.test(rel) && !/\.d\.ts$/.test(rel)) out.push(path.normalize(rel));
    return;
  }
  for (const e of readdirSync(abs)) {
    if (SKIP_DIRS.has(e) || e.startsWith(".")) continue;
    walk(path.join(rel, e), out);
  }
}

// String literals that are (or hold, with no whitespace) a key variable name. Message text
// ("GIT_X is unset - ...") has whitespace and is ignored; a bare name is a read waiting to
// happen (`const N = "GIT_..."; process.env[N]`), allowed only as the argument of a sanctioned call.
function nameLiterals(src: string, file: string): string[] {
  const sf = ts.createSourceFile(file, src, ts.ScriptTarget.Latest, true);
  const hits: string[] = [];
  const visit = (n: ts.Node) => {
    if ((ts.isStringLiteral(n) || ts.isNoSubstitutionTemplateLiteral(n)) && NAME_RE.test(n.text) && !/\s/.test(n.text)) {
      const p = n.parent;
      const sanctioned =
        p && ts.isCallExpression(p) && ts.isIdentifier(p.expression) && SANCTIONED_CALLEES.has(p.expression.text);
      if (!sanctioned) hits.push("key-name string literal outside a sanctioned call");
    }
    ts.forEachChild(n, visit);
  };
  visit(sf);
  return hits;
}

function offenders(files: string[], read: (f: string) => string): string[] {
  const hits: string[] = [];
  for (const f of files) {
    if (ALLOWED.has(f)) continue;
    const raw = read(f);
    // Fast path: a file that never names a key variable cannot read one by name; skip the parse.
    if (!raw.includes("_SSH_PRIVATE_KEY")) continue;
    const src = stripComments(raw, f);
    for (const [label, re] of READ_PATTERNS) if (re.test(src)) hits.push(`${f}: ${label}`);
    if (COMPUTED_ENV_RE.test(src)) hits.push(`${f}: computed process.env[...] in a file naming a key variable`);
    for (const label of nameLiterals(raw, f)) hits.push(`${f}: ${label}`);
  }
  return hits;
}

describe("only server/git-data-key.ts reads the git-data SSH key variables (#8211 PR-G)", () => {
  const files: string[] = [];
  for (const d of SCAN_ROOTS) walk(d, files);
  const read = (f: string) => readFileSync(path.join(APP, f), "utf8");

  it("the sweep sees the app's source (non-vacuity)", () => {
    expect(files.length).toBeGreaterThan(200);
    for (const f of ["server/git-data-key.ts", "server/git-auth.ts", "server/git-data-replication.ts", "server/git-data-client.ts"]) {
      expect(files).toContain(f);
    }
  });

  it("the helper module is the reader: it names all three variables and reads the env by that name", () => {
    const src = stripComments(read("server/git-data-key.ts"), "server/git-data-key.ts");
    for (const n of ["GIT_TRANSPORT_SSH_PRIVATE_KEY", "GIT_PROVISION_SSH_PRIVATE_KEY", "GIT_REMOVE_SSH_PRIVATE_KEY"]) {
      expect(src).toContain(`"${n}"`);
    }
    expect(src).toMatch(/process\.env\[\s*name\s*\]/);
  });

  it("no other app source reads the key variables directly", () => {
    expect(offenders(files, read)).toEqual([]);
  });

  // WIRE: the readers use the helper. Reverting a call site to a bare read is caught by the
  // sweep above; dropping the helper call while keeping the file clean is caught here.
  it.each([
    ["server/git-data-client.ts", /\breadGitDataKeyEnv\s*\(\s*["']GIT_TRANSPORT_SSH_PRIVATE_KEY["']\s*\)/],
    ["server/git-data-replication.ts", /\breadGitDataKeyEnv\s*\(\s*["']GIT_REMOVE_SSH_PRIVATE_KEY["']\s*\)/],
    ["server/git-data-replication.ts", /\brequireEnvKey\s*\(\s*["']GIT_PROVISION_SSH_PRIVATE_KEY["']\s*\)/],
    ["server/git-data-replication.ts", /\brequireEnvKey\s*\(\s*["']GIT_TRANSPORT_SSH_PRIVATE_KEY["']\s*\)/],
    // requireEnvKey itself reads through the helper (tolerant of renames and formatting).
    ["server/git-data-replication.ts", /\bfunction requireEnvKey\b[^{]*\{[\s\S]*?\breadGitDataKeyEnv\s*\(\s*name\s*\)/],
  ])("%s calls the normaliser at the read (%s)", (f, re) => {
    expect(stripComments(read(f), f)).toMatch(re);
  });

  it("both key-file writers in git-auth.ts go through gitDataKeyFileContents", () => {
    const src = stripComments(read("server/git-auth.ts"), "server/git-auth.ts");
    expect((src.match(/writeFileSync\(\s*keyPath\s*,\s*gitDataKeyFileContents\(\s*privateKey\s*\)/g) ?? []).length).toBe(2);
    expect(src).not.toMatch(/writeFileSync\(\s*keyPath\s*,\s*privateKey/);
  });

  it.each([
    ["const k = process.env.GIT_TRANSPORT_SSH_PRIVATE_KEY?.trim();", ["process.env.<KEY>"]],
    ['const k = process.env["GIT_REMOVE_SSH_PRIVATE_KEY"];', ['env["<KEY>"]', "key-name string literal outside a sanctioned call"]],
    ["const { GIT_PROVISION_SSH_PRIVATE_KEY: k } = process.env;", ["destructured from env"]],
    [
      'const N = "GIT_TRANSPORT_SSH_PRIVATE_KEY";\nconst k = process.env[N];',
      ["computed process.env[...] in a file naming a key variable", "key-name string literal outside a sanctioned call"],
    ],
    ['const names = ["GIT_REMOVE_SSH_PRIVATE_KEY"];', ["key-name string literal outside a sanctioned call"]],
    ["const n = `GIT_PROVISION_SSH_PRIVATE_KEY`;", ["key-name string literal outside a sanctioned call"]],
  ])("a planted `%s` elsewhere is flagged", (line, labels) => {
    expect(offenders(["server/zz-planted.ts"], () => line).sort()).toEqual(labels.map((l) => `server/zz-planted.ts: ${l}`).sort());
  });

  it("a comment, message text, or a sanctioned helper call naming the variable is not a hit", () => {
    const src = [
      "// process.env.GIT_TRANSPORT_SSH_PRIVATE_KEY lives in git-data-key.ts",
      'const msg = "git-data: GIT_REMOVE_SSH_PRIVATE_KEY is unset - cannot reach the host";',
      'const a = readGitDataKeyEnv("GIT_REMOVE_SSH_PRIVATE_KEY");',
      'const b = requireEnvKey("GIT_PROVISION_SSH_PRIVATE_KEY");',
    ].join("\n");
    expect(offenders(["server/zz-planted.ts"], () => src)).toEqual([]);
  });

  it("a computed env read in a file that never names a key variable is not a hit", () => {
    expect(offenders(["server/zz-planted.ts"], () => "const v = process.env[name];")).toEqual([]);
  });

  it("the whole app root is scanned, including files at the top level and outside server/", () => {
    expect(files.some((f) => !f.includes(path.sep))).toBe(true); // e.g. next.config.ts, middleware.ts
    expect(files.some((f) => f.startsWith(`test${path.sep}helpers${path.sep}`))).toBe(true);
    expect(files.some((f) => f.includes("node_modules") || f.startsWith(".next"))).toBe(false);
  });
});
