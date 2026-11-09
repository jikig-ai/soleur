// Helper rows for server/host-git.ts (Ref #9601). The per-consumer carrier battery lives in
// host-git-consumers-real-git.test.ts; these rows pin the helper's own contract with real git where git decides.
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { execFileSync, spawnSync } from "node:child_process";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { GIT_HARDENING_ARGS, GIT_HARDENING_ENV } from "../server/inngest/functions/_git-hardening";
import { AGENT_GIT_GLOBAL_CONFIG, buildScrubbedEnv, hostGitInvocation } from "../server/host-git";
import { AGENT_GIT_GLOBAL_CONFIG as FROM_AGENT_ENV } from "../server/agent-env";
import { buildScrubbedEnv as FROM_GATES } from "../server/compound-promote-create-gates";

const SERVER_KEYS = ["SERVER_ONLY_SENTINEL", "SSL_CERT_FILE", "SSL_CERT_DIR", "GIT_SSL_CAINFO", "HTTPS_PROXY", "https_proxy", "NO_PROXY", "no_proxy", "GIT_DIR", "GIT_EXEC_PATH", "PATH"];
const saved: Record<string, string | undefined> = {};
let root = "";

beforeEach(() => {
  for (const k of SERVER_KEYS) saved[k] = process.env[k];
  root = mkdtempSync(join(tmpdir(), "host-git-helper-"));
});
afterEach(() => {
  for (const k of SERVER_KEYS) {
    if (saved[k] === undefined) delete process.env[k];
    else process.env[k] = saved[k];
  }
  rmSync(root, { recursive: true, force: true });
});

/** A minimal environment for the fixture's OWN git calls (nothing inherited). */
function plainEnv(): NodeJS.ProcessEnv {
  return { PATH: process.env.PATH ?? "/usr/bin:/bin", HOME: root, GIT_CONFIG_GLOBAL: "/dev/null", GIT_CONFIG_NOSYSTEM: "1" } as unknown as NodeJS.ProcessEnv;
}

/** Run real git with the helper's argv and env (the env is the whole environment, nothing inherited). */
function runHost(cwd: string, args: string[], opts: Parameters<typeof hostGitInvocation>[1] = {}): { status: number | null; stdout: string; stderr: string } {
  const h = hostGitInvocation(args, { cwd, ...opts });
  const r = spawnSync("git", h.args, { cwd, env: h.env, encoding: "utf8" });
  return { status: r.status, stdout: r.stdout, stderr: r.stderr };
}

describe("hostGitInvocation: argv", () => {
  it("is the shared hardening block, then the helper-only extras, then the caller's args, in that order", () => {
    const { args } = hostGitInvocation(["status", "--porcelain"]);
    expect(args.slice(0, GIT_HARDENING_ARGS.length)).toEqual([...GIT_HARDENING_ARGS]);
    expect(args.slice(-2)).toEqual(["status", "--porcelain"]);
    const extras = args.slice(GIT_HARDENING_ARGS.length, -2);
    expect(extras).toEqual([
      "-c",
      "safe.bareRepository=explicit",
      "-c",
      "protocol.ext.allow=never",
      "-c",
      "commit.gpgsign=false",
      "-c",
      "tag.gpgsign=false",
    ]);
  });

  it("uses only -c pairs and a leading --no-replace-objects: no other global option (an unknown one exits 129 on git 2.38/2.39)", () => {
    const { args } = hostGitInvocation(["status"]);
    const block = args.slice(0, -1);
    const options = block.filter((a, i) => a.startsWith("-") && block[i - 1] !== "-c");
    expect(options.sort()).toEqual(["--no-replace-objects", "-c", "-c", "-c", "-c", "-c", "-c", "-c"].sort());
  });

  it("a caller's credential-helper reset rides inside args, after the block", () => {
    const { args } = hostGitInvocation(["-c", "credential.helper=", "pull"]);
    const i = args.indexOf("credential.helper=");
    expect(args.indexOf("safe.bareRepository=explicit")).toBeLessThan(i);
    expect(args.slice(i + 1)).toEqual(["pull"]);
  });
});

describe("hostGitInvocation: environment", () => {
  it("carries the shared hardening env, with the global config pointed at the IMAGE identity file (never /dev/null)", () => {
    const { env } = hostGitInvocation(["status"]);
    expect(env.GIT_CONFIG_GLOBAL).toBe(AGENT_GIT_GLOBAL_CONFIG);
    expect(env.GIT_CONFIG_GLOBAL).not.toBe(GIT_HARDENING_ENV.GIT_CONFIG_GLOBAL);
    expect(env.GIT_CONFIG_SYSTEM).toBe("/dev/null");
    expect(env.GIT_CONFIG_NOSYSTEM).toBe("1");
    expect(env.GIT_NO_REPLACE_OBJECTS).toBe("1");
    expect(env.GIT_TERMINAL_PROMPT).toBe("0");
  });

  it("scrubs the server environment: a server-only variable never reaches the child; GIT_DIR and GIT_EXEC_PATH are dropped", () => {
    process.env.SERVER_ONLY_SENTINEL = "must-not-leak";
    process.env.GIT_DIR = "/somewhere/else";
    process.env.GIT_EXEC_PATH = "/somewhere/exec";
    const { env } = hostGitInvocation(["status"]);
    expect(JSON.stringify(env)).not.toContain("must-not-leak");
    expect(env.GIT_DIR).toBeUndefined();
    expect(env.GIT_EXEC_PATH).toBeUndefined();
    const allowed = new Set(["PATH", "LANG", "LC_ALL", "TMPDIR", "HOME", ...Object.keys(GIT_HARDENING_ENV), "GIT_TERMINAL_PROMPT"]);
    for (const k of Object.keys(env)) expect(allowed.has(k), `unexpected variable ${k}`).toBe(true);
  });

  it("forwards the TLS / proxy keys ONLY when they are set in the server environment", () => {
    for (const k of ["SSL_CERT_FILE", "SSL_CERT_DIR", "GIT_SSL_CAINFO", "HTTPS_PROXY", "https_proxy", "NO_PROXY", "no_proxy"]) delete process.env[k];
    const unset = hostGitInvocation(["status"]).env;
    for (const k of ["SSL_CERT_FILE", "SSL_CERT_DIR", "GIT_SSL_CAINFO", "HTTPS_PROXY", "https_proxy", "NO_PROXY", "no_proxy"]) expect(unset[k]).toBeUndefined();
    process.env.SSL_CERT_FILE = "/etc/ssl/certs/ca.pem";
    process.env.HTTPS_PROXY = "http://proxy.invalid:3128";
    const set = hostGitInvocation(["status"]).env;
    expect(set.SSL_CERT_FILE).toBe("/etc/ssl/certs/ca.pem");
    expect(set.HTTPS_PROXY).toBe("http://proxy.invalid:3128");
    expect(set.SSL_CERT_DIR).toBeUndefined();
  });

  it("sets GIT_WORK_TREE only with a cwd and GIT_ALLOW_PROTOCOL only with allowProtocol", () => {
    const bare = hostGitInvocation(["clone", "u", "d"]).env;
    expect(bare.GIT_WORK_TREE).toBeUndefined();
    expect(bare.GIT_ALLOW_PROTOCOL).toBeUndefined();
    const withBoth = hostGitInvocation(["pull"], { cwd: "/ws/a", allowProtocol: "https" }).env;
    expect(withBoth.GIT_WORK_TREE).toBe("/ws/a");
    expect(withBoth.GIT_ALLOW_PROTOCOL).toBe("https");
  });

  it("extraEnv is merged AFTER the scrub and wins (the call-site's own auth variables)", () => {
    const { env } = hostGitInvocation(["push"], {
      extraEnv: { GIT_ASKPASS: "/p/askpass.sh", GIT_INSTALLATION_TOKEN: "t0ken", GIT_TERMINAL_PROMPT: "1" },
    });
    expect(env.GIT_ASKPASS).toBe("/p/askpass.sh");
    expect(env.GIT_INSTALLATION_TOKEN).toBe("t0ken");
    expect(env.GIT_TERMINAL_PROMPT).toBe("1");
  });

  it("drops empty and non-absolute PATH entries (an empty entry is the current directory: the workspace)", () => {
    process.env.PATH = "/usr/bin::relative/bin:/bin:.";
    expect(hostGitInvocation(["status"]).env.PATH).toBe("/usr/bin:/bin");
    process.env.PATH = "::.";
    expect(hostGitInvocation(["status"]).env.PATH).toBe("/usr/bin:/bin");
  });
});

describe("one definition each (moved into the leaf)", () => {
  it("buildScrubbedEnv and AGENT_GIT_GLOBAL_CONFIG are the same values from their old import paths", () => {
    expect(FROM_GATES).toBe(buildScrubbedEnv);
    expect(FROM_AGENT_ENV).toBe(AGENT_GIT_GLOBAL_CONFIG);
  });

  it("buildScrubbedEnv still refuses secret-shaped, GIT_ and non-uppercase extras", () => {
    for (const bad of ["GIT_DIR", "MY_TOKEN", "lower", "GITHUB_X"]) expect(() => buildScrubbedEnv({ [bad]: "x" })).toThrow(/refused/);
  });

  it("layering: the leaf imports only node:os and the hardening constants", () => {
    const src = readFileSync(join(__dirname, "..", "server", "host-git.ts"), "utf8");
    const imports = [...src.matchAll(/^import .* from "([^"]+)";$/gm)].map((m) => m[1]);
    expect(imports.sort()).toEqual(["./inngest/functions/_git-hardening", "node:os"]);
  });
});

describe("hostGitInvocation with real git", () => {
  const ident = { name: "Image Identity", email: "image-identity@example.invalid" };

  function workspace(withLocalIdentity: boolean): string {
    const ws = join(root, "ws");
    mkdirSync(ws);
    const env = plainEnv();
    execFileSync("git", ["init", "-q", "-b", "main"], { cwd: ws, env });
    if (withLocalIdentity) {
      execFileSync("git", ["config", "user.name", "Seeded Local"], { cwd: ws, env });
      execFileSync("git", ["config", "user.email", "seeded-local@example.invalid"], { cwd: ws, env });
    }
    writeFileSync(join(ws, "f.txt"), "x\n");
    execFileSync("git", ["add", "--", "f.txt"], { cwd: ws, env });
    return ws;
  }

  function identityFile(): string {
    const p = join(root, "agent.gitconfig");
    writeFileSync(p, `[user]\n\tname = ${ident.name}\n\temail = ${ident.email}\n`);
    return p;
  }

  it("a workspace with NO local identity commits through the image identity file", () => {
    const ws = workspace(false);
    const r = runHost(ws, ["commit", "-q", "-m", "x"], { globalConfig: identityFile() });
    expect(r.status, r.stderr).toBe(0);
    expect(runHost(ws, ["log", "-1", "--format=%an|%ae"]).stdout.trim()).toBe(`${ident.name}|${ident.email}`);
  });

  it("an ABSENT identity file makes the same commit fail with 'Author identity unknown' (dev/CI behaviour pinned; the Dockerfile asserts the file at build time)", () => {
    const ws = workspace(false);
    const r = runHost(ws, ["commit", "-q", "-m", "x"], { globalConfig: join(root, "does-not-exist.gitconfig") });
    expect(r.status).not.toBe(0);
    expect(r.stderr).toMatch(/Author identity unknown|unable to auto-detect email address/);
  });

  it("a seeded LOCAL identity still wins over the image identity file", () => {
    const ws = workspace(true);
    const r = runHost(ws, ["commit", "-q", "-m", "x"], { globalConfig: identityFile() });
    expect(r.status, r.stderr).toBe(0);
    expect(runHost(ws, ["log", "-1", "--format=%an"]).stdout.trim()).toBe("Seeded Local");
  });

  it("a repo-config protocol.ext.allow=always does not let an ext:: URL run a command (control: raw git does)", () => {
    const ws = workspace(true);
    const marker = join(root, "ext-marker");
    execFileSync("git", ["config", "protocol.ext.allow", "always"], { cwd: ws, env: plainEnv() });
    const url = `ext::touch ${marker}`;
    // control: raw git honours the repo config and runs the command, so the absence below is meaningful
    spawnSync("git", ["ls-remote", url], { cwd: ws, env: plainEnv(), encoding: "utf8", timeout: 20_000 });
    expect(existsSync(marker)).toBe(true);
    rmSync(marker);
    runHost(ws, ["ls-remote", url]);
    expect(existsSync(marker)).toBe(false);
  });

  it("GIT_WORK_TREE=<cwd> keeps a repo-config core.worktree from pointing the consumer at another directory (control: raw git follows it)", () => {
    const ws = workspace(true);
    const foreign = join(root, "foreign");
    mkdirSync(join(foreign, "knowledge-base"), { recursive: true });
    writeFileSync(join(foreign, "knowledge-base", "n.md"), "foreign\n");
    execFileSync("git", ["config", "core.worktree", foreign], { cwd: ws, env: plainEnv() });
    const raw = spawnSync("git", ["status", "--porcelain", "--untracked-files=all"], { cwd: ws, env: plainEnv(), encoding: "utf8" });
    expect(raw.stdout).toContain("n.md");
    const hosted = runHost(ws, ["status", "--porcelain", "--untracked-files=all"]);
    expect(hosted.stdout).not.toContain("n.md");
  });

  it("a committed bare repository as cwd is refused (safe.bareRepository=explicit): no consumer legitimately runs in one", () => {
    const bare = join(root, "bare.git");
    execFileSync("git", ["init", "-q", "--bare", bare], { env: plainEnv() });
    const r = runHost(bare, ["rev-parse", "--git-dir"], { cwd: undefined });
    expect(r.status).not.toBe(0);
    expect(r.stderr).toMatch(/cannot use bare repository/);
  });
});
