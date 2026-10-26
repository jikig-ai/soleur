import { describe, expect, it } from "vitest";
import { readdirSync, readFileSync, statSync } from "node:fs";
import path from "node:path";
import { stripComments } from "./helpers/strip-comments";

// #8211 PR-G: the three git-data SSH key variables reach the app as a docker env-file
// one-liner (literal backslash-n pairs). server/git-data-key.ts is the ONE place they are
// read and repaired; a bare read anywhere else would hand ssh an unparseable key again
// (the rehearsal-2 `auth_refused`). Comments are stripped by the TypeScript parser and the
// patterns are anchored on READ forms (member access, element access, destructuring), so a
// comment or a string naming the variable is not a hit.
const APP = path.resolve(__dirname, "..");
const SCAN_DIRS = ["server", "app", "lib", "scripts", "components", "middleware.ts", "instrumentation.ts", "next.config.ts"];
const ALLOWED = new Set(["server/git-data-key.ts"]);
const NAMES = "GIT_(?:TRANSPORT|PROVISION|REMOVE)_SSH_PRIVATE_KEY";

const READ_PATTERNS: Array<[string, RegExp]> = [
  ["process.env.<KEY>", new RegExp(`\\b(?:process\\.)?env\\s*\\??\\.\\s*${NAMES}\\b`)],
  ["env[\"<KEY>\"]", new RegExp(`\\benv\\s*\\??\\.?\\s*\\[\\s*["'\`]${NAMES}["'\`]\\s*\\]`)],
  ["destructured from env", new RegExp(`\\{[^}]*\\b${NAMES}\\b[^}]*\\}\\s*=\\s*(?:process\\.)?env\\b`)],
];

function walk(rel: string, out: string[]): void {
  const abs = path.join(APP, rel);
  let st;
  try {
    st = statSync(abs);
  } catch {
    return;
  }
  if (st.isFile()) {
    if (/\.(ts|tsx|js|mjs|cjs)$/.test(rel) && !/\.test\.[tj]sx?$/.test(rel)) out.push(rel);
    return;
  }
  for (const e of readdirSync(abs)) {
    if (e === "node_modules" || e.startsWith(".")) continue;
    walk(path.join(rel, e), out);
  }
}

function offenders(files: string[], read: (f: string) => string): string[] {
  const hits: string[] = [];
  for (const f of files) {
    if (ALLOWED.has(f)) continue;
    const src = stripComments(read(f), f);
    for (const [label, re] of READ_PATTERNS) if (re.test(src)) hits.push(`${f}: ${label}`);
  }
  return hits;
}

describe("only server/git-data-key.ts reads the git-data SSH key variables (#8211 PR-G)", () => {
  const files: string[] = [];
  for (const d of SCAN_DIRS) walk(d, files);
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
    ["server/git-data-replication.ts", /\bconst key = readGitDataKeyEnv\s*\(\s*name\s*\)/],
  ])("%s calls the normaliser at the read (%s)", (f, re) => {
    expect(stripComments(read(f), f)).toMatch(re);
  });

  it("both key-file writers in git-auth.ts go through gitDataKeyFileContents", () => {
    const src = stripComments(read("server/git-auth.ts"), "server/git-auth.ts");
    expect((src.match(/writeFileSync\(\s*keyPath\s*,\s*gitDataKeyFileContents\(\s*privateKey\s*\)/g) ?? []).length).toBe(2);
    expect(src).not.toMatch(/writeFileSync\(\s*keyPath\s*,\s*privateKey/);
  });

  it.each([
    ["const k = process.env.GIT_TRANSPORT_SSH_PRIVATE_KEY?.trim();", "process.env.<KEY>"],
    ['const k = process.env["GIT_REMOVE_SSH_PRIVATE_KEY"];', 'env["<KEY>"]'],
    ["const { GIT_PROVISION_SSH_PRIVATE_KEY: k } = process.env;", "destructured from env"],
  ])("a planted `%s` elsewhere is flagged", (line, label) => {
    expect(offenders(["server/zz-planted.ts"], () => line)).toEqual([`server/zz-planted.ts: ${label}`]);
  });

  it("a comment or a string naming the variable is not a hit", () => {
    expect(
      offenders(["server/zz-planted.ts"], () => '// process.env.GIT_TRANSPORT_SSH_PRIVATE_KEY lives in git-data-key.ts\nconst n = "GIT_REMOVE_SSH_PRIVATE_KEY";'),
    ).toEqual([]);
  });
});
