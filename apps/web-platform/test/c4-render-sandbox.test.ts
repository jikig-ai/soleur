// Guard Contract for the sandboxed likec4 render child (#8696; plan
// 2026-09-24 "Guard 1", "Guard 3", "Guard 4", the output transport and the
// boot self-probe).
//
// The chokepoint is the (cmd, args, opts) actually passed to `spawn`, observed
// through the child_process mock — NOT the builder's return value, so a mount
// spliced in at the call site is caught too. `checkSandboxArgv` is a
// test-local, pure checker whose allowlist, launch chain and scripts live HERE
// (not derived from the module under test): weakening the sandbox needs this
// file and the builder edited together. Every return code the checker can
// produce has a row that drives it, and a meta-row fails when a code has none.
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
const LAUNCHERS = ["/usr/bin/bash", "/usr/bin/choom", "/usr/bin/nice", "/usr/bin/bwrap", "/usr/bin/prlimit", "/usr/bin/sh"];

type FakeChild = EventEmitter & {
  stdout: EventEmitter;
  stderr: EventEmitter;
  stdio: unknown[];
  kill: ReturnType<typeof vi.fn>;
};
function makeChild(): FakeChild {
  const child = new EventEmitter() as FakeChild;
  child.stdout = new EventEmitter();
  child.stderr = new EventEmitter();
  const status = new EventEmitter();
  child.stdio = [null, child.stdout, child.stderr, status];
  child.kill = vi.fn();
  return child;
}
function status(child: FakeChild, text: string) {
  (child.stdio[3] as EventEmitter).emit("data", Buffer.from(text));
}
/** A child that ran in the sandbox, printed the model and exited 0. */
function okChild(model = VALID_MODEL): FakeChild {
  const child = makeChild();
  spawnMock.mockImplementationOnce(() => {
    queueMicrotask(() => {
      child.stdout.emit("data", Buffer.from(model));
      status(child, '{ "child-pid": 7 }\n{ "exit-code": 0 }\n');
      child.emit("close", 0, null);
    });
    return child;
  });
  return child;
}

const REALPATHS = new Map<string, string>();
let tempN = 0;

beforeEach(() => {
  vi.useRealTimers();
  spawnMock.mockReset();
  for (const f of Object.values(obs)) f.mockReset();
  sentry.captureMessage.mockReset();
  for (const f of Object.values(log)) f.mockReset();
  tempN = 0;
  REALPATHS.clear();
  for (const l of LAUNCHERS) REALPATHS.set(l, l);
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
  fsMock.open.mockReset();
  vi.stubEnv("LIKEC4_BIN", LIKEC4_LINK);
  vi.stubEnv("C4_RENDER_STAGING_ROOT", ROOT);
  vi.stubEnv("NODE_ENV", "test");
  vi.stubEnv("C4_RENDER_SANDBOX", "");
});

let loaded: Mod | null = null;
afterEach(() => {
  vi.unstubAllEnvs();
  vi.useRealTimers();
  loaded?.__resetC4RenderStateForTests();
  loaded = null;
});

async function load(): Promise<Mod> {
  vi.resetModules();
  loaded = await import("@/server/c4-render");
  loaded.__resetC4RenderStateForTests();
  return loaded;
}

const STAGE = async () => ({ ok: true as const, paths: ["model.c4"], sourceKey: "k" });

// ---------------------------------------------------------------------------
// The test-local checker. Launch chain, scripts, allowlist and arities live
// here, not in the module.
// ---------------------------------------------------------------------------
const MiB = 1024 * 1024;
const CLOSE_FDS =
  'for p in /proc/self/fd/*; do n=${p##*/}; if [ "$n" -gt 3 ] 2>/dev/null; then eval "exec $n>&-"; fi; done; exec "$@"';
const RENDER_SH =
  '"$0" "$1" export json --no-use-dot -o /c4-out/model.likec4.json . >/dev/null && exec cat /c4-out/model.likec4.json';
const LAUNCH_PREFIX = [
  "-c", CLOSE_FDS, "c4-close-fds",
  "/usr/bin/choom", "-n", "1000", "--",
  "/usr/bin/nice", "-n", "10", "--",
  "/usr/bin/bwrap",
];
const ARITY: Record<string, number> = {
  "--ro-bind": 2,
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
type Kind = "ro" | "symlink" | "tmpfs" | "dev";
const BASE: Record<string, { kind: Kind; src?: string; size?: number }> = {
  "/usr": { kind: "ro", src: "/usr" },
  "/bin": { kind: "symlink", src: "usr/bin" },
  "/lib": { kind: "symlink", src: "usr/lib" },
  "/lib64": { kind: "symlink", src: "usr/lib64" },
  "/sbin": { kind: "symlink", src: "usr/sbin" },
  "/etc/ld.so.cache": { kind: "ro", src: "/etc/ld.so.cache" },
  "/etc/passwd": { kind: "ro", src: "/etc/passwd" },
  "/etc/group": { kind: "ro", src: "/etc/group" },
  "/dev": { kind: "dev" },
  "/dev/shm": { kind: "tmpfs", size: 16 * MiB },
  "/tmp": { kind: "tmpfs", size: 16 * MiB },
  "/c4-home": { kind: "tmpfs", size: 16 * MiB },
  "/c4-out": { kind: "tmpfs", size: 24 * MiB },
  "/c4-sources": { kind: "ro" },
};
const NAMESPACES = ["--unshare-user", "--unshare-pid", "--unshare-net", "--unshare-ipc", "--unshare-uts"];

function renderTail(nodeBin = NODE, entry = LIKEC4_ENTRY): string[] {
  return ["/usr/bin/prlimit", "--nproc=64", "--", "/usr/bin/sh", "-c", RENDER_SH, nodeBin, entry];
}

type Ctx = { stageDir: string; root: string; extra?: string[]; tail?: string[]; nodeDir?: string };
type Check = { code: string; parsed: number };

function checkSandboxArgv(cmd: string, args: string[], ctx: Ctx): Check {
  let parsed = 0;
  const r = (code: string): Check => ({ code, parsed });
  if (cmd !== "/usr/bin/bash") return r("launcher");
  if (args.slice(0, LAUNCH_PREFIX.length).join("\0") !== LAUNCH_PREFIX.join("\0")) return r("launcher");
  const argv = args.slice(LAUNCH_PREFIX.length);
  const mounts = new Map<string, { kind: Kind; src?: string; size?: number }>();
  const unshare = new Set<string>();
  const env = new Map<string, string>();
  const remounts: Array<{ dest: string; at: number }> = [];
  let clearenv = false;
  let lastMount = -1;
  let pendingSize: string | null = null;
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
    if (pendingSize !== null && opt !== "--tmpfs") return r("unsized-tmpfs");
    const addMount = (dest: string, m: { kind: Kind; src?: string; size?: number }) => {
      if (mounts.has(dest)) return false;
      mounts.set(dest, m);
      lastMount = i;
      return true;
    };
    switch (opt) {
      case "--size":
        pendingSize = a[0];
        break;
      case "--tmpfs":
        if (pendingSize === null) return r("unsized-tmpfs");
        if (!addMount(a[0], { kind: "tmpfs", size: Number(pendingSize) })) return r("duplicate-destination");
        pendingSize = null;
        break;
      case "--ro-bind":
        if (!addMount(a[1], { kind: "ro", src: a[0] })) return r("duplicate-destination");
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
    i += 1 + ARITY[opt];
  }
  if (dashdash < 0) return r("no-dashdash");
  if (parsed < 25) return r("too-few-options");
  if (pendingSize !== null) return r("unsized-tmpfs");
  const expected: Record<string, { kind: Kind; src?: string; size?: number }> = { ...BASE };
  for (const p of ctx.extra ?? []) expected[p] = { kind: "ro", src: p };
  for (const dest of mounts.keys()) if (!(dest in expected)) return r("extra-destination");
  for (const dest of Object.keys(expected)) if (!mounts.has(dest)) return r("missing-destination");
  for (const [dest, m] of mounts) if (m.kind !== expected[dest].kind) return r("kind-mismatch");
  for (const [dest, m] of mounts) {
    if (m.kind === "tmpfs" && m.size !== expected[dest].size) return r("unsized-tmpfs");
  }
  if (!ctx.stageDir.startsWith(`${ctx.root}/`)) return r("source-mismatch");
  for (const [dest, m] of mounts) {
    const want = expected[dest];
    if (dest === "/c4-sources") {
      if (m.src !== `${ctx.stageDir}/src`) return r("source-mismatch");
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
  const path = [...new Set([ctx.nodeDir ?? "/usr/local/bin", "/usr/local/bin", "/usr/bin", "/bin"])].join(":");
  if (env.get("HOME") !== "/c4-home" || env.get("TMPDIR") !== "/tmp" || env.get("LANG") !== "C.UTF-8") return r("env");
  if (env.get("PATH") !== path) return r("env");
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

const BW = LAUNCH_PREFIX.length;
/** Splice `items` into the bwrap options right before `--`. */
function spliceBeforeDashDash(args: string[], items: string[]): string[] {
  const out = [...args];
  out.splice(out.indexOf("--", BW), 0, ...items);
  return out;
}
/** Index of `opt` whose next args are `rest` (e.g. ("--tmpfs", "/tmp")). */
function optIdx(args: string[], opt: string, ...rest: string[]): number {
  return args.findIndex((x, j) => x === opt && rest.every((v, k) => args[j + 1 + k] === v));
}

const ROWS: Array<[string, (a: string[], sd: string) => string[], string]> = [
  ["cmd is not bash", (a) => a, "launcher"], // cmd swapped in the row body
  ["nice dropped from the launch chain", (a) => a.filter((_, j) => !(j >= 7 && j <= 10)), "launcher"],
  ["close-fds script edited", (a) => a.map((x) => (x === CLOSE_FDS ? CLOSE_FDS.replace("-gt 3", "-gt 9") : x)), "launcher"],
  ["--bind /workspaces", (a) => spliceBeforeDashDash(a, ["--bind", "/workspaces", "/workspaces"]), "forbidden-option"],
  ["--ro-bind / /", (a) => spliceBeforeDashDash(a, ["--ro-bind", "/", "/"]), "extra-destination"],
  ["--proc /proc", (a) => spliceBeforeDashDash(a, ["--proc", "/proc"]), "forbidden-option"],
  ["--ro-bind /proc /proc", (a) => spliceBeforeDashDash(a, ["--ro-bind", "/proc", "/proc"]), "extra-destination"],
  ["/c4-out made a writable host bind", (a, sd) => {
    const o = [...a];
    const k = optIdx(o, "--tmpfs", "/c4-out");
    o.splice(k - 2, 4, "--bind", `${sd}/out`, "/c4-out");
    return o;
  }, "forbidden-option"],
  ["--unshare-net removed", (a) => a.filter((x) => x !== "--unshare-net"), "namespaces"],
  ["--share-net added", (a) => spliceBeforeDashDash(a, ["--share-net"]), "forbidden-option"],
  ["--clearenv removed", (a) => a.filter((x) => x !== "--clearenv"), "env"],
  ["secret setenv", (a) => spliceBeforeDashDash(a, ["--setenv", "SUPABASE_SERVICE_ROLE_KEY", "x"]), "env"],
  ["HOME pointed at the sources", (a) => a.map((x, j) => (a[j - 1] === "HOME" && a[j - 2] === "--setenv" ? "/c4-sources" : x)), "env"],
  ["PATH prefixed with /c4-sources", (a) => a.map((x, j) => (a[j - 1] === "PATH" && a[j - 2] === "--setenv" ? `/c4-sources:${x}` : x)), "env"],
  ["a second bind of /app", (a) => spliceBeforeDashDash(a, ["--ro-bind", "/app", "/app"]), "extra-destination"],
  ["duplicate /tmp tmpfs", (a) => spliceBeforeDashDash(a, ["--size", String(16 * MiB), "--tmpfs", "/tmp"]), "duplicate-destination"],
  ["/c4-sources from /workspaces", (a) => {
    const o = [...a];
    o[o.indexOf("/c4-sources") - 1] = "/workspaces";
    return o;
  }, "source-mismatch"],
  ["/usr from /app", (a) => {
    const o = [...a];
    o[optIdx(o, "--ro-bind", "/usr", "/usr") + 1] = "/app";
    return o;
  }, "source-mismatch"],
  ["/tmp mount removed", (a) => {
    const o = [...a];
    o.splice(optIdx(o, "--tmpfs", "/tmp") - 2, 4);
    return o;
  }, "missing-destination"],
  ["/dev/shm made a ro-bind of the host's", (a) => {
    const o = [...a];
    const k = optIdx(o, "--tmpfs", "/dev/shm");
    o.splice(k - 2, 4, "--ro-bind", "/dev/shm", "/dev/shm");
    return o;
  }, "kind-mismatch"],
  ["--remount-ro / removed", (a) => {
    const o = [...a];
    o.splice(optIdx(o, "--remount-ro", "/"), 2);
    return o;
  }, "order"],
  ["--remount-ro /dev moved before the mounts", (a) => {
    const o = [...a];
    const [x, y] = o.splice(optIdx(o, "--remount-ro", "/dev"), 2);
    o.splice(BW, 0, x, y);
    return o;
  }, "order"],
  ["--no-use-dot dropped from the script", (a) => a.map((x) => (x === RENDER_SH ? RENDER_SH.replace(" --no-use-dot", "") : x)), "tail"],
  ["model written outside /c4-out", (a) => a.map((x) => (x === RENDER_SH ? RENDER_SH.replaceAll("/c4-out/", "/tmp/") : x)), "tail"],
  ["tmpfs without --size", (a) => {
    const o = [...a];
    o.splice(optIdx(o, "--tmpfs", "/tmp") - 2, 2);
    return o;
  }, "unsized-tmpfs"],
  ["/c4-out tmpfs enlarged", (a) => {
    const o = [...a];
    o[optIdx(o, "--tmpfs", "/c4-out") - 1] = String(64 * MiB);
    return o;
  }, "unsized-tmpfs"],
  ["--size followed by a bind", (a) => spliceBeforeDashDash(a, ["--size", "1", "--ro-bind", "/app", "/app"]), "unsized-tmpfs"],
  ["trailing --size", (a) => spliceBeforeDashDash(a, ["--size", "1"]), "unsized-tmpfs"],
  ["--new-session removed", (a) => a.filter((x) => x !== "--new-session"), "missing-flag"],
  ["--die-with-parent removed", (a) => a.filter((x) => x !== "--die-with-parent"), "missing-flag"],
  ["--chdir /", (a) => a.map((x, j) => (a[j - 1] === "--chdir" ? "/" : x)), "chdir"],
  ["--json-status-fd 4", (a) => a.map((x, j) => (a[j - 1] === "--json-status-fd" ? "4" : x)), "status-fd"],
  ["no `--`", (a) => a.slice(0, a.indexOf("--", BW)), "no-dashdash"],
];

describe("Guard 1 — likec4 child launch, mount, env and namespace closure", () => {
  it("the observed production-shaped spawn passes the checker (must-PASS baseline), with exact spawn options", async () => {
    const { res, cmd, args, opts, stageDir } = await observe();
    expect(res.ok).toBe(true);
    const c = checkSandboxArgv(cmd, args, { stageDir, root: ROOT });
    expect(c.code).toBe("ok");
    expect(c.parsed).toBeGreaterThanOrEqual(25);
    // Exact options: no shell, no detached, cwd = stage, bwrap's own env is the
    // allow-list with HOME = stage (it never sees a server secret).
    const env: Record<string, string> = { HOME: stageDir };
    for (const k of ["PATH", "LANG", "LC_ALL", "TMPDIR"]) if (process.env[k] !== undefined) env[k] = process.env[k]!;
    expect(opts).toEqual({ cwd: stageDir, env, stdio: ["ignore", "pipe", "pipe", "pipe"] });
    expect(stageDir.startsWith(`${ROOT}/c4-render-`)).toBe(true);
  });

  it("the scripts are the pinned static strings, and no path reaches them except as $0/$1 or \"$@\"", async () => {
    const mod = await load();
    expect(mod.CLOSE_FDS_SCRIPT).toBe(CLOSE_FDS);
    expect(mod.RENDER_SCRIPT).toBe(RENDER_SH);
    for (const s of [mod.CLOSE_FDS_SCRIPT, mod.RENDER_SCRIPT]) {
      expect(s).not.toContain(NODE);
      expect(s).not.toContain(LIKEC4_ENTRY);
      expect(s).not.toContain(ROOT);
    }
  });

  for (const [name, mutate, code] of ROWS) {
    it(`row: ${name} → ${code}`, async () => {
      const { cmd, args, stageDir } = await observe();
      const mutated = mutate(args, stageDir);
      const mcmd = name === "cmd is not bash" ? "/usr/bin/choom" : cmd;
      // The mutation landed.
      expect(mcmd !== cmd || mutated.join("\0") !== args.join("\0")).toBe(true);
      expect(checkSandboxArgv(mcmd, mutated, { stageDir, root: ROOT }).code).toBe(code);
    });
  }

  it("row: a stage outside the staging root → source-mismatch", async () => {
    const { cmd, args, stageDir } = await observe();
    expect(checkSandboxArgv(cmd, args, { stageDir, root: "/elsewhere" }).code).toBe("source-mismatch");
  });

  it("row: reading the argv AFTER `--` parses nothing → too-few-options (the checker's own dispatch)", async () => {
    const { cmd, args, stageDir } = await observe();
    const onlyTail = [...args.slice(0, BW), "--", ...args.slice(args.indexOf("--", BW) + 1)];
    expect(checkSandboxArgv(cmd, onlyTail, { stageDir, root: ROOT }).code).toBe("too-few-options");
  });

  it("meta: every return code of the checker has a row", () => {
    const codes = new Set([...checkSandboxArgv.toString().matchAll(/r\("([a-z-]+)"\)/g)].map((m) => m[1]));
    const covered = new Set([...ROWS.map((r) => r[2]), "source-mismatch", "too-few-options", "ok"]);
    expect(codes.size).toBeGreaterThan(10);
    expect([...codes].filter((c) => !covered.has(c))).toEqual([]);
  });

  it("production: a launcher, node or bwrap resolving outside /usr never spawns", async () => {
    vi.stubEnv("NODE_ENV", "production");
    REALPATHS.set(process.execPath, "/opt/node/bin/node");
    let mod = await load();
    expect(await mod.renderC4Model(STAGE)).toMatchObject({ ok: false, reason: "sandbox_error", detail: "binary outside /usr", detailClass: "outside-usr" });

    REALPATHS.set(process.execPath, NODE);
    REALPATHS.set("/usr/bin/bwrap", "/opt/evil/bwrap");
    mod = await load();
    expect(await mod.renderC4Model(STAGE)).toMatchObject({ ok: false, reason: "sandbox_error", detail: "binary outside /usr" });

    REALPATHS.set("/usr/bin/bwrap", "/usr/bin/bwrap");
    REALPATHS.delete("/usr/bin/nice");
    mod = await load();
    expect(await mod.renderC4Model(STAGE)).toMatchObject({ ok: false, reason: "sandbox_error", detailClass: "launcher-enoent" });
    expect(spawnMock).not.toHaveBeenCalled();
  });

  it("an install prefix too shallow to bind (would be `/`) refuses to render, in any environment", async () => {
    REALPATHS.set(process.execPath, "/node/node");
    const mod = await load();
    expect(await mod.renderC4Model(STAGE)).toMatchObject({ ok: false, reason: "sandbox_error", detailClass: "not-resolvable" });
    expect(spawnMock).not.toHaveBeenCalled();
    expect(mod.installPrefixBinds("/x/node", "/usr/local/lib/node_modules/likec4/bin/likec4.mjs")).toBeNull();
    expect(mod.installPrefixBinds("/opt/n/bin/node", "/opt/n/lib/node_modules/likec4/bin/likec4.mjs")).toEqual(["/opt/n"]);
  });

  it("binaries are resolved lazily and only a successful resolution is memoized", async () => {
    fsMock.realpath.mockReset().mockRejectedValue(new Error("EACCES"));
    const mod = await load();
    expect(fsMock.realpath).not.toHaveBeenCalled();
    expect(await mod.renderC4Model(STAGE)).toMatchObject({ ok: false, reason: "sandbox_error", detail: "likec4 not resolvable", detailClass: "not-resolvable" });
    expect(spawnMock).not.toHaveBeenCalled();
    fsMock.realpath.mockReset().mockImplementation(async (p: string) => REALPATHS.get(String(p)) ?? Promise.reject(new Error("ENOENT")));
    okChild();
    expect((await mod.renderC4Model(STAGE)).ok).toBe(true);
    expect(spawnMock).toHaveBeenCalledTimes(1);
  });

  it("H1: a forbidden bind in the LAST option position before `--` is still caught", async () => {
    const { cmd, args, stageDir } = await observe();
    const dd = args.indexOf("--", BW);
    const mutated = [...args.slice(0, dd), "--ro-bind", "/app", "/app", ...args.slice(dd)];
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

  it("H3: outside production an extra --ro-bind p p (hosted-toolcache node) passes; a moved destination does not", async () => {
    const TOOL = "/opt/hostedtoolcache/node/22/x64";
    REALPATHS.set(process.execPath, `${TOOL}/bin/node`);
    REALPATHS.set(LIKEC4_LINK, `${TOOL}/lib/node_modules/likec4/bin/likec4.mjs`);
    const { cmd, args, stageDir } = await observe();
    const ctx = {
      stageDir,
      root: ROOT,
      extra: [TOOL],
      nodeDir: `${TOOL}/bin`,
      tail: renderTail(`${TOOL}/bin/node`, `${TOOL}/lib/node_modules/likec4/bin/likec4.mjs`),
    };
    expect(checkSandboxArgv(cmd, args, ctx).code).toBe("ok");
    const moved = [...args];
    moved[optIdx(moved, "--ro-bind", TOOL, TOOL) + 2] = "/opt/elsewhere";
    expect(checkSandboxArgv(cmd, moved, ctx).code).toBe("extra-destination");
  });
});

describe("Guard 3 — no unsandboxed spawn in production", () => {
  it("row 1: a missing launcher fails closed — exactly one spawn, sandbox_error, no direct retry", async () => {
    const mod = await load();
    const child = makeChild();
    spawnMock.mockImplementation(() => {
      queueMicrotask(() => child.emit("error", Object.assign(new Error("spawn /usr/bin/bash ENOENT"), { code: "ENOENT" })));
      return child;
    });
    const res = await mod.renderC4Model(STAGE);
    expect(spawnMock).toHaveBeenCalledTimes(1);
    expect(spawnMock.mock.calls[0][0]).toBe("/usr/bin/bash");
    expect(res).toMatchObject({ ok: false, reason: "sandbox_error", detailClass: "launcher-enoent" });
  });

  it("row 2: C4_RENDER_SANDBOX=off is ignored in production", async () => {
    vi.stubEnv("NODE_ENV", "production");
    vi.stubEnv("C4_RENDER_SANDBOX", "off");
    const { cmd, args } = await observe();
    expect(cmd).toBe("/usr/bin/bash");
    expect(args).toContain("/usr/bin/bwrap");
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
    expect(await mod.renderC4Model(STAGE)).toMatchObject({ ok: false, reason: "sandbox_error", detailClass: "bwrap-setup" });
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
    expect(await mod.renderC4Model(STAGE)).toMatchObject({ ok: false, reason: "non_zero_exit", detailClass: "likec4-exit" });
  });

  it("a kill by a signal we did not send (e.g. the OOM killer) is classed `killed`", async () => {
    const mod = await load();
    const child = makeChild();
    spawnMock.mockImplementation(() => {
      queueMicrotask(() => child.emit("close", null, "SIGKILL"));
      return child;
    });
    expect(await mod.renderC4Model(STAGE)).toMatchObject({ ok: false, reason: "non_zero_exit", detailClass: "killed" });
  });

  it("harness: NODE_ENV=test + C4_RENDER_SANDBOX=off spawns node directly, still with --no-use-dot", async () => {
    vi.stubEnv("C4_RENDER_SANDBOX", "off");
    const mod = await load();
    fsMock.open.mockImplementation(async () => ({
      stat: async () => ({ isFile: () => true, size: VALID_MODEL.length }),
      readFile: async () => VALID_MODEL,
      close: async () => {},
    }));
    const child = makeChild();
    spawnMock.mockImplementation(() => {
      queueMicrotask(() => child.emit("close", 0, null));
      return child;
    });
    expect((await mod.renderC4Model(STAGE)).ok).toBe(true);
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
    const observed = new Set(args.slice(BW, args.indexOf("--", BW)).filter((a) => a.startsWith("--unshare-")));
    expect([...observed].sort()).toEqual([...fixtureSet, "--unshare-ipc", "--unshare-uts"].sort());
  });
});

describe("output transport — stdout is the trust boundary", () => {
  it("stdout beyond RAW_MODEL_READ_CAP kills the sandbox and is rejected, never buffered whole", async () => {
    const mod = await load();
    const child = makeChild();
    const chunk = Buffer.alloc(1024 * 1024, 0x7b);
    spawnMock.mockImplementation(() => {
      queueMicrotask(() => {
        for (let k = 0; k <= mod.RAW_MODEL_READ_CAP / chunk.length; k++) child.stdout.emit("data", chunk);
        status(child, '{ "exit-code": 0 }\n');
        child.emit("close", 0, null);
      });
      return child;
    });
    expect(await mod.renderC4Model(STAGE)).toMatchObject({ ok: false, reason: "io_error", detail: "model output rejected: exceeds cap", detailClass: "output-rejected" });
    expect(child.kill).toHaveBeenCalledWith("SIGKILL");
  });

  it("an empty stdout on exit 0 is rejected", async () => {
    const mod = await load();
    okChild("");
    expect(await mod.renderC4Model(STAGE)).toMatchObject({ ok: false, reason: "io_error", detail: "model output rejected: empty", detailClass: "output-rejected" });
  });
});

describe("render pool, stderr cap and the timeout path", () => {
  it("the pool is shared across two module instances; a waiter is still pending just before SLOT_WAIT_MS and gives up after it", async () => {
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
    vi.resetModules();
    const b = await import("@/server/c4-render");
    expect(b).not.toBe(a);
    let settled = false;
    const waiting = b.renderC4Model(STAGE).then((r) => {
      settled = true;
      return r;
    });
    await vi.advanceTimersByTimeAsync(b.SLOT_WAIT_MS - 1);
    expect(settled).toBe(false);
    await vi.advanceTimersByTimeAsync(2);
    expect(await waiting).toMatchObject({ ok: false, reason: "timeout", detail: b.RENDER_SLOT_WAIT_DETAIL, detailClass: "slot-wait" });
    expect(spawnMock).toHaveBeenCalledTimes(2);
    for (const c of held) {
      c.stdout.emit("data", Buffer.from(VALID_MODEL));
      status(c, '{ "exit-code": 0 }\n');
      c.emit("close", 0, null);
    }
    await Promise.all(running);
    const pool = (globalThis as Record<symbol, { inFlight: number; waiters: unknown[] }>)[POOL_KEY];
    expect(pool.inFlight).toBe(0);
    expect(pool.waiters).toHaveLength(0);
  });

  it("a freed slot is handed to the next waiter, which then renders", async () => {
    const mod = await load();
    const held: FakeChild[] = [];
    spawnMock.mockImplementation(() => {
      const c = makeChild();
      held.push(c);
      return c;
    });
    const first = [mod.renderC4Model(STAGE), mod.renderC4Model(STAGE)];
    await vi.waitFor(() => expect(spawnMock).toHaveBeenCalledTimes(2));
    const third = mod.renderC4Model(STAGE);
    await new Promise((r) => setTimeout(r, 20));
    expect(spawnMock).toHaveBeenCalledTimes(2);
    const close = (c: FakeChild) => {
      c.stdout.emit("data", Buffer.from(VALID_MODEL));
      status(c, '{ "exit-code": 0 }\n');
      c.emit("close", 0, null);
    };
    close(held[0]);
    await vi.waitFor(() => expect(spawnMock).toHaveBeenCalledTimes(3));
    close(held[2]);
    expect((await third).ok).toBe(true);
    close(held[1]);
    await Promise.all(first);
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
    expect(await p).toMatchObject({ ok: false, reason: "timeout", detailClass: "spawn-timeout" });
    expect(order).toEqual(["kill", "close", "rm"]);
  });

  it("timeout: a sandbox that never exits keeps its stage AND its slot until it does; the stale sweep leaves it alone", async () => {
    vi.useFakeTimers();
    const mod = await load();
    const child = makeChild();
    spawnMock.mockImplementationOnce(() => child);
    const p = mod.renderC4Model(STAGE);
    await vi.advanceTimersByTimeAsync(25_001);
    await vi.advanceTimersByTimeAsync(5_001);
    await vi.advanceTimersByTimeAsync(3_000);
    expect(await p).toMatchObject({ ok: false, reason: "sandbox_error", detail: "sandbox did not exit", detailClass: "sandbox-no-exit" });
    const stageDir = String(await fsMock.mkdtemp.mock.results[0].value);
    const removed = () => fsMock.rm.mock.calls.some((c) => String(c[0]) === stageDir);
    expect(removed()).toBe(false);
    const pool = () => (globalThis as Record<symbol, { inFlight: number }>)[POOL_KEY];
    expect(pool().inFlight).toBe(1);
    // A later render's sweep sees the kept stage as 11 min old and skips it.
    const base = stageDir.slice(stageDir.lastIndexOf("/") + 1);
    fsMock.readdir.mockImplementation(async (d: string) =>
      String(d).endsWith("/src")
        ? [{ name: "model.c4", isDirectory: () => false, isFile: () => true }]
        : [{ name: base, isDirectory: () => true, isFile: () => false }],
    );
    fsMock.lstat.mockImplementation(async () => ({
      isDirectory: () => true,
      isSymbolicLink: () => false,
      uid: typeof process.getuid === "function" ? process.getuid() : 0,
      mtimeMs: Date.now() - 11 * 60_000,
    }));
    okChild();
    expect((await mod.renderC4Model(STAGE)).ok).toBe(true);
    expect(removed()).toBe(false);
    // The late exit runs what was deferred: the slot release and the removal.
    child.emit("close", null, "SIGKILL");
    await vi.advanceTimersByTimeAsync(1);
    expect(removed()).toBe(true);
    expect(pool().inFlight).toBe(0);
  });
});

describe("boot self-probe", () => {
  it("renders a real fixture through the one spawn site and emits the Sentry info event", async () => {
    const mod = await load();
    okChild();
    await mod.verifyC4RenderSandboxOnce();
    expect(spawnMock).toHaveBeenCalledTimes(1);
    expect(spawnMock.mock.calls[0][0]).toBe("/usr/bin/bash");
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

  it("a failed probe render reports via reportSilentFallback(null, …) with the class in the message", async () => {
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
      message: "c4 render sandbox self-probe failed: sandbox_error/bwrap-setup",
      tags: { reason: "sandbox_error", detail_class: "bwrap-setup" },
    });
    expect(sentry.captureMessage).not.toHaveBeenCalled();
  });

  it("reports inheritable (non-CLOEXEC) fds of every kind, by count and kind only", async () => {
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
    expect(opts).toMatchObject({ op: "sandbox-selfprobe-fds", extra: { count: 2, kinds: { path: 1, other: 1 } } });
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
