/**
 * #11636 / ADR-309 9b: the argv and child ENVIRONMENT of the hardened `gitWithInstallationAuth`, observed at the `execFile`
 * seam (no git is run). The hardened option is the branded isolated push directory (`IsolatedPushDir`), validated at runtime
 * BEFORE a token is minted. The legacy form is asserted unchanged next to it, so "opt-in" is a tested claim.
 */
import { describe, test, expect, vi, beforeEach, afterEach } from "vitest";
import { existsSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

type Call = { cmd: string; args: string[]; opts: { env?: NodeJS.ProcessEnv; cwd?: string; hardened?: unknown } };
const { calls, mint } = vi.hoisted(() => ({
  calls: [] as unknown[],
  mint: vi.fn(async (_id: number) => `ghs_${"a".repeat(40)}`),
}));

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
vi.mock("../server/github-app", () => ({ generateInstallationToken: (id: number) => mint(id) }));
vi.mock("../server/logger", () => ({ createChildLogger: () => ({ info: vi.fn(), warn: vi.fn(), error: vi.fn() }) }));

import { gitWithInstallationAuth } from "../server/git-auth";
import { GIT_HARDENING_ARGS, GIT_HARDENING_ENV } from "../server/inngest/functions/_git-hardening";
import {
  HARDENED_ENV_ALLOWLIST,
  ISOLATED_PUSH_DIR_BRAND,
  buildIsolatedGitEnv,
  type IsolatedPushDir,
} from "../server/git-hardened-env";
import { stripComments } from "./approval/source-scan";

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
  let base: string;
  let root: string;
  let iso: IsolatedPushDir;
  const ALT = "/ws/parent/work/.git/objects";
  const call = (over: Record<string, unknown> = {}) =>
    gitWithInstallationAuth(["push", "u", `${"c".repeat(40)}:refs/heads/x`], 1, { hardened: iso, ...over } as never);

  beforeEach(() => {
    calls.length = 0;
    mint.mockClear();
    for (const k of CANARY_KEYS) process.env[k] = "canary-value";
    // The isolated shape the creator always produces: `<home>/.soleur-push/run-<x>`.
    base = mkdtempSync(join(tmpdir(), "git-auth-env-"));
    root = join(base, ".soleur-push", "run-fixture");
    mkdirSync(root, { recursive: true });
    iso = { gitDir: root, alternateObjectDirectory: ALT, [ISOLATED_PUSH_DIR_BRAND]: true };
  });
  afterEach(() => {
    for (const k of CANARY_KEYS) delete process.env[k];
    delete process.env.GIT_COMMON_DIR;
    delete process.env.GIT_INDEX_FILE;
    delete process.env.GIT_WORK_TREE;
    delete process.env.GIT_DIR;
    rmSync(base, { recursive: true, force: true });
  });

  test("hardened: no process.env canary, no proxy var and no GIT_SSH_COMMAND reaches the child; GIT_DIR is the isolated directory", async () => {
    await call();
    const { opts } = calls[0] as Call;
    const env = opts.env as NodeJS.ProcessEnv;
    // GIT_ALLOW_PROTOCOL is the one canary that is pinned rather than dropped: the server's value is replaced by "https" below.
    for (const k of CANARY_KEYS.filter((c) => c !== "GIT_ALLOW_PROTOCOL")) expect(env[k], k).toBeUndefined();
    expect(env.GIT_DIR).toBe(root);
    expect(env.GIT_ALTERNATE_OBJECT_DIRECTORIES).toBe(ALT);
    expect(env.HOME).toBe(root); // never the server's HOME: ~/.netrc and $XDG_CONFIG_HOME/git/* are unreachable
    expect(env.GIT_ALLOW_PROTOCOL).toBe("https");
    expect(env.GIT_CONFIG_SYSTEM).toBe("/dev/null");
    expect(env.GIT_NO_REPLACE_OBJECTS).toBe("1");
    expect(env.GIT_CONFIG_GLOBAL).toBe("/dev/null");
    expect(env.GIT_TERMINAL_PROMPT).toBe("0");
    expect(env.GIT_USERNAME).toBe("x-access-token");
    expect(env.GIT_INSTALLATION_TOKEN).toMatch(/^ghs_/);
    expect(opts.hardened).toBeUndefined();
    // Pins that do nothing for a fresh bare directory are gone.
    for (const k of ["GIT_COMMON_DIR", "GIT_OBJECT_DIRECTORY", "GIT_CEILING_DIRECTORIES"]) expect(env[k], k).toBeUndefined();
  });

  test("hardened: runs with cwd = the isolated directory, placed after the option spread (a caller cwd is refused, never overridden)", async () => {
    await call();
    expect((calls[0] as Call).opts.cwd).toBe(root);
    calls.length = 0;
    mint.mockClear();
    await expect(call({ cwd: "/ws/parent/work" })).rejects.toThrow(/isolated push directory|cwd/);
    expect(calls).toHaveLength(0);
    expect(mint).not.toHaveBeenCalled();
  });

  test("hardened: server GIT_DIR / GIT_COMMON_DIR / GIT_INDEX_FILE / GIT_WORK_TREE never reach the child, except GIT_DIR = the isolated directory", async () => {
    process.env.GIT_DIR = "/other/.git";
    process.env.GIT_COMMON_DIR = "/other/.git";
    process.env.GIT_INDEX_FILE = "/other/index";
    process.env.GIT_WORK_TREE = "/other";
    await call();
    const env = (calls[0] as Call).opts.env as NodeJS.ProcessEnv;
    expect(env.GIT_DIR).toBe(root);
    for (const k of ["GIT_COMMON_DIR", "GIT_INDEX_FILE", "GIT_WORK_TREE"]) expect(env[k], k).toBeUndefined();
  });

  test("hardened: the askpass script lives INSIDE the isolated directory (not $HOME) and is gone after the call", async () => {
    await call();
    const env = (calls[0] as Call).opts.env as NodeJS.ProcessEnv;
    expect(String(env.GIT_ASKPASS).startsWith(`${root}/`)).toBe(true);
    expect(existsSync(String(env.GIT_ASKPASS))).toBe(false);
    expect(readdirSync(root)).toEqual([]);
  });

  test("hardened: a stray true, an unbranded object, a relative or unsafe path and a missing option are refused BEFORE a token is minted", async () => {
    const bad: unknown[] = [
      true,
      null,
      { gitDir: root, alternateObjectDirectory: ALT },
      { ...iso, gitDir: "relative/dir" },
      { ...iso, alternateObjectDirectory: "/ws/a:b/.git/objects" },
      { ...iso, gitDir: `${root}\n` },
      "isolated",
      // FORGED handles: the exported brand plus syntactically safe paths, but not the shape `createIsolatedPushDir` produces.
      { ...iso, gitDir: "/ws/parent/work/.git" }, // the workspace .git itself
      { ...iso, gitDir: "/ws/parent/work/.git/objects" },
      { ...iso, gitDir: "/ws/parent/work" },
      { ...iso, gitDir: `${base}/.soleur-push/not-a-run` }, // right parent, wrong child
      { ...iso, gitDir: `${base}/.soleur-push/run-` }, // empty run suffix
      { ...iso, gitDir: `${base}/elsewhere/run-x` }, // right child, wrong parent
      { ...iso, gitDir: `${root}/../run-other` }, // not normalized
      { ...iso, gitDir: `${root}/` }, // trailing separator
      { ...iso, gitDir: "/ws/parent/work/.soleur-push/run-x" }, // looks right but lives INSIDE the alternate's workspace
      { ...iso, alternateObjectDirectory: "/ws/parent/work/.git/objects/" },
      { ...iso, alternateObjectDirectory: "/ws/parent/work/objects" }, // not <ws>/.git/objects
      { ...iso, alternateObjectDirectory: `${root}/../objects` },
    ];
    for (const b of bad) {
      calls.length = 0;
      mint.mockClear();
      await expect(gitWithInstallationAuth(["push"], 1, { hardened: b } as never), JSON.stringify(b)).rejects.toThrow();
      expect(mint).not.toHaveBeenCalled();
      expect(calls).toHaveLength(0);
    }
  });

  test("hardened: the child env is EXACTLY the allowlist (those that are set) + the shared hardening env + the pins + the askpass wiring", async () => {
    const saved = new Map<string, string | undefined>();
    for (const k of HARDENED_ENV_ALLOWLIST) {
      saved.set(k, process.env[k]);
      process.env[k] = `allowlisted-${k}`;
    }
    try {
      await call();
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
      "GIT_ALTERNATE_OBJECT_DIRECTORIES",
      "GIT_ALLOW_PROTOCOL",
      "GIT_ASKPASS",
      "GIT_INSTALLATION_TOKEN",
      "GIT_USERNAME",
      "GIT_TERMINAL_PROMPT",
      "GIT_TERMINAL_PROGRESS",
    ];
    expect(Object.keys(env).sort()).toEqual([...new Set(expected)].sort());
    // HOME is allowlisted but always OVERRIDDEN with the isolated directory.
    for (const k of HARDENED_ENV_ALLOWLIST.filter((a) => a !== "HOME")) expect(env[k], k).toBe(`allowlisted-${k}`);
    expect(env.HOME).toBe(root);
    for (const k of SERVER_SECRET_KEYS) expect(HARDENED_ENV_ALLOWLIST, k).not.toContain(k);
    // The allowlist itself carries no secret-shaped name (a new entry must be argued for in a reviewed diff, not slip in).
    for (const k of HARDENED_ENV_ALLOWLIST) expect(k, k).not.toMatch(/KEY|TOKEN|SECRET|PASSWORD|URL|PROXY/);
  });

  test("the allowlist is EXACTLY the forwarded set (dropping or adding any key is a red test)", () => {
    expect([...HARDENED_ENV_ALLOWLIST].sort()).toEqual(["HOME", "LANG", "LC_ALL", "PATH", "SSL_CERT_DIR", "SSL_CERT_FILE", "TMPDIR"]);
    const saved = new Map<string, string | undefined>();
    for (const k of HARDENED_ENV_ALLOWLIST) saved.set(k, process.env[k]);
    for (const k of ["PATH", "SSL_CERT_FILE", "SSL_CERT_DIR", "TMPDIR", "LANG", "LC_ALL"]) process.env[k] = `forwarded-${k}`;
    try {
      const env = buildIsolatedGitEnv(iso);
      for (const k of ["PATH", "SSL_CERT_FILE", "SSL_CERT_DIR", "TMPDIR", "LANG", "LC_ALL"]) expect(env[k], k).toBe(`forwarded-${k}`);
    } finally {
      for (const [k, v] of saved) {
        if (v === undefined) delete process.env[k];
        else process.env[k] = v;
      }
    }
  });

  // The ONLY keys `extra` may carry: the askpass wiring `gitWithInstallationAuth` builds (git-auth.ts `authEnv`) and the one
  // test-only seam (a CA bundle for the local TLS server). Everything else is refused, so a future caller cannot reach PATH,
  // TMPDIR, SSL_CERT_*, LANG, LC_ALL or an unpinned GIT_* / loader variable through `extra`.
  const AUTH_ENV = {
    GIT_ASKPASS: "/ws/parent/.soleur-push/run-fixture/.askpass-x.sh",
    GIT_INSTALLATION_TOKEN: "ghs_token",
    GIT_USERNAME: "x-access-token",
    GIT_TERMINAL_PROMPT: "0",
    GIT_TERMINAL_PROGRESS: "0",
    GIT_CONFIG_NOSYSTEM: "1",
    GIT_CONFIG_GLOBAL: "/dev/null",
  };

  test("buildIsolatedGitEnv: the production authEnv and the test-only GIT_SSL_CAINFO seam are accepted and land in the child env", () => {
    const env = buildIsolatedGitEnv(iso, { ...AUTH_ENV, GIT_SSL_CAINFO: "/test/ca.pem" });
    for (const [k, v] of Object.entries(AUTH_ENV)) expect(env[k], k).toBe(k === "GIT_CONFIG_GLOBAL" ? "/dev/null" : v);
    expect(env.GIT_SSL_CAINFO).toBe("/test/ca.pem");
    expect(env.GIT_DIR).toBe(root);
    expect(env.HOME).toBe(root);
  });

  test.each([
    // pinned keys
    "GIT_DIR",
    "HOME",
    "GIT_ALLOW_PROTOCOL",
    "GIT_ALTERNATE_OBJECT_DIRECTORIES",
    "GIT_NO_REPLACE_OBJECTS",
    "GIT_CONFIG_SYSTEM",
    // allowlisted-but-unpinned passthrough keys
    "PATH",
    "TMPDIR",
    "SSL_CERT_FILE",
    "SSL_CERT_DIR",
    "LANG",
    "LC_ALL",
    // unpinned git and loader variables
    "GIT_EXEC_PATH",
    "GIT_OBJECT_DIRECTORY",
    "GIT_COMMON_DIR",
    "GIT_CONFIG_COUNT",
    "GIT_CONFIG_PARAMETERS",
    "GIT_CONFIG_KEY_0",
    "GIT_CONFIG_VALUE_0",
    "GIT_TRACE",
    "GIT_SSH_COMMAND",
    "GIT_PROXY_COMMAND",
    "LD_PRELOAD",
    "NODE_OPTIONS",
    "HTTPS_PROXY",
    "git_dir", // case variants are other keys to the OS, still refused
  ])("buildIsolatedGitEnv: extra carrying %s is refused (an explicit allowed set, not a denylist)", (key) => {
    expect(() => buildIsolatedGitEnv(iso, { ...AUTH_ENV, [key]: "/evil" })).toThrow(/environment key is not allowed/);
    expect(() => buildIsolatedGitEnv(iso, { [key]: "/evil" })).toThrow(/environment key is not allowed/);
  });

  test("buildIsolatedGitEnv: the refusal names no value (the token and askpass path never appear in the error)", () => {
    let err: unknown;
    try {
      buildIsolatedGitEnv(iso, { GIT_INSTALLATION_TOKEN: "ghs_secret_value", LD_PRELOAD: "/evil.so" });
    } catch (e) {
      err = e;
    }
    expect((err as Error).message).not.toMatch(/ghs_secret_value|\/evil\.so/);
  });

  test("buildIsolatedGitEnv: the allowlisted passthrough keys come from the server environment, not from extra, and the pins always win", () => {
    const saved = process.env.PATH;
    process.env.PATH = "/usr/bin";
    try {
      // The two allowed keys that the shared hardening environment also pins: the pinned value wins over what `extra` carries.
      const env = buildIsolatedGitEnv(iso, { ...AUTH_ENV, GIT_CONFIG_GLOBAL: "/ws/evil-gitconfig", GIT_CONFIG_NOSYSTEM: "0" });
      expect(env.PATH).toBe("/usr/bin");
      expect(env.GIT_CONFIG_NOSYSTEM).toBe("1");
      expect(env.GIT_DIR).toBe(root);
      expect(env.GIT_ALLOW_PROTOCOL).toBe("https");
      expect(env.GIT_ALTERNATE_OBJECT_DIRECTORIES).toBe(ALT);
      expect(env.GIT_CONFIG_GLOBAL).toBe("/dev/null");
      expect(env.GIT_NO_REPLACE_OBJECTS).toBe("1");
    } finally {
      if (saved === undefined) delete process.env.PATH;
      else process.env.PATH = saved;
    }
  });

  test("git-hardened-env.ts is a leaf: it imports only node:path and the shared hardening constants, never the creator or fs", () => {
    const code = stripComments(readFileSync(join(__dirname, "../server/git-hardened-env.ts"), "utf8"));
    const specs = [...code.matchAll(/\bfrom\s*(["'])([^"']+)\1/g)].map((m) => m[2]);
    expect([...specs].sort()).toEqual(["./inngest/functions/_git-hardening", "node:path"]);
    expect(code).not.toMatch(/import\s*\(/);
    expect(code).not.toMatch(/^\s*import\s*["']/m); // a side-effect import (`import "node:fs"`) has no `from`
    expect(code).not.toMatch(/\brequire\s*\(/);
    expect(code).not.toMatch(/git-isolated-push-dir|node:fs|child_process/);
  });

  test("hardened argv: credential reset, the shared hardening args, the proxy and extra-header resets, then the command", async () => {
    await call();
    const { args } = calls[0] as Call;
    expect(args.slice(0, 2)).toEqual(["-c", "credential.helper="]);
    expect(args.slice(2, 2 + GIT_HARDENING_ARGS.length)).toEqual([...GIT_HARDENING_ARGS]);
    for (const c of ["http.proxy=", "http.https://github.com/.proxy=", "http.extraHeader=", "push.followTags=false"]) {
      const i = args.indexOf(c);
      expect(i, c).toBeGreaterThan(0);
      expect(args[i - 1]).toBe("-c");
    }
    expect(args.slice(-3)).toEqual(["push", "u", `${"c".repeat(40)}:refs/heads/x`]);
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
