/**
 * #11636: the argv and child ENVIRONMENT of the hardened `gitWithInstallationAuth`, observed at the `execFile` seam (no git is
 * run). The legacy form is asserted unchanged next to it, so "opt-in" is a tested claim.
 */
import { describe, test, expect, vi, beforeEach, afterEach } from "vitest";

type Call = { cmd: string; args: string[]; opts: { env?: NodeJS.ProcessEnv; cwd?: string; hardened?: unknown } };
const { calls } = vi.hoisted(() => ({ calls: [] as unknown[] }));

vi.mock("child_process", async () => {
  const actual = await vi.importActual<typeof import("child_process")>("child_process");
  return {
    ...actual,
    execFile: (cmd: string, args: string[], opts: Call["opts"], cb: (e: null, r: { stdout: Buffer; stderr: Buffer }) => void) => {
      calls.push({ cmd, args, opts });
      cb(null, { stdout: Buffer.from(""), stderr: Buffer.from("") });
    },
  };
});
vi.mock("../server/github-app", () => ({ generateInstallationToken: async () => `ghs_${"a".repeat(40)}` }));
vi.mock("../server/logger", () => ({ createChildLogger: () => ({ info: vi.fn(), warn: vi.fn(), error: vi.fn() }) }));

import { gitWithInstallationAuth } from "../server/git-auth";
import { GIT_HARDENING_ARGS } from "../server/inngest/functions/_git-hardening";

const CANARY_KEYS = ["SOLEUR_TEST_SECRET_CANARY", "HTTPS_PROXY", "https_proxy", "ALL_PROXY", "GIT_SSH_COMMAND", "GIT_EXTERNAL_DIFF"];

describe("gitWithInstallationAuth child env and argv", () => {
  beforeEach(() => {
    calls.length = 0;
    for (const k of CANARY_KEYS) process.env[k] = "canary-value";
  });
  afterEach(() => {
    for (const k of CANARY_KEYS) delete process.env[k];
  });

  test("hardened: no process.env canary, no proxy var and no GIT_SSH_COMMAND reaches the child", async () => {
    await gitWithInstallationAuth(["push", "u", "HEAD:refs/heads/x"], 1, { cwd: "/ws/parent/work", hardened: true });
    const { opts } = calls[0] as Call;
    const env = opts.env as NodeJS.ProcessEnv;
    for (const k of CANARY_KEYS) expect(env[k], k).toBeUndefined();
    const allowed = new Set([
      "PATH", "HOME", "TMPDIR", "LANG", "LC_ALL", "SSL_CERT_FILE", "SSL_CERT_DIR",
      "GIT_ASKPASS", "GIT_INSTALLATION_TOKEN", "GIT_USERNAME", "GIT_TERMINAL_PROMPT", "GIT_TERMINAL_PROGRESS",
      "GIT_CONFIG_NOSYSTEM", "GIT_CONFIG_GLOBAL", "GIT_CONFIG_SYSTEM", "GIT_NO_REPLACE_OBJECTS", "GIT_DIR",
      "GIT_CEILING_DIRECTORIES",
    ]);
    expect(Object.keys(env).filter((k) => !allowed.has(k))).toEqual([]);
    expect(env.GIT_DIR).toBe("/ws/parent/work/.git");
    expect(env.GIT_CEILING_DIRECTORIES).toBe("/ws/parent");
    expect(env.GIT_CONFIG_GLOBAL).toBe("/dev/null");
    expect(env.GIT_TERMINAL_PROMPT).toBe("0");
    expect(env.GIT_USERNAME).toBe("x-access-token");
    expect(env.GIT_INSTALLATION_TOKEN).toMatch(/^ghs_/);
    expect(opts.hardened).toBeUndefined();
  });

  test("hardened argv: credential reset, the shared hardening args, the proxy and extra-header resets, then the command", async () => {
    await gitWithInstallationAuth(["push", "u", "HEAD:refs/heads/x"], 1, { cwd: "/ws/parent/work", hardened: true });
    const { args } = calls[0] as Call;
    expect(args.slice(0, 2)).toEqual(["-c", "credential.helper="]);
    expect(args.slice(2, 2 + GIT_HARDENING_ARGS.length)).toEqual([...GIT_HARDENING_ARGS]);
    for (const c of ["http.proxy=", "http.https://github.com/.proxy=", "http.extraHeader="]) {
      const i = args.indexOf(c);
      expect(i, c).toBeGreaterThan(0);
      expect(args[i - 1]).toBe("-c");
    }
    expect(args.slice(-3)).toEqual(["push", "u", "HEAD:refs/heads/x"]);
  });

  test("legacy form (field unset): no hardening args, no GIT_DIR, process.env still inherited", async () => {
    await gitWithInstallationAuth(["push", "u", "HEAD:refs/heads/x"], 1, { cwd: "/ws/parent/work" });
    const { args, opts } = calls[0] as Call;
    expect(args).toEqual(["-c", "credential.helper=", "push", "u", "HEAD:refs/heads/x"]);
    expect(args).not.toContain("--no-replace-objects");
    expect(args).not.toContain("core.hooksPath=/dev/null");
    expect(opts.env?.SOLEUR_TEST_SECRET_CANARY).toBe("canary-value");
    expect(opts.env?.GIT_DIR).toBeUndefined();
  });
});
