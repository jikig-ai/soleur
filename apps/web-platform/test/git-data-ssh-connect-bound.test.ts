// #8211 PR-D: the git-data ssh transport must fail fast on a blackholed dial.
//
// Measured 2026-10-24 (flag-on rehearsal): `git fetch ssh://git@<git-data>/...` HUNG until the
// 60 s execFile SIGTERM (Better Stack op=git-data-overlay, killed:true, signal SIGTERM, stderr "")
// because the container egress firewall dropped the SYN and ssh had no connect bound: the kernel's
// SYN retries outlast the timeout, so the failure was silent. ConnectTimeout turns that into
// `Connection timed out` (a classifiable stderr line) inside the budget; ServerAlive* bounds a
// session that connects and then goes quiet.
//
// ssh keeps the FIRST value it sees for an option, so presence is not effect: the options must
// each appear exactly once in every site's argv, and `ssh -G` must resolve the pinned values.
process.env.HOME = process.env.HOME || "/tmp";

import { describe, test, expect, beforeEach, afterEach, vi } from "vitest";
import { readFileSync, readdirSync, statSync } from "node:fs";
import { join } from "node:path";
import { execFileSync as realExecFileSync } from "child_process";
import { makeEd25519Pin } from "./helpers/ssh-host-key-fixture";

type ExecFileCallback = (err: Error | null, result: { stdout: Buffer; stderr: Buffer }) => void;
type Call = {
  cmd: string;
  args: string[];
  opts: { env?: NodeJS.ProcessEnv } | undefined;
  cb: ExecFileCallback;
};

function mockExecFile(calls: Call[]) {
  vi.doMock("child_process", async () => {
    const actual = await vi.importActual<typeof import("child_process")>("child_process");
    return {
      ...actual,
      execFile: vi
        .fn()
        .mockImplementation((cmd: string, args: string[], opts: Call["opts"], cb: ExecFileCallback) => {
          calls.push({ cmd, args, opts, cb });
          cb(null, { stdout: Buffer.from(""), stderr: Buffer.from("") });
        }),
    };
  });
}

const BOUND = {
  ConnectTimeout: "8",
  ServerAliveInterval: "6",
  ServerAliveCountMax: "2",
} as const;
const KEY =
  "-----BEGIN OPENSSH PRIVATE KEY-----\nc3ludGhldGljLWJvdW5k\n-----END OPENSSH PRIVATE KEY-----";
const DEST = "git@10.0.1.20";

beforeEach(() => {
  vi.resetModules();
});
afterEach(() => {
  vi.restoreAllMocks();
  vi.doUnmock("child_process");
});

function optionValues(opts: string[], key: string): string[] {
  const vals: string[] = [];
  for (let i = 0; i < opts.length - 1; i++) {
    if (opts[i] !== "-o") continue;
    const [k, ...rest] = opts[i + 1].split("=");
    if (k.toLowerCase() === key.toLowerCase()) vals.push(rest.join("="));
  }
  return vals;
}

async function captureSites(): Promise<{ site: string; opts: string[] }[]> {
  const pin = makeEd25519Pin();
  const out: { site: string; opts: string[] }[] = [];

  const sshCalls: Call[] = [];
  mockExecFile(sshCalls);
  const { sshWithPrivateKeyAuth } = await import("../server/git-auth");
  await sshWithPrivateKeyAuth("10.0.1.20", "ws-uuid-123", KEY, pin);
  const a = sshCalls[0].args;
  out.push({ site: "sshWithPrivateKeyAuth", opts: a.slice(0, a.indexOf(DEST)) });

  vi.resetModules();
  vi.doUnmock("child_process");
  const gitCalls: Call[] = [];
  mockExecFile(gitCalls);
  const { gitWithPrivateKeyAuth } = await import("../server/git-auth");
  await gitWithPrivateKeyAuth(["fetch", `ssh://${DEST}/repositories/x.git`], KEY, pin);
  const cmd = (gitCalls[0].opts?.env?.GIT_SSH_COMMAND ?? "").split(" ");
  expect(cmd[0]).toBe("ssh");
  out.push({ site: "gitWithPrivateKeyAuth", opts: cmd.slice(1) });
  return out;
}

describe("git-data ssh dial is bounded at every site (#8211)", () => {
  test("both helpers pass the exact connect/keepalive options, each exactly once", async () => {
    const sites = await captureSites();
    expect(sites.map((s) => s.site).sort()).toEqual(["gitWithPrivateKeyAuth", "sshWithPrivateKeyAuth"]);
    for (const { site, opts } of sites) {
      for (const [k, v] of Object.entries(BOUND)) {
        expect(optionValues(opts, k), `${site}: ${k}`).toEqual([v]);
      }
    }
  });

  let sshAvailable = false;
  try {
    realExecFileSync("ssh", ["-V"], { stdio: "ignore" });
    sshAvailable = true;
  } catch {
    sshAvailable = false;
  }

  test.skipIf(!sshAvailable)("ssh -G resolves the bound values for both helpers", async () => {
    for (const { site, opts } of await captureSites()) {
      const resolved = realExecFileSync("ssh", ["-G", ...opts, DEST], {
        encoding: "utf8",
        stdio: ["ignore", "pipe", "ignore"],
      });
      const get = (k: string) =>
        resolved
          .split("\n")
          .find((l) => l.startsWith(`${k} `))
          ?.slice(k.length + 1);
      expect(get("connecttimeout"), site).toBe(BOUND.ConnectTimeout);
      expect(get("serveraliveinterval"), site).toBe(BOUND.ServerAliveInterval);
      expect(get("serveralivecountmax"), site).toBe(BOUND.ServerAliveCountMax);
    }
  });

  test("the dead-peer window (ConnectTimeout + ServerAliveInterval x CountMax) is STRICTLY under the shortest REAL caller timeout, read from source", () => {
    const timeouts: number[] = [];
    for (const f of ["git-data-replication.ts", "git-data-client.ts"]) {
      const code = stripComments(readFileSync(join(__dirname, "..", "server", f), "utf8"));
      for (const m of code.matchAll(/\bawait\s+(?:git|ssh)WithPrivateKeyAuth\s*\(/g)) {
        const args = balanced(code, m.index! + m[0].length - 1, "(", ")");
        const t = args.match(/\btimeout:\s*([\d_]+)/);
        expect(t, `${f}: a git-data ssh dial with no explicit timeout`).not.toBeNull();
        timeouts.push(Number(t![1].replace(/_/g, "")));
      }
    }
    // Non-vacuity: provision + remove (30 s), the fetch and the push (60 s).
    expect(timeouts.length).toBeGreaterThanOrEqual(4);
    expect(Math.min(...timeouts)).toBe(30_000);
    const windowMs =
      (Number(BOUND.ConnectTimeout) + Number(BOUND.ServerAliveInterval) * Number(BOUND.ServerAliveCountMax)) * 1000;
    expect(windowMs).toBeLessThan(Math.min(...timeouts));
  });
});

function stripComments(src: string): string {
  return src.replace(/\/\*[\s\S]*?\*\//g, "").replace(/(^|[^:"'`])\/\/.*$/gm, "$1");
}

/** The balanced `open ... close` span starting at text[at] (string literals skipped). */
function balanced(text: string, at: number, open: string, close: string): string {
  let depth = 0;
  for (let i = at; i < text.length; i++) {
    const c = text[i];
    if (c === '"' || c === "'" || c === "`") {
      for (i++; i < text.length && text[i] !== c; i++) if (text[i] === "\\") i++;
      continue;
    }
    if (c === open) depth++;
    else if (c === close && --depth === 0) return text.slice(at, i + 1);
  }
  return text.slice(at);
}

/** The array or string literal a `const|let|var NAME = ...` binds, or null. */
function definitionOf(code: string, name: string): string | null {
  const m = new RegExp(`\\b(?:const|let|var)\\s+${name}\\b[^=;]*=\\s*`).exec(code);
  if (!m) return null;
  const at = m.index + m[0].length;
  const c = code[at];
  if (c === "[") return balanced(code, at, "[", "]");
  if (c === '"' || c === "'" || c === "`") return code.slice(at, code.indexOf(c, at + 1) + 1);
  return null;
}

/** Inline every `...IDENT` spread whose definition is a literal in this file (bounded depth). */
function expand(code: string, literal: string, depth = 0): string {
  if (depth > 4) return literal;
  return literal.replace(/\.\.\.\s*([A-Za-z_$][\w$]*)\b(?!\s*[.(])/g, (all, id: string) => {
    const def = definitionOf(code, id);
    return def ? expand(code, def, depth + 1) : all;
  });
}

const REQUIRED = ["ConnectTimeout=", "ServerAliveInterval=", "ServerAliveCountMax="];
type Site = { form: string; set: string | null };

/**
 * Every ssh option set a source file builds, anchored on the CALL FORM (never on an option name, so a set
 * that forgot IdentitiesOnly is still found): an exec/spawn-family call whose first argument is "ssh",
 * a GIT_SSH_COMMAND assignment, and a string-form `ssh ... -o` command. `set === null` means the set
 * could not be resolved to a literal in the file (itself a violation: it cannot be proven bounded).
 */
function sshSites(raw: string): Site[] {
  const code = stripComments(raw);
  const sites: Site[] = [];
  const resolve = (at: number): string | null => {
    const c = code[at];
    if (c === "[") return expand(code, balanced(code, at, "[", "]"));
    if (c === '"' || c === "'" || c === "`") return code.slice(at, code.indexOf(c, at + 1) + 1);
    const id = /^[A-Za-z_$][\w$]*(?![\w$.(])/.exec(code.slice(at));
    const def = id ? definitionOf(code, id[0]) : null;
    return def ? expand(code, def) : null;
  };
  for (const m of code.matchAll(/\b\w*(?:execFile|spawn|exec|execa)\w*\s*\(\s*["'`]ssh["'`]\s*,\s*/g)) {
    sites.push({ form: "spawn of ssh", set: resolve(m.index! + m[0].length) });
  }
  for (const m of code.matchAll(/\bGIT_SSH_COMMAND\s*[:=]\s*/g)) {
    sites.push({ form: "GIT_SSH_COMMAND", set: resolve(m.index! + m[0].length) });
  }
  for (const m of code.matchAll(/(["'`])[^"'`\n]*\bssh(?=\s)[^"'`\n]*?\s-o\s[^"'`\n]*\1/g)) {
    sites.push({ form: "string-form ssh -o", set: m[0] });
  }
  return sites;
}

function violations(file: string, raw: string): string[] {
  const out: string[] = [];
  for (const s of sshSites(raw)) {
    if (s.set === null) out.push(`${file}: ${s.form}: option set cannot be resolved to a literal`);
    else for (const r of REQUIRED) if (!s.set.includes(r)) out.push(`${file}: ${s.form}: missing ${r}`);
  }
  return out;
}

describe("every ssh option set under server/ carries the connect bound (#8211, call-form sweep)", () => {
  const root = join(__dirname, "..");
  const files: string[] = [];
  const walk = (rel: string) => {
    for (const e of readdirSync(join(root, rel))) {
      if (e === "node_modules" || e.startsWith(".")) continue;
      const r = join(rel, e);
      if (statSync(join(root, r)).isDirectory()) walk(r);
      else if (/\.(ts|tsx|js|mjs|cjs)$/.test(e) && !/\.test\./.test(e)) files.push(r);
    }
  };
  for (const d of ["server", "lib", "app"]) walk(d);
  const read = (f: string) => readFileSync(join(root, f), "utf8");

  test("the sweep sees the source and finds the git-auth.ts sites (non-vacuity)", () => {
    expect(files.length).toBeGreaterThan(200);
    expect(files).toContain(join("server", "git-auth.ts"));
    const found: Record<string, number> = {};
    for (const f of files) {
      const n = sshSites(read(f)).length;
      if (n) found[f] = n;
    }
    expect(found).toEqual({ [join("server", "git-auth.ts")]: 2 });
  });

  test("no ssh option set in the app lacks ConnectTimeout, ServerAliveInterval or ServerAliveCountMax", () => {
    const bad: string[] = [];
    for (const f of files) bad.push(...violations(f, read(f)));
    expect(bad).toEqual([]);
  });

  test("the bound option set is defined once, with the exact values, and spread at both git-auth.ts sites", () => {
    const code = stripComments(read(join("server", "git-auth.ts")));
    const def = definitionOf(code, "GIT_DATA_SSH_BOUND_OPTS");
    expect(def).not.toBeNull();
    for (const [k, v] of Object.entries(BOUND)) expect(def).toContain(`"${k}=${v}"`);
    for (const k of Object.keys(BOUND)) expect(code.match(new RegExp(`${k}=`, "g"))).toHaveLength(1);
    expect(code.match(/\.\.\.GIT_DATA_SSH_BOUND_OPTS/g)).toHaveLength(2);
  });

  // The detector must be able to fail: each planted shape is RED on its own.
  test.each([
    ["server/zz-extra.ts", 'await execFileAsync("ssh", ["-i", k, "-o", "IdentitiesOnly=yes", "-o", "BatchMode=yes", host, cmd]);', "spawn of ssh"],
    ["server/zz-extra.ts", 'const a = ["-i", k, "-o", "BatchMode=yes"]; spawn("ssh", a);', "spawn of ssh"],
    ["server/git-auth.ts", 'await execFileAsync("ssh", ["-i", k, "-o", "BatchMode=yes", host, cmd]);', "spawn of ssh"],
    ["server/zz-extra.ts", 'const env = { GIT_SSH_COMMAND: "ssh -i k -o BatchMode=yes" };', "GIT_SSH_COMMAND"],
    ["server/zz-extra.ts", "const env = { GIT_SSH_COMMAND: cmdFromElsewhere };", "GIT_SSH_COMMAND"],
    ["server/zz-extra.ts", 'exec(`ssh -o BatchMode=yes -i ${k} ${host} true`);', "string-form ssh -o"],
  ])("planted in %s: %s is RED (%s)", (file, line, form) => {
    const v = violations(file, line);
    expect(v.length).toBeGreaterThan(0);
    expect(v.some((x) => x.startsWith(`${file}: ${form}`))).toBe(true);
  });

  test("a bounded planted set is GREEN, and a comment naming ssh is not a site", () => {
    const good =
      'const B: readonly string[] = ["-o", "ConnectTimeout=8", "-o", "ServerAliveInterval=6", "-o", "ServerAliveCountMax=2"]; ' +
      'const o = ["-o", "IdentitiesOnly=yes", ...B]; await execFileAsync("ssh", o);';
    expect(violations("server/zz-ok.ts", good)).toEqual([]);
    expect(violations("server/zz-ok.ts", '// execFile("ssh", [...]) lives elsewhere\n/* GIT_SSH_COMMAND: x */')).toEqual([]);
  });
});
