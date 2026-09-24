// Guard Contract for the sandboxed likec4 render child (#8696; plan
// 2026-09-24 "Guard 1", "Guard 3", "Guard 4" and the boot self-probe).
//
// The chokepoint is the (cmd, args) actually passed to `spawn`, observed through
// the child_process mock — NOT the builder's return value, so a mount spliced in
// at the call site is caught too. `checkSandboxArgv` is a test-local, pure
// checker whose allowlist lives HERE (not derived from the module under test):
// weakening the sandbox needs this file and the builder edited together.
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { EventEmitter } from "node:events";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

const spawnMock = vi.hoisted(() => vi.fn());
vi.mock("node:child_process", () => ({ spawn: spawnMock }));

const fsMock = vi.hoisted(() => ({
  lstat: vi.fn(),
  readdir: vi.fn(),
  mkdir: vi.fn(),
  mkdtemp: vi.fn(),
  readFile: vi.fn(),
  writeFile: vi.fn(),
  rm: vi.fn(),
  open: vi.fn(),
  realpath: vi.fn(),
}));
vi.mock("node:fs/promises", () => fsMock);

const obs = vi.hoisted(() => ({ reportSilentFallback: vi.fn(), warnSilentFallback: vi.fn() }));
vi.mock("@/server/observability", () => obs);
const sentry = vi.hoisted(() => ({ captureMessage: vi.fn() }));
vi.mock("@sentry/nextjs", () => sentry);
const log = vi.hoisted(() => ({ info: vi.fn(), warn: vi.fn(), error: vi.fn() }));
vi.mock("@/server/logger", () => ({ default: log }));

type Mod = typeof import("@/server/c4-render");

const ROOT = "/srv/c4-stage-root";
const NODE = "/usr/local/bin/node";
const LIKEC4_LINK = "/usr/local/bin/likec4";
const LIKEC4_ENTRY = "/usr/local/lib/node_modules/likec4/bin/likec4.mjs";
const POOL_KEY = Symbol.for("soleur.c4RenderPool");
const VALID_MODEL = JSON.stringify({
  elements: { u: { id: "u" }, s: { id: "s" } },
  views: { index: { hash: "x" } },
});

type FakeChild = EventEmitter & {
  stderr: EventEmitter;
  stdio: unknown[];
  kill: ReturnType<typeof vi.fn>;
};
function makeChild(): FakeChild {
  const child = new EventEmitter() as FakeChild;
  child.stderr = new EventEmitter();
  const status = new EventEmitter();
  child.stdio = [null, null, child.stderr, status];
  child.kill = vi.fn();
  return child;
}
function status(child: FakeChild, text: string) {
  (child.stdio[3] as EventEmitter).emit("data", Buffer.from(text));
}
/** A child that exits 0 after a successful sandbox run. */
function okChild(): FakeChild {
  const child = makeChild();
  spawnMock.mockImplementationOnce(() => {
    queueMicrotask(() => {
      status(child, '{ "child-pid": 7 }\n{ "exit-code": 0 }\n');
      child.emit("close", 0, null);
    });
    return child;
  });
  return child;
}

const REALPATHS = new Map<string, string>();
let tempN = 0;

function fileHandle(content: string) {
  return {
    stat: async () => ({ isFile: () => true, size: Buffer.byteLength(content) }),
    readFile: async () => content,
    close: async () => {},
  };
}

beforeEach(() => {
  vi.useRealTimers();
  delete (globalThis as Record<symbol, unknown>)[POOL_KEY];
  spawnMock.mockReset();
  for (const f of Object.values(obs)) f.mockReset();
  sentry.captureMessage.mockReset();
  for (const f of Object.values(log)) f.mockReset();
  tempN = 0;
  REALPATHS.clear();
  REALPATHS.set("/usr/bin/bwrap", "/usr/bin/bwrap");
  REALPATHS.set(process.execPath, NODE);
  REALPATHS.set(LIKEC4_LINK, LIKEC4_ENTRY);
  fsMock.realpath.mockReset().mockImplementation(async (p: string) => {
    const r = REALPATHS.get(String(p));
    if (!r) throw Object.assign(new Error(`ENOENT: ${p}`), { code: "ENOENT" });
    return r;
  });
  fsMock.mkdir.mockReset().mockResolvedValue(undefined);
  fsMock.lstat.mockReset().mockResolvedValue({
    isDirectory: () => true,
    isSymbolicLink: () => false,
    uid: typeof process.getuid === "function" ? process.getuid() : 0,
    mtimeMs: Date.now(),
  });
  fsMock.readdir.mockReset().mockImplementation(async (p: string) =>
    String(p).endsWith("/src") ? [{ name: "model.c4", isDirectory: () => false, isFile: () => true }] : [],
  );
  fsMock.mkdtemp.mockReset().mockImplementation(async (prefix: string) => `${prefix}${++tempN}`);
  fsMock.readFile.mockReset().mockResolvedValue("");
  fsMock.writeFile.mockReset().mockResolvedValue(undefined);
  fsMock.rm.mockReset().mockResolvedValue(undefined);
  fsMock.open.mockReset().mockImplementation(async () => fileHandle(VALID_MODEL));
  vi.stubEnv("LIKEC4_BIN", LIKEC4_LINK);
  vi.stubEnv("C4_RENDER_STAGING_ROOT", ROOT);
  vi.stubEnv("NODE_ENV", "test");
  vi.stubEnv("C4_RENDER_SANDBOX", "");
});

afterEach(() => {
  vi.unstubAllEnvs();
  vi.useRealTimers();
  delete (globalThis as Record<symbol, unknown>)[POOL_KEY];
});

async function load(): Promise<Mod> {
  vi.resetModules();
  return import("@/server/c4-render");
}

const STAGE = async () => ({ ok: true as const, paths: ["model.c4"], sourceKey: "k" });

// ---------------------------------------------------------------------------
// The test-local checker. Allowlist + arities live here, not in the module.
// ---------------------------------------------------------------------------
const TMPFS_BYTES = String(64 * 1024 * 1024);
const ARITY: Record<string, number> = {
  "--ro-bind": 2,
  "--bind": 2,
  "--symlink": 2,
  "--tmpfs": 1,
  "--size": 1,
  "--dev": 1,
  "--remount-ro": 1,
  "--chdir": 1,
  "--setenv": 2,
  "--clearenv": 0,
  "--die-with-parent": 0,
  "--new-session": 0,
  "--unshare-user": 0,
  "--unshare-pid": 0,
  "--unshare-net": 0,
  "--unshare-ipc": 0,
  "--unshare-uts": 0,
  "--json-status-fd": 1,
};
const MOUNT_OPS = new Set(["--ro-bind", "--bind", "--symlink", "--tmpfs", "--dev"]);
type Kind = "ro" | "rw" | "symlink" | "tmpfs" | "dev";
const BASE: Record<string, { kind: Kind; src?: string }> = {
  "/usr": { kind: "ro", src: "/usr" },
  "/bin": { kind: "symlink", src: "usr/bin" },
  "/lib": { kind: "symlink", src: "usr/lib" },
  "/lib64": { kind: "symlink", src: "usr/lib64" },
  "/sbin": { kind: "symlink", src: "usr/sbin" },
  "/etc/ld.so.cache": { kind: "ro", src: "/etc/ld.so.cache" },
  "/etc/passwd": { kind: "ro", src: "/etc/passwd" },
  "/etc/group": { kind: "ro", src: "/etc/group" },
  "/dev": { kind: "dev" },
  "/dev/shm": { kind: "tmpfs" },
  "/tmp": { kind: "tmpfs" },
  "/c4-home": { kind: "tmpfs" },
  "/c4-sources": { kind: "ro" },
  "/c4-out": { kind: "rw" },
};
const NAMESPACES = ["--unshare-user", "--unshare-pid", "--unshare-net", "--unshare-ipc", "--unshare-uts"];

function renderTail(nodeBin = NODE, entry = LIKEC4_ENTRY): string[] {
  return [
    "/usr/bin/prlimit", "--nproc=64", "--",
    nodeBin, entry, "export", "json", "--no-use-dot", "-o", "/c4-out/model.likec4.json", ".",
  ];
}

type Ctx = { stageDir: string; root: string; extra?: string[]; tail?: string[] };
type Check = { code: string; parsed: number };

function checkSandboxArgv(cmd: string, args: string[], ctx: Ctx): Check {
  let parsed = 0;
  const r = (code: string): Check => ({ code, parsed });
  if (cmd !== "/usr/bin/choom") return r("launcher");
  if (args.slice(0, 4).join(" ") !== "-n 1000 -- /usr/bin/bwrap") return r("launcher");
  const argv = args.slice(4);
  const mounts = new Map<string, { kind: Kind; src?: string }>();
  const unshare = new Set<string>();
  const env = new Map<string, string>();
  const remounts: Array<{ dest: string; at: number }> = [];
  let clearenv = false;
  let lastMount = -1;
  let pendingSize = false;
  let dashdash = -1;
  const flags = new Set<string>();
  let chdir: string | undefined;
  let statusFd: string | undefined;
  let i = 0;
  while (i < argv.length) {
    const opt = argv[i];
    if (opt === "--") {
      dashdash = i;
      break;
    }
    if (!(opt in ARITY)) return r("forbidden-option");
    const a = argv.slice(i + 1, i + 1 + ARITY[opt]);
    parsed++;
    if (pendingSize && opt !== "--tmpfs") return r("unsized-tmpfs");
    const addMount = (dest: string, m: { kind: Kind; src?: string }) => {
      if (mounts.has(dest)) return false;
      mounts.set(dest, m);
      lastMount = i;
      return true;
    };
    switch (opt) {
      case "--size":
        if (a[0] !== TMPFS_BYTES) return r("unsized-tmpfs");
        pendingSize = true;
        break;
      case "--tmpfs":
        if (!pendingSize) return r("unsized-tmpfs");
        pendingSize = false;
        if (!addMount(a[0], { kind: "tmpfs" })) return r("duplicate-destination");
        break;
      case "--ro-bind":
        if (!addMount(a[1], { kind: "ro", src: a[0] })) return r("duplicate-destination");
        break;
      case "--bind":
        if (!addMount(a[1], { kind: "rw", src: a[0] })) return r("duplicate-destination");
        break;
      case "--symlink":
        if (!addMount(a[1], { kind: "symlink", src: a[0] })) return r("duplicate-destination");
        break;
      case "--dev":
        if (!addMount(a[0], { kind: "dev" })) return r("duplicate-destination");
        break;
      case "--remount-ro":
        remounts.push({ dest: a[0], at: i });
        break;
      case "--setenv":
        env.set(a[0], a[1]);
        break;
      case "--clearenv":
        clearenv = true;
        break;
      case "--chdir":
        chdir = a[0];
        break;
      case "--json-status-fd":
        statusFd = a[0];
        break;
      default:
        if (opt.startsWith("--unshare-")) unshare.add(opt);
        else flags.add(opt);
    }
    void MOUNT_OPS;
    i += 1 + ARITY[opt];
  }
  if (dashdash < 0) return r("no-dashdash");
  if (parsed < 25) return r("too-few-options");
  if (pendingSize) return r("unsized-tmpfs");
  const expected: Record<string, { kind: Kind; src?: string }> = { ...BASE };
  for (const p of ctx.extra ?? []) expected[p] = { kind: "ro", src: p };
  for (const dest of mounts.keys()) if (!(dest in expected)) return r("extra-destination");
  for (const dest of Object.keys(expected)) if (!mounts.has(dest)) return r("missing-destination");
  for (const [dest, m] of mounts) {
    const want = expected[dest];
    if (m.kind !== want.kind) return r(m.kind === "rw" ? "writable-bind" : "kind-mismatch");
  }
  if (!ctx.stageDir.startsWith(`${ctx.root}/`)) return r("source-mismatch");
  for (const [dest, m] of mounts) {
    const want = expected[dest];
    if (dest === "/c4-sources") {
      if (m.src !== `${ctx.stageDir}/src`) return r("source-mismatch");
    } else if (dest === "/c4-out") {
      if (m.src !== `${ctx.stageDir}/out`) return r("source-mismatch");
    } else if (want.src !== undefined && m.src !== want.src) {
      return r("source-mismatch");
    }
  }
  const remountDests = remounts.map((x) => x.dest).sort();
  if (remountDests.join(",") !== "/,/dev") return r("order");
  if (remounts.some((x) => x.at < lastMount)) return r("order");
  if ([...unshare].sort().join(",") !== [...NAMESPACES].sort().join(",")) return r("namespaces");
  if (!clearenv) return r("env");
  if ([...env.keys()].sort().join(",") !== "HOME,LANG,PATH,TMPDIR") return r("env");
  if (env.get("HOME") !== "/c4-home" || env.get("TMPDIR") !== "/tmp" || env.get("LANG") !== "C.UTF-8") return r("env");
  if (!flags.has("--die-with-parent") || !flags.has("--new-session")) return r("missing-flag");
  if (chdir !== "/c4-sources") return r("chdir");
  if (statusFd !== "3") return r("status-fd");
  const tail = argv.slice(dashdash + 1);
  if (tail.join("\0") !== (ctx.tail ?? renderTail()).join("\0")) return r("tail");
  return r("ok");
}

/** Render once and return the observed spawn + its stage dir. */
async function observe(m?: Mod) {
  const mod = m ?? (await load());
  okChild();
  const res = await mod.renderC4Model(STAGE);
  const [cmd, args, opts] = spawnMock.mock.calls[0] as [string, string[], Record<string, unknown>];
  const stageDir = String(await fsMock.mkdtemp.mock.results[0].value);
  return { mod, res, cmd, args, opts, stageDir };
}

/** Splice `items` into the bwrap options right before `--`. */
function spliceBeforeDashDash(args: string[], items: string[], at: "last" | number = "last"): string[] {
  const out = [...args];
  const dd = out.indexOf("--", 4);
  out.splice(at === "last" ? dd : at, 0, ...items);
  return out;
}

describe("Guard 1 — likec4 child mount/env/namespace closure", () => {
  it("the observed production-shaped spawn passes the checker (must-PASS baseline)", async () => {
    const { res, cmd, args, opts, stageDir } = await observe();
    expect(res.ok).toBe(true);
    const c = checkSandboxArgv(cmd, args, { stageDir, root: ROOT });
    expect(c.code).toBe("ok");
    expect(c.parsed).toBeGreaterThanOrEqual(25);
    // bwrap's own env is the allow-list: it never sees a server secret.
    const env = opts.env as Record<string, string>;
    expect(Object.keys(env).every((k) => ["PATH", "LANG", "LC_ALL", "HOME", "TMPDIR"].includes(k))).toBe(true);
    expect(opts.stdio).toEqual(["ignore", "ignore", "pipe", "pipe"]);
    expect(stageDir.startsWith(`${ROOT}/c4-render-`)).toBe(true);
  });

  const cases: Array<[string, (a: string[], sd: string) => string[], string]> = [
    ["1 --bind /workspaces", (a) => spliceBeforeDashDash(a, ["--bind", "/workspaces", "/workspaces"]), "extra-destination"],
    ["2 --ro-bind / /", (a) => spliceBeforeDashDash(a, ["--ro-bind", "/", "/"]), "extra-destination"],
    ["3a --proc /proc", (a) => spliceBeforeDashDash(a, ["--proc", "/proc"]), "forbidden-option"],
    ["3b --ro-bind /proc /proc", (a) => spliceBeforeDashDash(a, ["--ro-bind", "/proc", "/proc"]), "extra-destination"],
    [
      "4 source bind made writable",
      (a) => {
        const o = [...a];
        const k = o.indexOf("/c4-sources");
        o[k - 2] = "--bind";
        return o;
      },
      "writable-bind",
    ],
    ["5a --unshare-net removed", (a) => a.filter((x) => x !== "--unshare-net"), "namespaces"],
    ["5b --share-net added", (a) => spliceBeforeDashDash(a, ["--share-net"]), "forbidden-option"],
    ["6a --clearenv removed", (a) => a.filter((x) => x !== "--clearenv"), "env"],
    ["6b secret setenv", (a) => spliceBeforeDashDash(a, ["--setenv", "SUPABASE_SERVICE_ROLE_KEY", "x"]), "env"],
    ["7 a second bind of /app", (a) => spliceBeforeDashDash(a, ["--ro-bind", "/app", "/app"]), "extra-destination"],
    ["8 call-site splice --bind /home", (a) => spliceBeforeDashDash(a, ["--bind", "/home", "/home"]), "extra-destination"],
    [
      "9a /c4-sources from /workspaces",
      (a) => {
        const o = [...a];
        o[o.indexOf("/c4-sources") - 1] = "/workspaces";
        return o;
      },
      "source-mismatch",
    ],
    [
      "9b /c4-out from /tmp",
      (a) => {
        const o = [...a];
        o[o.indexOf("/c4-out") - 1] = "/tmp";
        return o;
      },
      "source-mismatch",
    ],
    [
      "9c /usr from /app",
      (a) => {
        const o = [...a];
        const k = o.findIndex((x, j) => x === "/usr" && o[j + 1] === "/usr");
        o[k] = "/app";
        return o;
      },
      "source-mismatch",
    ],
    [
      "9d /c4-out from another stage",
      (a, sd) => {
        const o = [...a];
        o[o.indexOf("/c4-out") - 1] = `${sd.replace(/\d+$/, "99")}/out`;
        return o;
      },
      "source-mismatch",
    ],
    ["10a --remount-ro / removed", (a) => {
      const o = [...a];
      const k = o.findIndex((x, j) => x === "--remount-ro" && o[j + 1] === "/");
      o.splice(k, 2);
      return o;
    }, "order"],
    ["10b --remount-ro /dev moved first", (a) => {
      const o = [...a];
      const k = o.findIndex((x, j) => x === "--remount-ro" && o[j + 1] === "/dev");
      const [x, y] = o.splice(k, 2);
      o.splice(4, 0, x, y);
      return o;
    }, "order"],
    ["11a --no-use-dot dropped", (a) => a.filter((x) => x !== "--no-use-dot"), "tail"],
    ["11b -o outside /c4-out", (a) => a.map((x) => (x === "/c4-out/model.likec4.json" ? "/tmp/m.json" : x)), "tail"],
    ["14a tmpfs without --size", (a) => {
      const o = [...a];
      const k = o.findIndex((x, j) => x === "--tmpfs" && o[j + 1] === "/tmp");
      o.splice(k - 2, 2);
      return o;
    }, "unsized-tmpfs"],
    ["14b tmpfs with another size", (a) => {
      const o = [...a];
      const k = o.findIndex((x, j) => x === "--tmpfs" && o[j + 1] === "/c4-home");
      o[k - 1] = "999";
      return o;
    }, "unsized-tmpfs"],
    ["15 bwrap by PATH lookup", (a) => a.map((x) => (x === "/usr/bin/bwrap" ? "bwrap" : x)), "launcher"],
  ];
  for (const [name, mutate, code] of cases) {
    it(`row ${name} → ${code}`, async () => {
      const { cmd, args, stageDir } = await observe();
      const mutated = mutate(args, stageDir);
      // The mutation landed.
      expect(mutated).not.toEqual(args);
      expect(checkSandboxArgv(cmd, mutated, { stageDir, root: ROOT }).code).toBe(code);
    });
  }

  it("row 12: the checker's own dispatch — reading the argv AFTER `--` parses nothing and fails", async () => {
    const { cmd, args, stageDir } = await observe();
    const c = checkSandboxArgv(cmd, args, { stageDir, root: ROOT });
    expect(c.parsed).toBeGreaterThanOrEqual(25);
    const onlyTail = [...args.slice(0, 4), "--", ...args.slice(args.indexOf("--", 4) + 1)];
    expect(checkSandboxArgv(cmd, onlyTail, { stageDir, root: ROOT }).code).toBe("too-few-options");
  });

  it("row 13: NODE_ENV=production with node (or bwrap) resolving outside /usr never spawns", async () => {
    vi.stubEnv("NODE_ENV", "production");
    REALPATHS.set(process.execPath, "/opt/node/bin/node");
    let mod = await load();
    let res = await mod.renderC4Model(STAGE);
    expect(spawnMock).not.toHaveBeenCalled();
    expect(res).toMatchObject({ ok: false, reason: "sandbox_error", detail: "binary outside /usr", detailClass: "outside-usr" });

    REALPATHS.set(process.execPath, NODE);
    REALPATHS.set("/usr/bin/bwrap", "/opt/evil/bwrap");
    mod = await load();
    res = await mod.renderC4Model(STAGE);
    expect(spawnMock).not.toHaveBeenCalled();
    expect(res).toMatchObject({ ok: false, reason: "sandbox_error", detail: "binary outside /usr" });
  });

  it("row 16: binaries are resolved lazily and only a successful resolution is memoized", async () => {
    fsMock.realpath.mockReset().mockRejectedValue(new Error("EACCES"));
    const mod = await load();
    expect(fsMock.realpath).not.toHaveBeenCalled();
    const res = await mod.renderC4Model(STAGE);
    expect(res).toMatchObject({ ok: false, reason: "sandbox_error", phase: "spawn", detail: "likec4 not resolvable", detailClass: "not-resolvable" });
    expect(spawnMock).not.toHaveBeenCalled();
    fsMock.realpath.mockReset().mockImplementation(async (p: string) => REALPATHS.get(String(p)) ?? Promise.reject(new Error("ENOENT")));
    okChild();
    expect((await mod.renderC4Model(STAGE)).ok).toBe(true);
    expect(spawnMock).toHaveBeenCalledTimes(1);
  });

  it("H1: a forbidden bind in the LAST option position before `--` is still caught", async () => {
    const { cmd, args, stageDir } = await observe();
    const dd = args.indexOf("--", 4);
    const mutated = [...args.slice(0, dd), "--bind", "/app", "/app", ...args.slice(dd)];
    expect(checkSandboxArgv(cmd, mutated, { stageDir, root: ROOT }).code).toBe("extra-destination");
  });

  it("H2: swapping two independent --ro-bind ops still passes (bind order is free)", async () => {
    const { cmd, args, stageDir } = await observe();
    const o = [...args];
    const a = o.indexOf("/etc/passwd") - 1;
    const b = o.indexOf("/etc/group") - 1;
    [o[a], o[a + 1], o[a + 2], o[b], o[b + 1], o[b + 2]] = [o[b], o[b + 1], o[b + 2], o[a], o[a + 1], o[a + 2]];
    expect(o).not.toEqual(args);
    expect(checkSandboxArgv(cmd, o, { stageDir, root: ROOT }).code).toBe("ok");
  });

  it("H3: outside production an extra --ro-bind p p (hosted-toolcache node) passes; --bind or a moved destination does not", async () => {
    const TOOL = "/opt/hostedtoolcache/node/22/x64";
    REALPATHS.set(process.execPath, `${TOOL}/bin/node`);
    REALPATHS.set(LIKEC4_LINK, `${TOOL}/lib/node_modules/likec4/bin/likec4.mjs`);
    const { cmd, args, stageDir } = await observe();
    const ctx = { stageDir, root: ROOT, extra: [TOOL], tail: renderTail(`${TOOL}/bin/node`, `${TOOL}/lib/node_modules/likec4/bin/likec4.mjs`) };
    expect(checkSandboxArgv(cmd, args, ctx).code).toBe("ok");
    const k = args.findIndex((x, j) => x === TOOL && args[j + 1] === TOOL);
    const rw = [...args];
    rw[k - 1] = "--bind";
    expect(checkSandboxArgv(cmd, rw, ctx).code).toBe("writable-bind");
    const moved = [...args];
    moved[k + 1] = "/opt/elsewhere";
    expect(checkSandboxArgv(cmd, moved, ctx).code).toBe("extra-destination");
  });
});

describe("Guard 3 — no unsandboxed spawn in production", () => {
  it("row 1: bwrap spawn ENOENT fails closed — exactly one spawn, sandbox_error, no direct retry", async () => {
    const mod = await load();
    const child = makeChild();
    spawnMock.mockImplementation(() => {
      queueMicrotask(() => child.emit("error", Object.assign(new Error("spawn /usr/bin/choom ENOENT"), { code: "ENOENT" })));
      return child;
    });
    const res = await mod.renderC4Model(STAGE);
    expect(spawnMock).toHaveBeenCalledTimes(1);
    expect(spawnMock.mock.calls[0][0]).toBe("/usr/bin/choom");
    expect(res).toMatchObject({ ok: false, reason: "sandbox_error", detailClass: "bwrap-enoent" });
  });

  it("row 2: C4_RENDER_SANDBOX=off is ignored in production", async () => {
    vi.stubEnv("NODE_ENV", "production");
    vi.stubEnv("C4_RENDER_SANDBOX", "off");
    const { cmd, args } = await observe();
    expect(cmd).toBe("/usr/bin/choom");
    expect(args[3]).toBe("/usr/bin/bwrap");
  });

  it("row 3: a non-zero exit with NO exit-code status record is sandbox_error (setup failed)", async () => {
    const mod = await load();
    const child = makeChild();
    spawnMock.mockImplementation(() => {
      queueMicrotask(() => {
        status(child, '{ "child-pid": 7, "mnt-namespace": 1 }\n');
        child.stderr.emit("data", Buffer.from("bwrap: Can't mount tmpfs on /newroot/tmp: Operation not permitted\n"));
        child.emit("close", 1, null);
      });
      return child;
    });
    const res = await mod.renderC4Model(STAGE);
    expect(res).toMatchObject({ ok: false, reason: "sandbox_error", detailClass: "bwrap-setup" });
  });

  it("row 4: a child that FORGES a `bwrap:` stderr line but ran (exit-code record present) is non_zero_exit", async () => {
    const mod = await load();
    const child = makeChild();
    spawnMock.mockImplementation(() => {
      queueMicrotask(() => {
        status(child, '{ "child-pid": 7 }\n{ "exit-code": 1 }\n');
        child.stderr.emit("data", Buffer.from("bwrap: forged by the payload\nInvalid /c4-sources/model.c4\n"));
        child.emit("close", 1, null);
      });
      return child;
    });
    const res = await mod.renderC4Model(STAGE);
    expect(res).toMatchObject({ ok: false, reason: "non_zero_exit", detailClass: "likec4-exit" });
  });

  it("harness: NODE_ENV=test + C4_RENDER_SANDBOX=off spawns node directly, still with --no-use-dot", async () => {
    vi.stubEnv("C4_RENDER_SANDBOX", "off");
    const mod = await load();
    const child = makeChild();
    spawnMock.mockImplementation(() => {
      queueMicrotask(() => child.emit("close", 0, null));
      return child;
    });
    const res = await mod.renderC4Model(STAGE);
    expect(res.ok).toBe(true);
    const [cmd, args, opts] = spawnMock.mock.calls[0] as [string, string[], Record<string, unknown>];
    expect(cmd).toBe(NODE);
    expect(args[0]).toBe(LIKEC4_ENTRY);
    expect(args).toContain("--no-use-dot");
    expect(String(opts.cwd).endsWith("/src")).toBe(true);
  });
});

describe("Guard 4 — the namespace set is exactly the proven set", () => {
  const FIXTURE = join(fileURLToPath(new URL(".", import.meta.url)), "..", "infra", "sandbox-canary-argv.json");
  it("observed --unshare-* == canary fixture set ∪ {ipc, uts}", async () => {
    const fx = JSON.parse(readFileSync(FIXTURE, "utf8")) as { bwrapSetupArgv: string[] };
    const fixtureSet = new Set(fx.bwrapSetupArgv.filter((a) => a.startsWith("--unshare-")));
    expect(fixtureSet.size).toBeGreaterThan(0);
    expect(fixtureSet.has("--unshare-user")).toBe(true);
    const { args } = await observe();
    const observed = new Set(args.slice(0, args.indexOf("--", 4)).filter((a) => a.startsWith("--unshare-")));
    expect([...observed].sort()).toEqual([...fixtureSet, "--unshare-ipc", "--unshare-uts"].sort());
  });
});

describe("render pool, stderr cap and the timeout path", () => {
  it("the pool is shared across two module instances; a waiter gives up after SLOT_WAIT_MS", async () => {
    vi.useFakeTimers();
    const a = await load();
    const held: FakeChild[] = [];
    spawnMock.mockImplementation(() => {
      const c = makeChild();
      held.push(c);
      return c;
    });
    const running = [a.renderC4Model(STAGE), a.renderC4Model(STAGE)];
    await vi.waitFor(() => expect(spawnMock).toHaveBeenCalledTimes(2));
    const b = await load();
    expect(b).not.toBe(a);
    const waiting = b.renderC4Model(STAGE);
    await vi.advanceTimersByTimeAsync(b.SLOT_WAIT_MS + 1);
    const res = await waiting;
    expect(res).toMatchObject({ ok: false, reason: "timeout", detail: b.RENDER_SLOT_WAIT_DETAIL, detailClass: "slot-wait" });
    expect(spawnMock).toHaveBeenCalledTimes(2);
    for (const c of held) {
      status(c, '{ "exit-code": 0 }\n');
      c.emit("close", 0, null);
    }
    await Promise.all(running);
    const pool = (globalThis as Record<symbol, { inFlight: number; waiters: unknown[] }>)[POOL_KEY];
    expect(pool.inFlight).toBe(0);
    expect(pool.waiters).toHaveLength(0);
  });

  it("successful renders report queueWaitMs", async () => {
    const { res } = await observe();
    expect(res.ok).toBe(true);
    if (res.ok) expect(typeof res.queueWaitMs).toBe("number");
  });

  it("stderr is retained only up to 512 bytes while the pipe keeps draining", async () => {
    const mod = await load();
    const child = makeChild();
    const concat = vi.spyOn(Buffer, "concat");
    spawnMock.mockImplementation(() => {
      queueMicrotask(() => {
        for (let k = 0; k < 64; k++) child.stderr.emit("data", Buffer.alloc(1024, 0x61));
        status(child, '{ "exit-code": 3 }\n');
        child.emit("close", 3, null);
      });
      return child;
    });
    await mod.renderC4Model(STAGE);
    const inputs = concat.mock.calls
      .map((c) => c[0] as Buffer[])
      .filter((bufs) => bufs.length > 0 && bufs.every((b) => b.length === 1024 && b[0] === 0x61));
    concat.mockRestore();
    expect(inputs.length).toBeGreaterThan(0);
    for (const bufs of inputs) expect(bufs.reduce((n, b) => n + b.length, 0)).toBeLessThanOrEqual(512 + 1024);
    expect(child.stderr.listenerCount("data")).toBe(1);
  });

  it("timeout: SIGKILL, then wait for `close` before settling; the stage is removed only after close", async () => {
    vi.useFakeTimers();
    const mod = await load();
    const child = makeChild();
    const order: string[] = [];
    child.kill.mockImplementation(() => {
      order.push("kill");
      setTimeout(() => {
        order.push("close");
        child.emit("close", null, "SIGKILL");
      }, 100);
    });
    fsMock.rm.mockImplementation(async (p: string) => {
      if (String(p).startsWith(`${ROOT}/c4-render-`)) order.push("rm");
    });
    spawnMock.mockImplementation(() => child);
    const p = mod.renderC4Model(STAGE);
    await vi.advanceTimersByTimeAsync(25_001);
    await vi.advanceTimersByTimeAsync(200);
    const res = await p;
    expect(res).toMatchObject({ ok: false, reason: "timeout" });
    expect(order).toEqual(["kill", "close", "rm"]);
  });

  it("timeout: a child that never closes → sandbox_error 'sandbox did not exit' and the stage is NOT removed", async () => {
    vi.useFakeTimers();
    const mod = await load();
    const child = makeChild();
    spawnMock.mockImplementation(() => child);
    const p = mod.renderC4Model(STAGE);
    await vi.advanceTimersByTimeAsync(25_001);
    await vi.advanceTimersByTimeAsync(5_001);
    await vi.advanceTimersByTimeAsync(3_000);
    const res = await p;
    expect(res).toMatchObject({ ok: false, reason: "sandbox_error", detail: "sandbox did not exit", detailClass: "sandbox-no-exit" });
    const stageDir = String(await fsMock.mkdtemp.mock.results[0].value);
    expect(fsMock.rm.mock.calls.some((c) => String(c[0]) === stageDir)).toBe(false);
  });
});

describe("boot self-probe", () => {
  it("renders a real fixture through the one spawn site and emits the Sentry info event", async () => {
    const mod = await load();
    okChild();
    await mod.verifyC4RenderSandboxOnce();
    expect(spawnMock).toHaveBeenCalledTimes(1);
    expect(spawnMock.mock.calls[0][0]).toBe("/usr/bin/choom");
    // The probe stages its own fixture.
    const written = fsMock.writeFile.mock.calls.map((c) => String(c[0]));
    expect(written.some((p) => p.endsWith("/src/model.c4"))).toBe(true);
    expect(sentry.captureMessage).toHaveBeenCalledWith(
      "c4 render sandbox probe ok",
      expect.objectContaining({ level: "info", tags: { event_type: "c4-sandbox-probe" } }),
    );
    expect(log.info).toHaveBeenCalledWith(expect.objectContaining({ event: "c4_render_sandbox_probe", ok: true }), expect.any(String));
    expect(obs.reportSilentFallback).not.toHaveBeenCalled();
  });

  it("a failed probe render reports via reportSilentFallback(null, …) with reason + detail_class", async () => {
    const mod = await load();
    const child = makeChild();
    spawnMock.mockImplementation(() => {
      queueMicrotask(() => {
        child.stderr.emit("data", Buffer.from("bwrap: setting up uid map: Permission denied\n"));
        child.emit("close", 1, null);
      });
      return child;
    });
    await mod.verifyC4RenderSandboxOnce();
    expect(obs.reportSilentFallback).toHaveBeenCalledTimes(1);
    const [err, opts] = obs.reportSilentFallback.mock.calls[0];
    expect(err).toBeNull();
    expect(opts).toMatchObject({
      feature: "c4-rerender",
      op: "sandbox-selfprobe",
      message: "c4 render sandbox self-probe failed: sandbox_error",
      tags: { reason: "sandbox_error", detail_class: "bwrap-setup" },
    });
    expect(sentry.captureMessage).not.toHaveBeenCalled();
  });

  it("reports inheritable (non-CLOEXEC) file fds by count and kind only", async () => {
    const mod = await load();
    okChild();
    fsMock.readdir.mockImplementation(async (p: string) => {
      if (String(p) === "/proc/self/fdinfo") return ["0", "1", "2", "5", "7", "9"];
      return String(p).endsWith("/src") ? [{ name: "model.c4", isDirectory: () => false, isFile: () => true }] : [];
    });
    fsMock.readFile.mockImplementation(async (p: string) => {
      if (String(p) === "/proc/self/fdinfo/5") return "pos:\t0\nflags:\t02100002\n"; // CLOEXEC
      if (String(p) === "/proc/self/fdinfo/7") return "pos:\t0\nflags:\t0100002\n"; // inheritable file
      if (String(p) === "/proc/self/fdinfo/9") return "pos:\t0\nflags:\t0100002\n"; // inheritable socket
      return "";
    });
    REALPATHS.set("/proc/self/fd/7", "/secret/tenant/file");
    // fd 5 resolves to a file too: only its close-on-exec flag may exclude it.
    REALPATHS.set("/proc/self/fd/5", "/some/cloexec/file");
    await mod.verifyC4RenderSandboxOnce();
    expect(obs.warnSilentFallback).toHaveBeenCalledTimes(1);
    const [err, opts] = obs.warnSilentFallback.mock.calls[0];
    expect(err).toBeNull();
    expect(opts).toMatchObject({ op: "sandbox-selfprobe-fds", extra: { count: 1 } });
    expect(JSON.stringify(opts)).not.toContain("/secret");
  });

  it("a throwing resolution never rejects the caller", async () => {
    fsMock.realpath.mockReset().mockImplementation(() => {
      throw new Error("sync boom");
    });
    const mod = await load();
    await expect(mod.verifyC4RenderSandboxOnce()).resolves.toBeUndefined();
    expect(obs.reportSilentFallback).toHaveBeenCalled();
  });
});
