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
import { readFileSync } from "node:fs";
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
  ConnectTimeout: "10",
  ServerAliveInterval: "10",
  ServerAliveCountMax: "3",
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

  test("the worst-case dead-peer window fits inside the shortest caller timeout (30 s provision)", () => {
    // connect: ConnectTimeout; stalled session: Interval x CountMax. Each is bounded on its own;
    // the larger of the two must stay under the 30 s provision / remove timeout.
    const connect = Number(BOUND.ConnectTimeout);
    const stalled = Number(BOUND.ServerAliveInterval) * Number(BOUND.ServerAliveCountMax);
    expect(Math.max(connect, stalled)).toBeLessThanOrEqual(30);
  });
});

// WIRING (comment-stripped, anchored on the construct): no ssh option array that carries the
// identity/batch options may survive without the shared bound spread. A third site added later
// with a bare array is RED here even if its own unit test was never written.
describe("no bare git-data ssh option array survives in server/git-auth.ts (#8211)", () => {
  const src = readFileSync(join(__dirname, "..", "server", "git-auth.ts"), "utf8");
  const code = src.replace(/\/\*[\s\S]*?\*\//g, "").replace(/(^|[^:"'`])\/\/.*$/gm, "$1");

  /** Each `[ ... ]` literal that contains the "IdentitiesOnly=yes" element (an ssh option array). */
  function sshOptionArrays(text: string): string[] {
    const arrays: string[] = [];
    let from = 0;
    for (;;) {
      const at = text.indexOf('"IdentitiesOnly=yes"', from);
      if (at < 0) break;
      const open = text.lastIndexOf("[", at);
      const close = text.indexOf("]", at);
      arrays.push(text.slice(open, close + 1));
      from = close + 1;
    }
    return arrays;
  }

  test("the bound option set is defined once with the exact values", () => {
    const def = code.match(/const\s+(\w+)\s*:\s*readonly string\[\]\s*=\s*\[([\s\S]*?)\];/g) ?? [];
    const bound = def.filter((d) => d.includes("ConnectTimeout="));
    expect(bound).toHaveLength(1);
    const body = bound[0];
    for (const [k, v] of Object.entries(BOUND)) expect(body).toContain(`"${k}=${v}"`);
    expect(code.match(/ConnectTimeout=/g)).toHaveLength(1);
    expect(code.match(/ServerAliveInterval=/g)).toHaveLength(1);
    expect(code.match(/ServerAliveCountMax=/g)).toHaveLength(1);
  });

  test("every ssh option array (the git transport and the provision/remove dial) spreads the bound set", () => {
    const name = (code.match(/const\s+(\w+)\s*:\s*readonly string\[\]\s*=\s*\[[^\]]*ConnectTimeout=/) ?? [])[1];
    expect(name, "bound const name").toBeTruthy();
    const arrays = sshOptionArrays(code);
    expect(arrays).toHaveLength(2);
    for (const a of arrays) expect(a, a).toContain(`...${name}`);
  });

  test("the sweep is live: a bare array is detected", () => {
    const bare = 'const x = ["-i", k, "-o", "IdentitiesOnly=yes", "-o", "BatchMode=yes"];';
    expect(sshOptionArrays(bare)).toHaveLength(1);
    expect(sshOptionArrays(bare)[0]).not.toContain("...");
  });

  test("no other app source builds ssh options (BatchMode / ConnectTimeout live only in git-auth.ts)", async () => {
    const { readdirSync, statSync } = await import("node:fs");
    const root = join(__dirname, "..");
    const hits: string[] = [];
    const walk = (rel: string) => {
      for (const e of readdirSync(join(root, rel))) {
        if (e === "node_modules" || e.startsWith(".")) continue;
        const r = join(rel, e);
        if (statSync(join(root, r)).isDirectory()) walk(r);
        else if (/\.(ts|tsx|js|mjs)$/.test(e) && !/\.test\./.test(e) && r !== join("server", "git-auth.ts")) {
          const t = readFileSync(join(root, r), "utf8")
            .replace(/\/\*[\s\S]*?\*\//g, "")
            .replace(/(^|[^:"'`])\/\/.*$/gm, "$1");
          if (/["'`](?:BatchMode|ConnectTimeout|ServerAliveInterval)=/.test(t)) hits.push(r);
        }
      }
    };
    for (const d of ["server", "lib", "app"]) walk(d);
    expect(hits).toEqual([]);
  });
});
