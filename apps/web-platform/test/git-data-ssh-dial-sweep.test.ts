import { describe, it, expect } from "vitest";
import { readdirSync, readFileSync, statSync } from "node:fs";
import path from "node:path";

// #5914 review (structural enumeration): the property is "no code path in the web app
// dials the git-data host without a host-key pin". Guard 1 (tests/scripts/test-no-tofu-ssh.sh)
// only sees LITERAL unpinned options, and the git-auth tests only exercise the two named
// helpers — so a new module spawning `ssh` itself (with a template-literal option, a
// runtime-written known_hosts, GIT_SSH instead of GIT_SSH_COMMAND, or ssh-keyscan) would
// sit outside every guard. This sweep puts it inside one: the ONLY app source allowed to
// spawn ssh or set an ssh transport is server/git-auth.ts, whose helpers always pin.
const APP = path.resolve(__dirname, "..");
const SCAN_DIRS = ["server", "app", "lib", "scripts"];
const ALLOWED = new Set(["server/git-auth.ts"]);

// Anchored on CALL/ASSIGNMENT forms a comment cannot produce once comments are stripped.
const DIAL_PATTERNS: Array<[string, RegExp]> = [
  // Any exec/spawn-family callee (execFile, execFileAsync, execFileSync, spawn, execa, …)
  // whose first argument is an ssh-family binary literal.
  ["spawn of ssh / ssh-keyscan", /\b\w*(?:execFile|spawn|exec|execa)\w*\s*\(\s*["'`](?:ssh|ssh-keyscan|scp|sftp)["'`]/],
  ["GIT_SSH_COMMAND / GIT_SSH env", /\bGIT_SSH(?:_COMMAND)?\s*[:=]/],
  ["core.sshCommand config", /core\.sshCommand/],
];

function stripComments(src: string): string {
  return src.replace(/\/\*[\s\S]*?\*\//g, "").replace(/(^|[^:"'`])\/\/.*$/gm, "$1");
}

function walk(rel: string, out: string[]): void {
  const abs = path.join(APP, rel);
  let entries: string[];
  try {
    entries = readdirSync(abs);
  } catch {
    return;
  }
  for (const e of entries) {
    if (e === "node_modules" || e.startsWith(".")) continue;
    const r = path.join(rel, e);
    const st = statSync(path.join(APP, r));
    if (st.isDirectory()) walk(r, out);
    else if (/\.(ts|tsx|js|mjs|cjs)$/.test(e) && !/\.test\.[tj]sx?$/.test(e)) out.push(r);
  }
}

function offenders(files: string[], read: (f: string) => string): string[] {
  const hits: string[] = [];
  for (const f of files) {
    if (ALLOWED.has(f)) continue;
    const src = stripComments(read(f));
    for (const [label, re] of DIAL_PATTERNS) if (re.test(src)) hits.push(`${f}: ${label}`);
  }
  return hits;
}

describe("only server/git-auth.ts may dial over ssh (#5914)", () => {
  const files: string[] = [];
  for (const d of SCAN_DIRS) walk(d, files);
  const read = (f: string) => readFileSync(path.join(APP, f), "utf8");

  it("the sweep sees the app's source (non-vacuity)", () => {
    expect(files.length).toBeGreaterThan(200);
    expect(files).toContain("server/git-auth.ts");
    expect(files).toContain("server/git-data-replication.ts");
  });

  it("the allow-listed helper module is itself a hit (the patterns are live)", () => {
    const src = stripComments(read("server/git-auth.ts"));
    expect(DIAL_PATTERNS.some(([, re]) => re.test(src))).toBe(true);
  });

  it("no other app source spawns ssh or sets an ssh transport", () => {
    expect(offenders(files, read)).toEqual([]);
  });

  it.each([
    ['execFileAsync("ssh", ["-o", `StrictHostKeyChecking=${m}`])', "spawn of ssh / ssh-keyscan"],
    ["execFileSync('ssh-keyscan', ['10.0.1.20'])", "spawn of ssh / ssh-keyscan"],
    ["const env = { GIT_SSH: wrapperPath };", "GIT_SSH_COMMAND / GIT_SSH env"],
    ['args.push("-c", "core.sshCommand=ssh -F cfg")', "core.sshCommand config"],
  ])("a planted `%s` elsewhere is flagged", (line, label) => {
    expect(offenders(["server/zz-planted.ts"], () => line)).toEqual([`server/zz-planted.ts: ${label}`]);
  });

  it("a comment naming ssh is not a hit", () => {
    expect(offenders(["server/zz-planted.ts"], () => '// execFile("ssh", …) lives in git-auth.ts')).toEqual([]);
  });
});
