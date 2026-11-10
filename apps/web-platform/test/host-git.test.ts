// Helper rows for server/host-git.ts (Ref #9601). The per-consumer carrier battery lives in
// host-git-consumers-real-git.test.ts; these rows pin the helper's own contract with real git where git decides.
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { execFileSync, spawnSync } from "node:child_process";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { GIT_HARDENING_ARGS, GIT_HARDENING_ENV } from "../server/inngest/functions/_git-hardening";
import { AGENT_GIT_GLOBAL_CONFIG, ALLOW_PROTOCOL_NONE, buildScrubbedEnv, HostGitRefusedError, hostGitInvocation } from "../server/host-git";
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
function runHost(cwd: string, args: string[], opts: Partial<Parameters<typeof hostGitInvocation>[1]> = {}): { status: number | null; stdout: string; stderr: string } {
  const h = hostGitInvocation(args, { cwd, allowProtocol: "none", ...opts });
  const r = spawnSync("git", h.args, { cwd, env: h.env, encoding: "utf8" });
  return { status: r.status, stdout: r.stdout, stderr: r.stderr };
}

describe("hostGitInvocation: argv", () => {
  it("is the shared hardening block, then the helper-only extras, then the caller's args, in that order", () => {
    const { args } = hostGitInvocation(["status", "--porcelain"], { allowProtocol: "none" });
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
      "-c",
      "core.alternateRefsCommand=",
    ]);
  });

  it("uses only -c pairs and a leading --no-replace-objects: no other global option (an unknown one exits 129 on git 2.38/2.39)", () => {
    const { args } = hostGitInvocation(["status"], { allowProtocol: "none" });
    const block = args.slice(0, -1);
    const options = block.filter((a, i) => a.startsWith("-") && block[i - 1] !== "-c");
    expect(options.sort()).toEqual(["--no-replace-objects", "-c", "-c", "-c", "-c", "-c", "-c", "-c", "-c"].sort());
  });

  it("a caller's credential-helper reset rides inside args, after the block", () => {
    const { args } = hostGitInvocation(["-c", "credential.helper=", "pull"], { allowProtocol: "https" });
    const i = args.indexOf("credential.helper=");
    expect(args.indexOf("safe.bareRepository=explicit")).toBeLessThan(i);
    expect(args.slice(i + 1)).toEqual(["pull"]);
  });
});

describe("hostGitInvocation: environment", () => {
  it("carries the shared hardening env, with the global config pointed at the IMAGE identity file (never /dev/null)", () => {
    const { env } = hostGitInvocation(["status"], { allowProtocol: "none" });
    expect(env.GIT_CONFIG_GLOBAL).toBe(AGENT_GIT_GLOBAL_CONFIG);
    expect(env.GIT_CONFIG_GLOBAL).not.toBe(GIT_HARDENING_ENV.GIT_CONFIG_GLOBAL);
    expect(env.GIT_CONFIG_SYSTEM).toBe("/dev/null");
    expect(env.GIT_CONFIG_NOSYSTEM).toBe("1");
    expect(env.GIT_NO_REPLACE_OBJECTS).toBe("1");
    expect(env.GIT_TERMINAL_PROMPT).toBe("0");
  });

  it("scrubs the server environment: a server-only variable is absent from the child's environment; GIT_DIR and GIT_EXEC_PATH are dropped", () => {
    // A developer or CI shell may set TLS / proxy keys; they are forwarded only when set (next row), so clear them here.
    for (const k of ["SSL_CERT_FILE", "SSL_CERT_DIR", "GIT_SSL_CAINFO", "HTTPS_PROXY", "https_proxy", "NO_PROXY", "no_proxy"]) delete process.env[k];
    process.env.SERVER_ONLY_SENTINEL = "must-not-leak";
    process.env.GIT_DIR = "/somewhere/else";
    process.env.GIT_EXEC_PATH = "/somewhere/exec";
    const { env } = hostGitInvocation(["status"], { allowProtocol: "none" });
    expect(JSON.stringify(env)).not.toContain("must-not-leak");
    expect(env.GIT_DIR).toBeUndefined();
    expect(env.GIT_EXEC_PATH).toBeUndefined();
    const allowed = new Set(["PATH", "LANG", "LC_ALL", "TMPDIR", "HOME", ...Object.keys(GIT_HARDENING_ENV), "GIT_TERMINAL_PROMPT", "GIT_ALLOW_PROTOCOL"]);
    for (const k of Object.keys(env)) expect(allowed.has(k), `unexpected variable ${k}`).toBe(true);
  });

  it("forwards the TLS / proxy keys ONLY when they are set in the server environment", () => {
    for (const k of ["SSL_CERT_FILE", "SSL_CERT_DIR", "GIT_SSL_CAINFO", "HTTPS_PROXY", "https_proxy", "NO_PROXY", "no_proxy"]) delete process.env[k];
    const unset = hostGitInvocation(["status"], { allowProtocol: "https" }).env;
    for (const k of ["SSL_CERT_FILE", "SSL_CERT_DIR", "GIT_SSL_CAINFO", "HTTPS_PROXY", "https_proxy", "NO_PROXY", "no_proxy"]) expect(unset[k]).toBeUndefined();
    process.env.SSL_CERT_FILE = "/etc/ssl/certs/ca.pem";
    process.env.HTTPS_PROXY = "http://proxy.invalid:3128";
    // not on a local-only or ssh call
    for (const arm of ["none", "ssh"]) {
      const other = hostGitInvocation(["status"], { allowProtocol: arm }).env;
      expect(other.SSL_CERT_FILE, arm).toBeUndefined();
      expect(other.HTTPS_PROXY, arm).toBeUndefined();
    }
    const set = hostGitInvocation(["status"], { allowProtocol: "https" }).env;
    expect(set.SSL_CERT_FILE).toBe("/etc/ssl/certs/ca.pem");
    expect(set.HTTPS_PROXY).toBe("http://proxy.invalid:3128");
    expect(set.SSL_CERT_DIR).toBeUndefined();
  });

  it("sets GIT_WORK_TREE only with a cwd and GIT_ALLOW_PROTOCOL only with allowProtocol", () => {
    const bare = hostGitInvocation(["clone", "u", "d"], { allowProtocol: "https" }).env;
    expect(bare.GIT_WORK_TREE).toBeUndefined();
    expect(bare.GIT_DIR).toBeUndefined();
    expect(bare.GIT_COMMON_DIR).toBeUndefined();
    expect(bare.GIT_ALLOW_PROTOCOL).toBe("https");
    const withBoth = hostGitInvocation(["pull"], { cwd: "/ws/a", allowProtocol: "https" }).env;
    expect(withBoth.GIT_WORK_TREE).toBe("/ws/a");
    expect(withBoth.GIT_DIR).toBe("/ws/a/.git");
    expect(withBoth.GIT_COMMON_DIR).toBe("/ws/a/.git");
    expect(withBoth.GIT_ALLOW_PROTOCOL).toBe("https");
  });

  it("allowProtocol is carried on every call: none for a local-only consumer, never absent", () => {
    expect(hostGitInvocation(["status"], { allowProtocol: ALLOW_PROTOCOL_NONE }).env.GIT_ALLOW_PROTOCOL).toBe("none");
    expect(ALLOW_PROTOCOL_NONE).toBe("none");
  });

  it("a cwd must be absolute and non-empty, and a call with a cwd may not be clone or init", () => {
    for (const bad of ["", "relative/ws", "."]) {
      expect(() => hostGitInvocation(["status"], { cwd: bad, allowProtocol: "none" }), bad).toThrow(HostGitRefusedError);
    }
    for (const args of [["clone", "u", "d"], ["init"], ["-C", "/x", "-c", "a=b", "clone", "u"]]) {
      expect(() => hostGitInvocation(args, { cwd: "/ws/a", allowProtocol: "https" }), args.join(" ")).toThrow(HostGitRefusedError);
    }
    expect(() => hostGitInvocation(["init"], { allowProtocol: "none" })).not.toThrow();
  });

  it("a global option other than -C/-c and the allowed flags is refused, so a --git-dir behind a value-taking global cannot hide (a subcommand's own --git-dir is fine)", () => {
    expect(() => hostGitInvocation(["-C", "/ws/a", "-c", "credential.helper=", "--no-replace-objects", "rev-parse", "--git-dir"], { cwd: "/ws/a", allowProtocol: "none" })).not.toThrow();
  });

  it("an argv --git-dir / --work-tree / --namespace outranks the pinned env and is refused", () => {
    for (const bad of [["--git-dir=/x", "status"], ["--git-dir", "/x", "status"], ["--work-tree=/x", "status"], ["--namespace=n", "status"], ["--attr-source", "HEAD", "--git-dir=/x", "rev-parse", "--git-dir"], ["--config-env", "a=B", "--git-dir=/x", "status"]]) {
      expect(() => hostGitInvocation(bad, { cwd: "/ws/a", allowProtocol: "none" }), bad.join(" ")).toThrow(HostGitRefusedError);
    }
  });

  it("a refusal never carries a path in its message", () => {
    try {
      hostGitInvocation(["status"], { cwd: "relative/secret-ws-id", allowProtocol: "none" });
      throw new Error("expected a refusal");
    } catch (err) {
      expect(err).toBeInstanceOf(HostGitRefusedError);
      expect((err as Error).message).not.toContain("secret-ws-id");
    }
  });

  it("extraEnv accepts only the call-sites' own names: a protected or unknown name throws", () => {
    for (const bad of ["GIT_DIR", "GIT_WORK_TREE", "GIT_CONFIG_GLOBAL", "GIT_CONFIG_NOSYSTEM", "GIT_ALLOW_PROTOCOL", "GIT_NO_REPLACE_OBJECTS", "GIT_EXEC_PATH", "SOME_SECRET", "HTTPS_PROXY"]) {
      expect(() => hostGitInvocation(["status"], { allowProtocol: "none", extraEnv: { [bad]: "x" } }), bad).toThrow(HostGitRefusedError);
    }
    expect(() => hostGitInvocation(["status"], { allowProtocol: "none", extraEnv: { GIT_AUTHOR_NAME: "n", GIT_INDEX_FILE: "/tmp/i" } })).not.toThrow();
  });

  it("extraEnv is merged AFTER the scrub and wins (the call-site's own auth variables)", () => {
    const { env } = hostGitInvocation(["push"], {
      allowProtocol: "https",
      extraEnv: { GIT_ASKPASS: "/p/askpass.sh", GIT_INSTALLATION_TOKEN: "t0ken", GIT_TERMINAL_PROMPT: "1" },
    });
    expect(env.GIT_ASKPASS).toBe("/p/askpass.sh");
    expect(env.GIT_INSTALLATION_TOKEN).toBe("t0ken");
    expect(env.GIT_TERMINAL_PROMPT).toBe("1");
  });

  it("drops empty and non-absolute PATH entries (an empty entry is the current directory: the workspace)", () => {
    process.env.PATH = "/usr/bin::relative/bin:/bin:.";
    expect(hostGitInvocation(["status"], { allowProtocol: "none" }).env.PATH).toBe("/usr/bin:/bin");
    process.env.PATH = "::.";
    expect(hostGitInvocation(["status"], { allowProtocol: "none" }).env.PATH).toBe("/usr/bin:/bin");
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

  it("layering: the leaf imports only node:fs, node:os, node:path and the hardening constants", () => {
    const src = readFileSync(join(__dirname, "..", "server", "host-git.ts"), "utf8");
    const imports = [...src.matchAll(/^import .* from "([^"]+)";$/gm)].map((m) => m[1]);
    expect(imports.sort()).toEqual(["./inngest/functions/_git-hardening", "node:fs", "node:os", "node:path"]);
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

  it("a .git that carries commondir, is a symlink or gitfile, has a symlinked refs/objects entry, or carries alternates/grafts is refused before git runs (the real-git effect controls are in the battery)", () => {
    const victim = join(root, "victim");
    mkdirSync(victim);
    execFileSync("git", ["init", "-q", "-b", "main"], { cwd: victim, env: plainEnv() });
    const cases: Array<[string, (ws: string) => void]> = [
      ["commondir", (ws) => writeFileSync(join(ws, ".git", "commondir"), `${join(victim, ".git")}\n`)],
      [
        "symlink",
        (ws) => {
          rmSync(join(ws, ".git"), { recursive: true, force: true });
          symlinkSync(join(victim, ".git"), join(ws, ".git"));
        },
      ],
      [
        "gitfile",
        (ws) => {
          rmSync(join(ws, ".git"), { recursive: true, force: true });
          writeFileSync(join(ws, ".git"), `gitdir: ${join(victim, ".git")}\n`);
        },
      ],
    ];
    const vg = join(victim, ".git");
    const redirects: Array<[string, (ws: string) => void]> = [
      ["refs-symlink", (ws) => { rmSync(join(ws, ".git", "refs"), { recursive: true, force: true }); symlinkSync(join(vg, "refs"), join(ws, ".git", "refs")); }],
      ["objects-symlink", (ws) => { rmSync(join(ws, ".git", "objects"), { recursive: true, force: true }); symlinkSync(join(vg, "objects"), join(ws, ".git", "objects")); }],
      ["refs-heads-symlink", (ws) => { rmSync(join(ws, ".git", "refs", "heads"), { recursive: true, force: true }); symlinkSync(join(vg, "refs", "heads"), join(ws, ".git", "refs", "heads")); }],
      ["alternates", (ws) => { mkdirSync(join(ws, ".git", "objects", "info"), { recursive: true }); writeFileSync(join(ws, ".git", "objects", "info", "alternates"), `${join(vg, "objects")}\n`); }],
      ["http-alternates", (ws) => { mkdirSync(join(ws, ".git", "objects", "info"), { recursive: true }); writeFileSync(join(ws, ".git", "objects", "info", "http-alternates"), "http://x.invalid/objects\n"); }],
      ["refs-depth2-symlink", (ws) => { mkdirSync(join(ws, ".git", "refs", "heads"), { recursive: true }); symlinkSync(join(vg, "refs", "heads"), join(ws, ".git", "refs", "heads", "foo")); }],
      ["logs-head-symlink", (ws) => { mkdirSync(join(ws, ".git", "logs"), { recursive: true }); symlinkSync(join(vg, "config"), join(ws, ".git", "logs", "HEAD")); }],
      ["logs-refs-symlink", (ws) => { mkdirSync(join(ws, ".git", "logs"), { recursive: true }); symlinkSync(join(vg, "refs"), join(ws, ".git", "logs", "refs")); }],
      ["grafts", (ws) => { mkdirSync(join(ws, ".git", "info"), { recursive: true }); writeFileSync(join(ws, ".git", "info", "grafts"), "\n"); }],
    ];
    for (const [name, plant] of redirects) {
      const ws = join(root, `ws-${name}`);
      mkdirSync(ws);
      execFileSync("git", ["init", "-q", "-b", "main"], { cwd: ws, env: plainEnv() });
      plant(ws);
      expect(() => hostGitInvocation(["status"], { cwd: ws, allowProtocol: "none" }), name).toThrow(HostGitRefusedError);
    }
    // a plain workspace with the same entries as real directories and no redirecting file passes (positive control)
    const clean = join(root, "ws-clean-entries");
    mkdirSync(clean);
    execFileSync("git", ["init", "-q", "-b", "main"], { cwd: clean, env: plainEnv() });
    expect(() => hostGitInvocation(["status"], { cwd: clean, allowProtocol: "none" })).not.toThrow();
    for (const [name, plant] of cases) {
      const ws = join(root, `ws-${name}`);
      mkdirSync(ws);
      execFileSync("git", ["init", "-q", "-b", "main"], { cwd: ws, env: plainEnv() });
      plant(ws);
      writeFileSync(join(ws, "x.txt"), `${name}\n`);
      // control: raw git resolves the redirect into the victim repository (a blob lands in its store, or git
      // reports the victim's state), so the refusal below is meaningful
      const raw = spawnSync("git", ["add", "--", "x.txt"], { cwd: ws, env: plainEnv(), encoding: "utf8" });
      expect(raw.status === 0 || /unable to|fatal/i.test(raw.stderr), name).toBe(true);
      expect(() => hostGitInvocation(["add", "--", "x.txt"], { cwd: ws, allowProtocol: "none" }), name).toThrow(HostGitRefusedError);
    }
  });

  it("a plain workspace passes the shape guard and git runs against its OWN directory (GIT_DIR and GIT_COMMON_DIR pinned)", () => {
    const ws = workspace(true);
    const r = runHost(ws, ["rev-parse", "--git-dir", "--git-common-dir"]);
    expect(r.status, r.stderr).toBe(0);
    expect(r.stdout.trim().split("\n")).toEqual([join(ws, ".git"), join(ws, ".git")]);
  });

  it("an absent .git is not refused by the guard; git fails closed on the missing GIT_DIR", () => {
    const ws = join(root, "no-git");
    mkdirSync(ws);
    const r = runHost(ws, ["rev-parse", "--git-dir"]);
    expect(r.status).not.toBe(0);
  });

  it("core.alternateRefsCommand= keeps an alternates helper from running on fetch (control: raw git runs it); defence in depth behind the alternates refusal", () => {
    // mechanism as measured: an empty workspace whose alternates name a populated object store, fetching from it. The shape
    // check now refuses such a workspace outright, so this row drives the argv and env WITHOUT a cwd (no shape check, no pin).
    const origin = join(root, "origin");
    mkdirSync(origin);
    const ident = { ...plainEnv(), GIT_AUTHOR_NAME: "n", GIT_AUTHOR_EMAIL: "n@example.invalid", GIT_COMMITTER_NAME: "n", GIT_COMMITTER_EMAIL: "n@example.invalid" };
    execFileSync("git", ["init", "-q", "-b", "main"], { cwd: origin, env: plainEnv() });
    writeFileSync(join(origin, "a.txt"), "a\n");
    execFileSync("git", ["add", "--", "a.txt"], { cwd: origin, env: plainEnv() });
    execFileSync("git", ["commit", "-q", "-m", "1"], { cwd: origin, env: ident });
    const marker = join(root, "alt-marker");
    const helper = join(root, "alt.sh");
    writeFileSync(helper, `#!/bin/sh\n: > '${marker}'\n`, { mode: 0o755 });
    const ws = join(root, "alt-ws");
    mkdirSync(ws);
    execFileSync("git", ["init", "-q", "-b", "main"], { cwd: ws, env: plainEnv() });
    mkdirSync(join(ws, ".git", "objects", "info"), { recursive: true });
    writeFileSync(join(ws, ".git", "objects", "info", "alternates"), `${join(origin, ".git", "objects")}\n`);
    execFileSync("git", ["config", "core.alternateRefsCommand", helper], { cwd: ws, env: plainEnv() });
    execFileSync("git", ["remote", "add", "o", origin], { cwd: ws, env: plainEnv() });
    spawnSync("git", ["fetch", "-q", "o"], { cwd: ws, env: { ...plainEnv(), GIT_ALLOW_PROTOCOL: "file" }, encoding: "utf8", timeout: 20_000 });
    expect(existsSync(marker), "control: raw git runs the alternates helper").toBe(true);
    rmSync(marker);
    const h = hostGitInvocation(["fetch", "-q", "o"], { allowProtocol: "none:file" });
    spawnSync("git", h.args, { cwd: ws, env: h.env, encoding: "utf8", timeout: 20_000 });
    expect(existsSync(marker)).toBe(false);
  });

  it("a promisor remote's uploadpack program does not run on a local verb under allowProtocol none (control: raw git runs it)", () => {
    const ws = workspace(true);
    execFileSync("git", ["commit", "-q", "-m", "base", "--author=a <a@example.invalid>"], { cwd: ws, env: { ...plainEnv(), GIT_COMMITTER_NAME: "a", GIT_COMMITTER_EMAIL: "a@example.invalid" } });
    const src = join(root, "promisor-src");
    mkdirSync(src);
    execFileSync("git", ["init", "-q", "--bare", src], { env: plainEnv() });
    const marker = join(root, "promisor-marker");
    const prog = join(root, "up.sh");
    writeFileSync(prog, `#!/bin/sh\n: > '${marker}'\nexit 1\n`, { mode: 0o755 });
    const cfg = (k: string, v: string) => execFileSync("git", ["config", k, v], { cwd: ws, env: plainEnv() });
    cfg("extensions.partialClone", "o");
    cfg("remote.o.promisor", "true");
    cfg("remote.o.url", src);
    cfg("remote.o.uploadpack", prog);
    // drop the only blob so a checkout must lazily fetch it
    const blob = execFileSync("git", ["rev-parse", "HEAD:f.txt"], { cwd: ws, env: plainEnv(), encoding: "utf8" }).trim();
    rmSync(join(ws, ".git", "objects", blob.slice(0, 2), blob.slice(2)), { force: true });
    rmSync(join(ws, "f.txt"), { force: true });
    spawnSync("git", ["checkout-index", "-a", "-f"], { cwd: ws, env: { ...plainEnv(), GIT_ALLOW_PROTOCOL: "file" }, encoding: "utf8", timeout: 20_000 });
    spawnSync("git", ["reset", "--hard"], { cwd: ws, env: { ...plainEnv(), GIT_ALLOW_PROTOCOL: "file" }, encoding: "utf8", timeout: 20_000 });
    expect(existsSync(marker), "control: raw git runs the promisor program").toBe(true);
    rmSync(marker);
    runHost(ws, ["checkout-index", "-a", "-f"]);
    runHost(ws, ["reset", "--hard"]);
    expect(existsSync(marker)).toBe(false);
  });

  it("a committed bare repository as cwd is refused (safe.bareRepository=explicit): no consumer legitimately runs in one", () => {
    const bare = join(root, "bare.git");
    execFileSync("git", ["init", "-q", "--bare", bare], { env: plainEnv() });
    const r = runHost(bare, ["rev-parse", "--git-dir"], { cwd: undefined });
    expect(r.status).not.toBe(0);
    expect(r.stderr).toMatch(/cannot use bare repository/);
  });
});
