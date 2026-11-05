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
import { GIT_HARDENING_ARGS, GIT_HARDENING_ENV } from "../server/inngest/functions/_git-hardening";
import { HARDENED_ENV_ALLOWLIST } from "../server/git-hardened-env";

// Every secret (and every git/proxy knob) the server process holds or could be handed: none may reach a hardened child. Names, not
// values: the point is that a NEW allowlist entry naming any of them is a red test.
const SERVER_SECRET_KEYS = [
  "SUPABASE_SERVICE_ROLE_KEY",
  "ANTHROPIC_API_KEY",
  "GITHUB_TOKEN",
  "GH_TOKEN",
  "DATABASE_URL",
  "GITHUB_APP_PRIVATE_KEY",
  "GITHUB_APP_ID",
  "GITHUB_APP_CLIENT_SECRET",
  "STRIPE_SECRET_KEY",
  "STRIPE_WEBHOOK_SECRET",
  "SENTRY_AUTH_TOKEN",
  "INNGEST_SIGNING_KEY",
  "INNGEST_EVENT_KEY",
  "BYOK_ENCRYPTION_KEY",
  "FLAGSMITH_SERVER_KEY",
  "DOPPLER_TOKEN",
  "RESEND_API_KEY",
  "NODE_OPTIONS",
];
const CANARY_KEYS = [
  "SOLEUR_TEST_SECRET_CANARY",
  "HTTPS_PROXY",
  "https_proxy",
  "ALL_PROXY",
  "GIT_SSH_COMMAND",
  "GIT_EXTERNAL_DIFF",
  "GIT_ALLOW_PROTOCOL",
  ...SERVER_SECRET_KEYS,
];

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
    // GIT_ALLOW_PROTOCOL is the one canary that is pinned rather than dropped: the server's value is replaced by "https" below.
    for (const k of CANARY_KEYS.filter((c) => c !== "GIT_ALLOW_PROTOCOL")) expect(env[k], k).toBeUndefined();
    expect(env.GIT_DIR).toBe("/ws/parent/work/.git");
    expect(env.GIT_COMMON_DIR).toBe("/ws/parent/work/.git");
    expect(env.GIT_OBJECT_DIRECTORY).toBe("/ws/parent/work/.git/objects");
    expect(env.GIT_ALLOW_PROTOCOL).toBe("https");
    expect(env.GIT_CEILING_DIRECTORIES).toBe("/ws/parent");
    expect(env.GIT_CONFIG_SYSTEM).toBe("/dev/null");
    expect(env.GIT_NO_REPLACE_OBJECTS).toBe("1");
    expect(env.GIT_CONFIG_GLOBAL).toBe("/dev/null");
    expect(env.GIT_TERMINAL_PROMPT).toBe("0");
    expect(env.GIT_USERNAME).toBe("x-access-token");
    expect(env.GIT_INSTALLATION_TOKEN).toMatch(/^ghs_/);
    expect(opts.hardened).toBeUndefined();
  });

  test("hardened: the child env is EXACTLY the allowlist (those that are set) + the shared hardening env + the pins + the askpass wiring", async () => {
    const saved = new Map<string, string | undefined>();
    for (const k of HARDENED_ENV_ALLOWLIST) {
      saved.set(k, process.env[k]);
      process.env[k] = `allowlisted-${k}`;
    }
    try {
      await gitWithInstallationAuth(["push", "u", "HEAD:refs/heads/x"], 1, { cwd: "/ws/parent/work", hardened: true });
    } finally {
      for (const [k, v] of saved) {
        if (v === undefined) delete process.env[k];
        else process.env[k] = v;
      }
    }
    const env = (calls[0] as Call).opts.env as NodeJS.ProcessEnv;
    const expected = [
      ...HARDENED_ENV_ALLOWLIST,
      ...Object.keys(GIT_HARDENING_ENV),
      "GIT_DIR",
      "GIT_COMMON_DIR",
      "GIT_OBJECT_DIRECTORY",
      "GIT_ALLOW_PROTOCOL",
      "GIT_CEILING_DIRECTORIES",
      "GIT_ASKPASS",
      "GIT_INSTALLATION_TOKEN",
      "GIT_USERNAME",
      "GIT_TERMINAL_PROMPT",
      "GIT_TERMINAL_PROGRESS",
    ];
    expect(Object.keys(env).sort()).toEqual([...new Set(expected)].sort());
    for (const k of HARDENED_ENV_ALLOWLIST) expect(env[k], k).toBe(`allowlisted-${k}`);
    for (const k of SERVER_SECRET_KEYS) expect(HARDENED_ENV_ALLOWLIST, k).not.toContain(k);
    // The allowlist itself carries no secret-shaped name (a new entry must be argued for in a reviewed diff, not slip in).
    for (const k of HARDENED_ENV_ALLOWLIST) expect(k, k).not.toMatch(/KEY|TOKEN|SECRET|PASSWORD|URL|PROXY/);
  });

  test("hardened argv: credential reset, the shared hardening args, the proxy and extra-header resets, then the command", async () => {
    await gitWithInstallationAuth(["push", "u", "HEAD:refs/heads/x"], 1, { cwd: "/ws/parent/work", hardened: true });
    const { args } = calls[0] as Call;
    expect(args.slice(0, 2)).toEqual(["-c", "credential.helper="]);
    expect(args.slice(2, 2 + GIT_HARDENING_ARGS.length)).toEqual([...GIT_HARDENING_ARGS]);
    for (const c of ["http.proxy=", "http.https://github.com/.proxy=", "http.extraHeader=", "push.followTags=false"]) {
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
