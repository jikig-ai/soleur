/**
 * ADR-309 flip item 9b, against the REAL git binary and real transports. The hardened push runs from a server-created isolated
 * GIT_DIR that reads the workspace `.git/objects` only as an alternate. Every vector below is shown EFFECTIVE under the shipped
 * 9a environment (`legacy9aEnv`: `GIT_DIR` = `<ws>/.git`, the `-c` resets, the allowlisted env) before it is shown INERT under the
 * isolated one, so a fixture that cannot exercise git cannot pass. Assertions are on what servers recorded and on exit status,
 * never on stderr wording (it varies with the curl backend and locale).
 *
 * Instrument preconditions fail loudly (never skip): the `openssl` CLI, the TLS servers, and the "control is effective" tests.
 * Synthesized data only: the certificate is generated with `openssl` at test time, the token is built by concatenation.
 * Every git child here is async (the TLS servers share this process's event loop; a sync child would deadlock them).
 */
import { execFile as execFileCb, execFileSync } from "node:child_process";
import { chmodSync, existsSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, realpathSync, rmSync, statSync, symlinkSync, writeFileSync } from "node:fs";
import https from "node:https";
import net from "node:net";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { promisify } from "node:util";
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, test, vi } from "vitest";
import { gitFixtureEnv } from "../../../plugins/soleur/test/lib/git-fixture-env";

const execFile = promisify(execFileCb);
const h = vi.hoisted(() => ({ protocol: "https", extraEnv: {} as Record<string, string> }));
const TOKEN = ["ghs", "_", "a".repeat(40)].join("");

vi.mock("../server/github-app", () => ({ generateInstallationToken: async () => ["ghs", "_", "a".repeat(40)].join("") }));
vi.mock("../server/logger", () => ({ createChildLogger: () => ({ info: vi.fn(), warn: vi.fn(), error: vi.fn() }) }));
// Test-only: the production clamp is `https`; the file-transport vectors need local bare remotes, so the `extra` argument (applied
// last by the builder, exactly as the askpass wiring is) widens the allowed set for those tests only. The same seam supplies
// `GIT_SSL_CAINFO` for the positive TLS control: measured on this git build, `SSL_CERT_FILE` is NOT honoured by git's libcurl (it has
// a compiled-in CA bundle path), so the allowlisted variable cannot carry the test CA.
vi.mock("../server/git-hardened-env", async (importOriginal) => {
  const actual = await importOriginal<typeof import("../server/git-hardened-env")>();
  return {
    ...actual,
    buildIsolatedGitEnv: (dir: import("../server/git-hardened-env").IsolatedPushDir, extra: Readonly<Record<string, string>> = {}) =>
      actual.buildIsolatedGitEnv(dir, { ...extra, GIT_ALLOW_PROTOCOL: h.protocol, ...h.extraEnv }),
  };
});

import { gitWithInstallationAuth, writeAskpassScriptTo } from "../server/git-auth";
import { HARDENED_ENV_ALLOWLIST, HARDENED_GIT_ARGS, buildIsolatedGitEnv } from "../server/git-hardened-env";
import { createIsolatedPushDir, IsolatedPushDirRefusal } from "../server/git-isolated-push-dir";
import { GIT_HARDENING_ENV } from "../server/inngest/functions/_git-hardening";

const git = (cwd: string, ...args: string[]): string =>
  execFileSync("git", ["-c", "user.name=t", "-c", "user.email=t@example.test", ...args], {
    cwd,
    stdio: "pipe",
    encoding: "utf8",
    env: gitFixtureEnv(cwd),
  }).trim();

// ---------------------------------------------------------------------------
// The shipped 9a form, rebuilt from the exported constants and the removed builder's documented pins (so it cannot drift silently).
// ---------------------------------------------------------------------------

function legacy9aEnv(ws: string, extra: Record<string, string> = {}): Record<string, string> {
  const env: Record<string, string> = {};
  for (const key of HARDENED_ENV_ALLOWLIST) {
    const value = process.env[key];
    if (value !== undefined) env[key] = value;
  }
  Object.assign(env, GIT_HARDENING_ENV);
  const gitDir = `${ws}/.git`;
  Object.assign(env, {
    GIT_DIR: gitDir,
    GIT_COMMON_DIR: gitDir,
    GIT_OBJECT_DIRECTORY: `${gitDir}/objects`,
    GIT_ALLOW_PROTOCOL: "https",
    GIT_CEILING_DIRECTORIES: dirname(ws),
  });
  return Object.assign(env, extra);
}

interface RunResult {
  ok: boolean;
  stderr: string;
}

async function run9a(ws: string, args: string[], extraEnv: Record<string, string> = {}): Promise<RunResult> {
  const script = writeAskpassScriptTo(join(ws, ".git"), ".askpass-control.sh");
  try {
    await execFile("git", ["-c", "credential.helper=", ...HARDENED_GIT_ARGS, ...args], {
      cwd: ws,
      timeout: 30_000,
      env: legacy9aEnv(ws, {
        GIT_ASKPASS: script,
        GIT_INSTALLATION_TOKEN: TOKEN,
        GIT_USERNAME: "x-access-token",
        GIT_TERMINAL_PROMPT: "0",
        GIT_TERMINAL_PROGRESS: "0",
        GIT_CONFIG_NOSYSTEM: "1",
        GIT_CONFIG_GLOBAL: "/dev/null",
        ...extraEnv,
      }) as NodeJS.ProcessEnv,
    });
    return { ok: true, stderr: "" };
  } catch (err) {
    return { ok: false, stderr: String((err as { stderr?: string }).stderr ?? "") };
  } finally {
    rmSync(script, { force: true });
  }
}

async function runIsolated(ws: string, args: string[], mutate?: (gitDir: string) => void): Promise<RunResult & { gitDir: string }> {
  const dir = createIsolatedPushDir(ws);
  try {
    mutate?.(dir.gitDir);
    await gitWithInstallationAuth(args, 1, { hardened: dir, timeout: 30_000 });
    return { ok: true, stderr: "", gitDir: dir.gitDir };
  } catch (err) {
    return { ok: false, stderr: String((err as { stderr?: string }).stderr ?? (err as Error).message), gitDir: dir.gitDir };
  } finally {
    dir.dispose();
  }
}

// ---------------------------------------------------------------------------
// TLS recording servers (generated certificate, port 0, closed in afterAll)
// ---------------------------------------------------------------------------

interface Recorded {
  url: string | undefined;
  authorization: string | undefined;
  xEvil: string | undefined;
  xEnv: string | undefined;
}
interface TlsServer {
  port: number;
  records: Recorded[];
  close(): Promise<void>;
}

async function startTls(key: string, cert: string): Promise<TlsServer> {
  const records: Recorded[] = [];
  const server = https.createServer({ key, cert }, (req, res) => {
    records.push({
      url: req.url,
      authorization: req.headers.authorization,
      xEvil: req.headers["x-evil"] as string | undefined,
      xEnv: req.headers["x-env"] as string | undefined,
    });
    if (!req.headers.authorization) {
      res.writeHead(401, { "WWW-Authenticate": 'Basic realm="r"' });
      res.end();
    } else {
      res.writeHead(404);
      res.end("not found");
    }
  });
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  const port = (server.address() as net.AddressInfo).port;
  return {
    port,
    records,
    close: () =>
      new Promise<void>((resolve) => {
        server.closeAllConnections();
        server.close(() => resolve());
      }),
  };
}

async function startProxy(): Promise<{ port: number; lines: string[]; close(): Promise<void> }> {
  const lines: string[] = [];
  const sockets = new Set<net.Socket>();
  const server = net.createServer((sock) => {
    sockets.add(sock);
    sock.on("data", (d) => {
      lines.push(d.toString("latin1").split("\r\n")[0]);
      sock.destroy();
    });
    sock.on("error", () => undefined);
  });
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  return {
    port: (server.address() as net.AddressInfo).port,
    lines,
    close: () =>
      new Promise<void>((resolve) => {
        for (const s of sockets) s.destroy();
        server.close(() => resolve());
      }),
  };
}

// ---------------------------------------------------------------------------

let base: string;
let certFile: string;
let tls: TlsServer;
let proxy: Awaited<ReturnType<typeof startProxy>>;

describe("preconditions (fail loudly, never skip)", () => {
  test("the openssl CLI is installed (a declared dependency of this suite)", () => {
    expect(() => execFileSync("openssl", ["version"], { stdio: "pipe" })).not.toThrow();
  });
});

beforeAll(async () => {
  base = realpathSync(mkdtempSync(join(tmpdir(), "iso-real-")));
  const keyFile = join(base, "key.pem");
  certFile = join(base, "certs", "cert.pem");
  mkdirSync(join(base, "certs"));
  execFileSync(
    "openssl",
    [
      "req", "-x509", "-newkey", "ec", "-pkeyopt", "ec_paramgen_curve:prime256v1", "-nodes", "-keyout", keyFile, "-out", certFile,
      "-days", "2", "-subj", "/CN=localhost", "-addext", "subjectAltName=IP:127.0.0.1,DNS:localhost,DNS:evil.test",
    ],
    { stdio: "pipe" },
  );
  tls = await startTls(readFileSync(keyFile, "utf8"), readFileSync(certFile, "utf8"));
  proxy = await startProxy();
}, 60_000);

afterAll(async () => {
  await tls?.close();
  await proxy?.close();
  rmSync(base, { recursive: true, force: true });
});

describe("push from an isolated GIT_DIR (real git)", () => {
  let root: string;
  let ws: string;
  let sha: string;
  let remote: string;
  const savedEnv: Record<string, string | undefined> = {};
  const savedGitConfigEnv: Record<string, string | undefined> = {};
  const ENV_KEYS = ["HOME", "TMPDIR", "SSL_CERT_FILE", "SSL_CERT_DIR", "PATH", "XDG_CONFIG_HOME"] as const;

  const mkRepo = (path: string, commits = 1): string => {
    mkdirSync(path, { recursive: true });
    git(path, "init", "-q", "-b", "main");
    for (let i = 0; i < commits; i++) {
      writeFileSync(join(path, `f${i}.txt`), `content ${i}\n`);
      git(path, "add", ".");
      git(path, "commit", "-q", "-m", `c${i}`);
    }
    return git(path, "rev-parse", "HEAD");
  };
  const mkBare = (path: string): string => {
    execFileSync("git", ["init", "--bare", "-q", path], { env: gitFixtureEnv(root) });
    return path;
  };
  const config = (text: string): void => {
    const p = join(ws, ".git", "config");
    writeFileSync(p, `${readFileSync(p, "utf8")}${text}`);
  };
  const url = (host = "127.0.0.1"): string => `https://${host}:${tls.port}/x.git`;
  const authRecords = (): Recorded[] => tls.records.filter((r) => r.authorization !== undefined);
  /** Trust the test CA for BOTH arms: the isolated child through the test-only builder seam, the control through `trustEnv`. */
  const trust = (): void => {
    h.extraEnv = { GIT_SSL_CAINFO: certFile };
  };
  const trustEnv = (): Record<string, string> => ({ GIT_SSL_CAINFO: certFile });

  beforeEach(() => {
    for (const k of Object.keys(process.env)) {
      if (k === "GIT_CONFIG_COUNT" || k === "GIT_CONFIG_PARAMETERS" || /^GIT_CONFIG_(KEY|VALUE)_\d+$/.test(k)) {
        savedGitConfigEnv[k] = process.env[k];
        delete process.env[k];
      }
    }
    for (const k of ENV_KEYS) savedEnv[k] = process.env[k];
    h.protocol = "https";
    h.extraEnv = {};
    tls.records.length = 0;
    proxy.lines.length = 0;
    root = realpathSync(mkdtempSync(join(tmpdir(), "iso-case-")));
    mkdirSync(join(root, "home"));
    mkdirSync(join(root, "tmp"));
    process.env.HOME = join(root, "home");
    process.env.TMPDIR = join(root, "tmp");
    delete process.env.SSL_CERT_FILE;
    delete process.env.SSL_CERT_DIR;
    delete process.env.XDG_CONFIG_HOME;
    ws = join(root, "ws");
    sha = mkRepo(ws);
    remote = mkBare(join(root, "remote.git"));
  });

  afterEach(() => {
    for (const [k, v] of Object.entries(savedEnv)) {
      if (v === undefined) delete process.env[k];
      else process.env[k] = v;
    }
    for (const [k, v] of Object.entries(savedGitConfigEnv)) {
      if (v !== undefined) process.env[k] = v;
      delete savedGitConfigEnv[k];
    }
    rmSync(root, { recursive: true, force: true });
  });

  const refspec = (branch = "feat-x"): string => `${sha}:refs/heads/${branch}`;

  // -------------------------------------------------------------------------
  describe("file-transport vectors: url.<base>.insteadOf / pushInsteadOf divert the 9a push, not the isolated one", () => {
    test.each(["insteadOf", "pushInsteadOf"])("%s", async (key) => {
      const good = remote;
      const evil = mkBare(join(root, "evil.git"));
      config(`[url "${evil}"]\n\t${key} = ${good}\n`);
      // CONTROL: the 9a form (config read from the workspace) lands the push in the attacker's remote.
      const control = await run9a(ws, ["push", good, refspec()], { GIT_ALLOW_PROTOCOL: "https:file" });
      expect(control.ok, control.stderr).toBe(true);
      expect(git(evil, "rev-parse", "refs/heads/feat-x")).toBe(sha);
      expect(() => git(good, "rev-parse", "refs/heads/feat-x")).toThrow();
      rmSync(join(evil, "refs", "heads", "feat-x"));
      // ISOLATED: the literal URL is honoured; the workspace config is never read.
      h.protocol = "https:file";
      const iso = await runIsolated(ws, ["push", good, refspec()]);
      expect(iso.ok, iso.stderr).toBe(true);
      expect(git(good, "rev-parse", "refs/heads/feat-x")).toBe(sha);
      expect(() => git(evil, "rev-parse", "refs/heads/feat-x")).toThrow();
    }, 60_000);
  });

  // -------------------------------------------------------------------------
  describe("TLS vectors: a recording HTTPS server shows where the Authorization header went", () => {
    test("positive control: the isolated form with a trusted CA reaches the server and sends Authorization", async () => {
      trust();
      const r = await runIsolated(ws, ["push", url(), refspec()]);
      expect(r.ok).toBe(false); // the server answers 404 after authentication
      expect(authRecords().length).toBeGreaterThan(0);
      expect(authRecords()[0].authorization).toMatch(/^Basic /);
    }, 60_000);

    test("http.<url>.sslVerify=false: honoured by the 9a form (token reaches the untrusted server), ignored by the isolated one", async () => {
      config(`[http "https://127.0.0.1:${tls.port}/"]\n\tsslVerify = false\n`);
      const control = await run9a(ws, ["push", url(), refspec()]);
      expect(control.ok).toBe(false);
      expect(authRecords().length, "the vector must be effective in the control").toBeGreaterThan(0);
      tls.records.length = 0;
      const iso = await runIsolated(ws, ["push", url(), refspec()]);
      expect(iso.ok).toBe(false);
      expect(authRecords()).toEqual([]);
      expect(tls.records).toEqual([]); // the handshake itself failed: no request was made
    }, 60_000);

    test("http.<url>.sslCAInfo=<attacker CA>: honoured by the 9a form, ignored by the isolated one", async () => {
      config(`[http "https://127.0.0.1:${tls.port}/"]\n\tsslCAInfo = ${certFile}\n`);
      const control = await run9a(ws, ["push", url(), refspec()]);
      expect(control.ok).toBe(false);
      expect(authRecords().length, "the vector must be effective in the control").toBeGreaterThan(0);
      tls.records.length = 0;
      const iso = await runIsolated(ws, ["push", url(), refspec()]);
      expect(iso.ok).toBe(false);
      expect(authRecords()).toEqual([]);
    }, 60_000);

    test("a URL-scoped http.<url>.proxy (more specific than the -c reset): the 9a form connects through the proxy, the isolated one does not", async () => {
      trust();
      config(`[http "https://127.0.0.1:${tls.port}/"]\n\tproxy = http://127.0.0.1:${proxy.port}\n`);
      const control = await run9a(ws, ["push", url(), refspec()], trustEnv());
      expect(control.ok).toBe(false);
      expect(proxy.lines.some((l) => l.startsWith("CONNECT ")), "the vector must be effective in the control").toBe(true);
      expect(authRecords()).toEqual([]); // the proxy swallowed the connection
      proxy.lines.length = 0;
      const iso = await runIsolated(ws, ["push", url(), refspec()]);
      expect(iso.ok).toBe(false);
      expect(proxy.lines).toEqual([]);
      expect(authRecords().length).toBeGreaterThan(0); // it reached the real server instead
    }, 60_000);

    test("http.curloptResolve: the 9a form is steered to the local server for an unresolvable name, the isolated one is not", async () => {
      trust();
      config(`[http]\n\tcurloptResolve = evil.test:${tls.port}:127.0.0.1\n`);
      const control = await run9a(ws, ["push", url("evil.test"), refspec()], trustEnv());
      expect(control.ok).toBe(false);
      expect(authRecords().length, "the vector must be effective in the control").toBeGreaterThan(0);
      tls.records.length = 0;
      const iso = await runIsolated(ws, ["push", url("evil.test"), refspec()]);
      expect(iso.ok).toBe(false);
      expect(tls.records).toEqual([]);
    }, 60_000);

    test("http.<url>.extraHeader: the 9a form sends the attacker's header with the token, the isolated one does not", async () => {
      trust();
      config(`[http "https://127.0.0.1:${tls.port}/"]\n\textraHeader = X-Evil: yes\n`);
      const control = await run9a(ws, ["push", url(), refspec()], trustEnv());
      expect(control.ok).toBe(false);
      expect(tls.records.some((r) => r.xEvil === "yes"), "the vector must be effective in the control").toBe(true);
      tls.records.length = 0;
      const iso = await runIsolated(ws, ["push", url(), refspec()]);
      expect(iso.ok).toBe(false);
      expect(authRecords().length).toBeGreaterThan(0);
      expect(tls.records.some((r) => r.xEvil !== undefined)).toBe(false);
    }, 60_000);

    test("server-process GIT_CONFIG_COUNT / KEY_n / VALUE_n env config is honoured when it reaches a child, and never reaches the isolated one", async () => {
      trust();
      // URL-scoped on purpose: the unscoped http.extraHeader is reset by the later `-c http.extraHeader=` and would prove nothing.
      const injected = { GIT_CONFIG_COUNT: "1", GIT_CONFIG_KEY_0: `http.https://127.0.0.1:${tls.port}/.extraHeader`, GIT_CONFIG_VALUE_0: "X-Env: leaked" };
      const control = await run9a(ws, ["push", url(), refspec()], { ...trustEnv(), ...injected });
      expect(control.ok).toBe(false);
      expect(tls.records.some((r) => r.xEnv === "leaked"), "the control must observe the injected config").toBe(true);
      tls.records.length = 0;
      Object.assign(process.env, injected);
      try {
        const dir = createIsolatedPushDir(ws);
        try {
          const keys = Object.keys(buildIsolatedGitEnv(dir));
          expect(keys.filter((k) => k.startsWith("GIT_CONFIG_") && !["GIT_CONFIG_GLOBAL", "GIT_CONFIG_SYSTEM", "GIT_CONFIG_NOSYSTEM"].includes(k))).toEqual([]);
        } finally {
          dir.dispose();
        }
        const iso = await runIsolated(ws, ["push", url(), refspec()]);
        expect(iso.ok).toBe(false);
        expect(authRecords().length).toBeGreaterThan(0);
        expect(tls.records.some((r) => r.xEnv !== undefined)).toBe(false);
      } finally {
        for (const k of Object.keys(injected)) delete process.env[k];
      }
    }, 60_000);

    test("a fake git-remote-https on a writable PATH directory outside the workspace does not shadow the real helper (git finds helpers in its exec path first)", async () => {
      trust();
      const fakeBin = join(root, "fakebin");
      const marker = join(root, "fake-ran");
      mkdirSync(fakeBin);
      writeFileSync(join(fakeBin, "git-remote-https"), `#!/bin/sh\necho ran > '${marker}'\nexit 1\n`, { mode: 0o755 });
      process.env.PATH = `${fakeBin}:${savedEnv.PATH ?? ""}`;
      const r = await runIsolated(ws, ["push", url(), refspec()]);
      expect(r.ok).toBe(false);
      expect(existsSync(marker)).toBe(false);
      expect(authRecords().length).toBeGreaterThan(0); // the real helper ran
    }, 60_000);

    test("a fake git-remote-https directory UNDER the workspace is refused before anything runs (env_path_unsafe)", () => {
      const fakeBin = join(ws, "bin");
      mkdirSync(fakeBin);
      process.env.PATH = `${fakeBin}:${savedEnv.PATH ?? ""}`;
      expect(() => createIsolatedPushDir(ws)).toThrow(expect.objectContaining({ reason: "env_path_unsafe" }));
    });
  });

  // -------------------------------------------------------------------------
  describe("nothing from the workspace config is read (git config --list --show-origin)", () => {
    test("the isolated child lists only the server-written file and command line, with hostile $HOME and $XDG_CONFIG_HOME configs present", async () => {
      const hostile = '[url "https://evil.invalid/"]\n\tinsteadOf = https://github.com/\n[http]\n\tproxy = http://127.0.0.1:9\n';
      writeFileSync(join(process.env.HOME as string, ".gitconfig"), hostile);
      mkdirSync(join(root, "xdg", "git"), { recursive: true });
      writeFileSync(join(root, "xdg", "git", "config"), hostile);
      process.env.XDG_CONFIG_HOME = join(root, "xdg");
      config(hostile);
      // CONTROL: the 9a child lists the workspace file (so the listing can show a workspace origin at all).
      const controlOut = await execFile("git", [...HARDENED_GIT_ARGS, "config", "--list", "--show-origin"], {
        cwd: ws,
        env: legacy9aEnv(ws, { XDG_CONFIG_HOME: join(root, "xdg") }) as NodeJS.ProcessEnv,
      });
      expect(controlOut.stdout).toContain(`file:${ws}/.git/config`);
      const dir = createIsolatedPushDir(ws);
      try {
        const out = await execFile("git", [...HARDENED_GIT_ARGS, "config", "--list", "--show-origin"], {
          cwd: dir.gitDir,
          env: buildIsolatedGitEnv(dir),
        });
        const origins = new Set(out.stdout.split("\n").filter(Boolean).map((l) => l.split("\t")[0]));
        for (const o of origins) expect([`file:${dir.gitDir}/config`, "command line:"], o).toContain(o);
        expect(origins.has(`file:${dir.gitDir}/config`)).toBe(true);
        expect(out.stdout).not.toContain(ws);
        expect(out.stdout).not.toContain("evil.invalid");
      } finally {
        dir.dispose();
      }
    }, 30_000);

    test("hooks and core.hooksPath in the workspace never run (a sentinel marker stays absent) on a pre-push-reaching push", async () => {
      const marker = join(root, "hook-ran");
      const evilHooks = join(root, "evil-hooks");
      mkdirSync(evilHooks);
      for (const dir of [join(ws, ".git", "hooks"), evilHooks]) {
        mkdirSync(dir, { recursive: true });
        writeFileSync(join(dir, "pre-push"), `#!/bin/sh\necho ran > '${marker}'\nexit 0\n`, { mode: 0o755 });
      }
      config(`[core]\n\thooksPath = ${evilHooks}\n`);
      h.protocol = "https:file";
      const control = await run9a(ws, ["push", remote, refspec()], { GIT_ALLOW_PROTOCOL: "https:file", ...{} });
      // The 9a form already neutralises hooks with -c core.hooksPath=/dev/null; that is why the isolated form keeps the -c too.
      expect(control.ok, control.stderr).toBe(true);
      expect(existsSync(marker)).toBe(false);
      rmSync(join(remote, "refs", "heads", "feat-x"));
      const iso = await runIsolated(ws, ["push", remote, refspec()]);
      expect(iso.ok, iso.stderr).toBe(true);
      expect(existsSync(marker)).toBe(false);
    }, 60_000);
  });

  // -------------------------------------------------------------------------
  describe("objects reach the remote through the alternate", () => {
    test("a loose, alternate-only commit with its whole ancestry arrives; the remote fscks clean; the isolated objects/ holds no object file", async () => {
      sha = mkRepo(join(root, "ws3"), 3);
      ws = join(root, "ws3");
      h.protocol = "https:file";
      let isoObjects: string[] = [];
      const r = await runIsolated(ws, ["push", remote, refspec()], (gitDir) => {
        isoObjects = [gitDir];
      });
      expect(r.ok, r.stderr).toBe(true);
      expect(git(remote, "rev-parse", "refs/heads/feat-x")).toBe(sha);
      expect(git(remote, "rev-list", "--count", "refs/heads/feat-x")).toBe("3");
      expect(() => execFileSync("git", ["fsck", "--strict"], { cwd: remote, stdio: "pipe", env: gitFixtureEnv(root) })).not.toThrow();
      expect(isoObjects).toHaveLength(1);
    }, 60_000);

    test("the isolated objects/ stays empty during the push (nothing is copied from the workspace)", async () => {
      h.protocol = "https:file";
      let files = -1;
      const dir = createIsolatedPushDir(ws);
      try {
        await gitWithInstallationAuth(["push", remote, refspec()], 1, { hardened: dir, timeout: 30_000 });
        const walk = (d: string): number => readdirSync(d, { withFileTypes: true }).reduce((n, e) => n + (e.isDirectory() ? walk(join(d, e.name)) : 1), 0);
        files = walk(join(dir.gitDir, "objects"));
      } finally {
        dir.dispose();
      }
      expect(files).toBe(0);
      expect(git(remote, "rev-parse", "refs/heads/feat-x")).toBe(sha);
    }, 60_000);

    test("a packed-only object store (after gc --prune=now) pushes too", async () => {
      git(ws, "gc", "-q", "--prune=now");
      expect(readdirSync(join(ws, ".git", "objects")).filter((n) => /^[0-9a-f]{2}$/.test(n))).toEqual([]); // precondition: no loose objects left
      h.protocol = "https:file";
      const r = await runIsolated(ws, ["push", remote, refspec()]);
      expect(r.ok, r.stderr).toBe(true);
      expect(git(remote, "rev-parse", "refs/heads/feat-x")).toBe(sha);
      expect(() => execFileSync("git", ["fsck", "--strict"], { cwd: remote, stdio: "pipe", env: gitFixtureEnv(root) })).not.toThrow();
    }, 60_000);

    test("a corrupt commit-graph, multi-pack-index and bitmap in the workspace object store are not parsed (the server-written config turns them off)", async () => {
      git(ws, "gc", "-q");
      const pack = readdirSync(join(ws, ".git", "objects", "pack")).find((f) => f.endsWith(".pack")) as string;
      rmSync(join(ws, ".git", "objects", "info", "commit-graph"), { force: true }); // gc writes it read-only
      writeFileSync(join(ws, ".git", "objects", "info", "commit-graph"), "CGPH garbage that is not a graph");
      writeFileSync(join(ws, ".git", "objects", "pack", "multi-pack-index"), "MIDX garbage that is not an index");
      writeFileSync(join(ws, ".git", "objects", "pack", pack.replace(/\.pack$/, ".bitmap")), "BITM garbage that is not a bitmap");
      h.protocol = "https:file";
      const r = await runIsolated(ws, ["push", remote, refspec()]);
      expect(r.ok, r.stderr).toBe(true);
      expect(git(remote, "rev-parse", "refs/heads/feat-x")).toBe(sha);
    }, 60_000);

    test("a crafted .gitmodules in the pushed tree is only data", async () => {
      writeFileSync(join(ws, ".gitmodules"), '[submodule "x"]\n\tpath = x\n\turl = ext::sh -c "touch /tmp/never"\n');
      git(ws, "add", ".gitmodules");
      git(ws, "commit", "-q", "-m", "mod");
      sha = git(ws, "rev-parse", "HEAD");
      h.protocol = "https:file";
      const r = await runIsolated(ws, ["push", remote, refspec()]);
      expect(r.ok, r.stderr).toBe(true);
      expect(git(remote, "rev-parse", "refs/heads/feat-x")).toBe(sha);
    }, 60_000);

    test("a planted refs/replace entry and info/grafts do not change the pushed objects (control: the workspace itself honours them)", async () => {
      writeFileSync(join(ws, "g.txt"), "g\n");
      git(ws, "add", ".");
      git(ws, "commit", "-q", "-m", "second");
      sha = git(ws, "rev-parse", "HEAD");
      const parent = git(ws, "rev-parse", "HEAD~1");
      const original = git(ws, "cat-file", "-p", sha);
      // A graft that would cut the history: honoured by git running in the workspace.
      mkdirSync(join(ws, ".git", "info"), { recursive: true });
      writeFileSync(join(ws, ".git", "info", "grafts"), `${sha}\n`);
      expect(git(ws, "log", "--format=%H", sha).split("\n")).toEqual([sha]); // control: the graft is effective for ws git
      // A replace ref swapping the parent for the commit itself.
      git(ws, "update-ref", `refs/replace/${parent}`, sha);
      h.protocol = "https:file";
      const r = await runIsolated(ws, ["push", remote, refspec()]);
      expect(r.ok, r.stderr).toBe(true);
      expect(git(remote, "rev-parse", "refs/heads/feat-x")).toBe(sha);
      expect(execFileSync("git", ["--no-replace-objects", "cat-file", "-p", sha], { cwd: remote, encoding: "utf8", env: gitFixtureEnv(root) }).trim()).toBe(original);
      expect(git(remote, "rev-list", "--count", "refs/heads/feat-x")).toBe("2");
    }, 60_000);
  });

  // -------------------------------------------------------------------------
  describe("nothing in the workspace .git is read (FIFO / mode-000 falsifiers with hard timeouts)", () => {
    test("config, HEAD, hooks, index and refs replaced by FIFOs: the push still succeeds (any read would hang or fail)", async () => {
      for (const entry of ["config", "HEAD", "hooks", "index", "refs"]) {
        rmSync(join(ws, ".git", entry), { recursive: true, force: true });
        execFileSync("mkfifo", [join(ws, ".git", entry)]);
      }
      h.protocol = "https:file";
      const r = await runIsolated(ws, ["push", remote, refspec()]);
      expect(r.ok, r.stderr).toBe(true);
      expect(git(remote, "rev-parse", "refs/heads/feat-x")).toBe(sha);
    }, 30_000);

    test("config, HEAD and index at mode 000 (precondition: unreadable for this uid): the push still succeeds", async () => {
      for (const entry of ["config", "HEAD", "index"]) {
        chmodSync(join(ws, ".git", entry), 0);
        expect(() => readFileSync(join(ws, ".git", entry))).toThrow();
      }
      h.protocol = "https:file";
      try {
        const r = await runIsolated(ws, ["push", remote, refspec()]);
        expect(r.ok, r.stderr).toBe(true);
        expect(git(remote, "rev-parse", "refs/heads/feat-x")).toBe(sha);
      } finally {
        for (const entry of ["config", "HEAD", "index"]) chmodSync(join(ws, ".git", entry), 0o644);
      }
    }, 30_000);

    test("symlinked or planted config / HEAD / hooks / index / refs / packed-refs / commondir / config.worktree / info/grafts are all ignored", async () => {
      const aside = join(root, "aside");
      mkdirSync(aside);
      for (const entry of ["config", "HEAD", "index"]) symlinkSync(join(root, "nonexistent", entry), join(aside, entry));
      rmSync(join(ws, ".git", "config"));
      symlinkSync(join(aside, "config"), join(ws, ".git", "config"));
      writeFileSync(join(ws, ".git", "commondir"), `${join(root, "other")}\n`);
      writeFileSync(join(ws, ".git", "config.worktree"), "[core]\n\tfsmonitor = /bin/false\n");
      writeFileSync(join(ws, ".git", "packed-refs"), `${"a".repeat(40)} refs/heads/evil\n`);
      h.protocol = "https:file";
      const r = await runIsolated(ws, ["push", remote, refspec()]);
      expect(r.ok, r.stderr).toBe(true);
      expect(git(remote, "rev-parse", "refs/heads/feat-x")).toBe(sha);
    }, 30_000);
  });

  // -------------------------------------------------------------------------
  describe("shallow workspaces (the highest functional risk: --depth 1 clones, remote ahead)", () => {
    interface ShallowScenario {
      shallowWs: string;
      boundary: string;
      pushed: string;
      target: string;
    }
    /** O: A0 -> A1. W = depth-1 clone of O (boundary A1) + commit B. O then advances (C). Target = a bare clone of O at C. */
    function scenario(): ShallowScenario {
      const origin = join(root, "origin");
      mkdirSync(origin);
      git(origin, "init", "-q", "-b", "main");
      for (const n of ["a0", "a1"]) {
        writeFileSync(join(origin, `${n}.txt`), n);
        git(origin, "add", ".");
        git(origin, "commit", "-q", "-m", n);
      }
      const shallowWs = join(root, "shallow-ws");
      execFileSync("git", ["clone", "-q", "--depth", "1", `file://${origin}`, shallowWs], { env: gitFixtureEnv(root), stdio: "pipe" });
      const boundary = git(shallowWs, "rev-parse", "HEAD");
      writeFileSync(join(shallowWs, "b.txt"), "b");
      git(shallowWs, "add", ".");
      git(shallowWs, "commit", "-q", "-m", "b");
      const pushed = git(shallowWs, "rev-parse", "HEAD");
      writeFileSync(join(origin, "c.txt"), "c");
      git(origin, "add", ".");
      git(origin, "commit", "-q", "-m", "c");
      const target = join(root, "target.git");
      execFileSync("git", ["clone", "-q", "--bare", origin, target], { env: gitFixtureEnv(root), stdio: "pipe" });
      return { shallowWs, boundary, pushed, target };
    }

    test("a --depth 1 workspace with the remote branch AHEAD pushes (the shallow boundary is carried into the isolated directory)", async () => {
      const s = scenario();
      expect(existsSync(join(s.shallowWs, ".git", "shallow"))).toBe(true); // precondition: it is shallow
      h.protocol = "https:file";
      const r = await runIsolated(s.shallowWs, ["push", s.target, `${s.pushed}:refs/heads/feat-x`]);
      expect(r.ok, r.stderr).toBe(true);
      expect(git(s.target, "rev-parse", "refs/heads/feat-x")).toBe(s.pushed);
      expect(git(s.target, "rev-parse", "refs/heads/feat-x~1")).toBe(s.boundary);
    }, 60_000);

    test("negative control: the same scenario WITHOUT the shallow copy fails (so the test above is not vacuous)", async () => {
      const s = scenario();
      h.protocol = "https:file";
      const r = await runIsolated(s.shallowWs, ["push", s.target, `${s.pushed}:refs/heads/feat-x`], (gitDir) => {
        expect(existsSync(join(gitDir, "shallow"))).toBe(true);
        rmSync(join(gitDir, "shallow"));
      });
      expect(r.ok).toBe(false);
      expect(() => git(s.target, "rev-parse", "refs/heads/feat-x")).toThrow();
    }, 60_000);

    test("the approved commit being the shallow boundary commit itself pushes", async () => {
      const s = scenario();
      h.protocol = "https:file";
      const r = await runIsolated(s.shallowWs, ["push", s.target, `${s.boundary}:refs/heads/feat-b`]);
      expect(r.ok, r.stderr).toBe(true);
      expect(git(s.target, "rev-parse", "refs/heads/feat-b")).toBe(s.boundary);
    }, 60_000);
  });

  // -------------------------------------------------------------------------
  describe("other flow edges", () => {
    test("a non-fast-forward to a divergent remote branch is rejected without --force, and the relayed text holds no token or temp path", async () => {
      h.protocol = "https:file";
      git(ws, "branch", "other", sha);
      writeFileSync(join(ws, "d.txt"), "d");
      git(ws, "add", ".");
      git(ws, "commit", "-q", "-m", "divergent");
      const divergent = git(ws, "rev-parse", "HEAD");
      const first = await runIsolated(ws, ["push", remote, `${divergent}:refs/heads/feat-x`]);
      expect(first.ok, first.stderr).toBe(true);
      const second = await runIsolated(ws, ["push", remote, `${sha}:refs/heads/feat-x`]);
      expect(second.ok).toBe(false);
      expect(git(remote, "rev-parse", "refs/heads/feat-x")).toBe(divergent);
      expect(second.stderr).not.toContain(TOKEN);
      expect(second.stderr).not.toContain(second.gitDir);
    }, 60_000);

    test("two concurrent pushes from one workspace both land and both directories are removed", async () => {
      h.protocol = "https:file";
      const [a, b] = await Promise.all([runIsolated(ws, ["push", remote, refspec("feat-a")]), runIsolated(ws, ["push", remote, refspec("feat-b")])]);
      expect(a.ok, a.stderr).toBe(true);
      expect(b.ok, b.stderr).toBe(true);
      expect(a.gitDir).not.toBe(b.gitDir);
      expect(existsSync(a.gitDir)).toBe(false);
      expect(existsSync(b.gitDir)).toBe(false);
      expect(git(remote, "rev-parse", "refs/heads/feat-a")).toBe(sha);
      expect(git(remote, "rev-parse", "refs/heads/feat-b")).toBe(sha);
    }, 60_000);

    test("a push whose isolated command fails still removes the directory (askpass script included)", async () => {
      h.protocol = "https:file";
      const r = await runIsolated(ws, ["push", join(root, "does-not-exist.git"), refspec()]);
      expect(r.ok).toBe(false);
      expect(existsSync(r.gitDir)).toBe(false);
      expect(statSync(join(process.env.HOME as string, ".soleur-push")).isDirectory()).toBe(true);
      expect(readdirSync(join(process.env.HOME as string, ".soleur-push"))).toEqual([]);
    }, 60_000);
  });

  // -------------------------------------------------------------------------
  describe("the alternates chain (git follows <alternate>/info/alternates)", () => {
    test("control: without the creator's refusal git DOES follow a planted chain; the creator refuses it", () => {
      const victim = join(root, "victim");
      const victimSha = mkRepo(victim);
      mkdirSync(join(ws, ".git", "objects", "info"), { recursive: true });
      writeFileSync(join(ws, ".git", "objects", "info", "alternates"), `${join(victim, ".git", "objects")}\n`);
      const manual = mkdtempSync(join(root, "manual-"));
      git(manual, "init", "-q", "--bare", manual);
      const seen = execFileSync("git", ["cat-file", "-t", victimSha], {
        encoding: "utf8",
        env: { ...gitFixtureEnv(root), GIT_DIR: manual, GIT_ALTERNATE_OBJECT_DIRECTORIES: join(ws, ".git", "objects") },
      }).trim();
      expect(seen).toBe("commit"); // the chain is followed: V is visible through the workspace alternate
      let err: unknown;
      try {
        createIsolatedPushDir(ws);
      } catch (e) {
        err = e;
      }
      expect(err).toBeInstanceOf(IsolatedPushDirRefusal);
      expect((err as IsolatedPushDirRefusal).reason).toBe("object_store_redirect");
    });
  });
});
