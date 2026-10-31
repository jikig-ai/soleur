// Guards 1, 2 and 4 of the production-HOME census (Ref #10455): the emit allowlist over the REAL
// serialized output of every sink, the filesystem-call limit, and the positive control / canary.
// Every fixture is synthesized (cq-test-fixtures-synthesized-only): no test scans a real HOME.
// The allowlist below is deliberately written HERE and not imported from the module, so the test
// cannot certify itself (learning 2026-09-14-a-registry-that-carries-its-own-hash-certifies-itself).
import { spawnSync } from "node:child_process";
import { readFileSync, mkdtempSync, mkdirSync, writeFileSync, rmSync, readdirSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { afterAll, afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import * as Sentry from "@sentry/nextjs";

import {
  CLASS_IDS,
  SUNSET_UTC,
  TRIGGER_CLASSES,
  bucketCount,
  defaultCensusDeps,
  handleHomeCensus,
  resolveRoots,
  scanHome,
  uptimeBucket,
  type CensusDeps,
  type CensusFs,
} from "@/server/home-census";
import { HOME_SESSION_DIRS, HOME_STATE_FILES } from "@/server/agent-outer-wrap";
import { scrubSentryEvent } from "@/server/sentry-scrub";

// ---------------------------------------------------------------------------------------------
// Synthesized in-memory filesystem. Records every call so a test can assert what was (not) touched.
// ---------------------------------------------------------------------------------------------
type Node =
  | { t: "dir"; mode?: number }
  | { t: "file"; mode?: number }
  | { t: "link"; mode?: number }
  | { t: "eacces" };

const CANARY_PATH = "/home/canary-tenant/.claude/projects/canary-secret-workspace-0000/transcript-canary.jsonl";

function memFs(nodes: Record<string, Node>, calls: string[] = []): CensusFs & { calls: string[] } {
  const kids = (dir: string) =>
    Object.keys(nodes)
      .filter((p) => p.startsWith(dir + "/") && !p.slice(dir.length + 1).includes("/"))
      .map((p) => p.slice(dir.length + 1));
  const enoent = () => Object.assign(new Error(`ENOENT: no such file or directory, lstat '${CANARY_PATH}'`), { code: "ENOENT" });
  const eacces = () => Object.assign(new Error(`EACCES: permission denied, scandir '${CANARY_PATH}'`), { code: "EACCES" });
  return {
    calls,
    async lstat(p: string) {
      calls.push(`lstat ${p}`);
      const n = nodes[p];
      if (!n) throw enoent();
      const mode = n.t === "eacces" ? 0o040700 : (n.mode ?? (n.t === "dir" ? 0o700 : 0o600));
      return {
        mode,
        dev: 1,
        ino: Object.keys(nodes).indexOf(p) + 1,
        isDirectory: () => n.t === "dir" || n.t === "eacces",
        isSymbolicLink: () => n.t === "link",
      };
    },
    async opendir(p: string) {
      calls.push(`opendir ${p}`);
      const n = nodes[p];
      if (!n) throw enoent();
      if (n.t === "eacces") throw eacces();
      const names = kids(p);
      let i = 0;
      return {
        async read() {
          return i < names.length ? { name: names[i++] } : null;
        },
        async close() {},
      };
    },
  };
}

const f = (mode = 0o600): Node => ({ t: "file", mode });
const d = (): Node => ({ t: "dir" });

/** A synthesized HOME with a DIFFERENT count in every class so a swap of two classes cannot hide. */
function homeTree(root = "/home/t"): Record<string, Node> {
  const n: Record<string, Node> = { "/home": d(), [root]: d(), [`${root}/.claude`]: d(), [`${root}/.claude.json`]: f(0o644) };
  const dirs: Record<string, number> = { debug: 3, todos: 2, tasks: 5, "shell-snapshots": 4, backups: 6, statsig: 7, "file-history": 1, history: 8 };
  for (const [name, count] of Object.entries(dirs)) {
    n[`${root}/.claude/${name}`] = d();
    for (let i = 0; i < count; i++) n[`${root}/.claude/${name}/canary-file-${name}-${i}`] = f(i === 0 ? 0o640 : 0o600);
  }
  n[`${root}/.claude/history.jsonl`] = f(0o644);
  n[`${root}/.claude/.last-cleanup`] = f();
  n[`${root}/.claude/projects`] = d();
  n[`${root}/.claude/projects/canary-slug-a`] = d();
  n[`${root}/.claude/projects/canary-slug-a/t1.jsonl`] = f();
  n[`${root}/.claude/projects/canary-slug-a/t2.jsonl`] = f();
  n[`${root}/.claude/projects/canary-slug-b`] = d();
  n[`${root}/.claude/projects/canary-slug-b/t3.jsonl`] = f();
  n[`${root}/.claude/sessions`] = d();
  n[`${root}/.claude/sessions/101.json`] = f();
  n[`${root}/.claude/sessions/102.json`] = f();
  n[`${root}/.claude/sessions/101.abc.key`] = f(0o644);
  n[`${root}/.claude/unlisted-canary-entry`] = f();
  return n;
}

const ROOT = (path = "/home/t") => [{ label: "env_home" as const, path }];
const scanOpts = (fs: CensusFs, over: Record<string, unknown> = {}) => ({
  fs,
  roots: ROOT(),
  entryCap: 20_000,
  timeCapMs: 20_000,
  yieldFn: async () => {},
  loadShed: () => false,
  ...over,
});

// ---------------------------------------------------------------------------------------------
describe("bucketing and evidence", () => {
  it("buckets exactly; zero is exact", () => {
    const table: Array<[number, string]> = [[0, "0"], [1, "1-4"], [4, "1-4"], [5, "5-19"], [19, "5-19"], [20, "20-99"], [99, "20-99"], [100, "100-999"], [999, "100-999"], [1000, "1000+"], [10 ** 6, "1000+"]];
    for (const [n, b] of table) expect(bucketCount(n), String(n)).toBe(b);
  });
  it("uptime bucket boundaries", () => {
    expect(uptimeBucket(0)).toBe("lt_1h");
    expect(uptimeBucket(3599)).toBe("lt_1h");
    expect(uptimeBucket(3600)).toBe("lt_24h");
    expect(uptimeBucket(86_399)).toBe("lt_24h");
    expect(uptimeBucket(86_400)).toBe("lt_7d");
    expect(uptimeBucket(604_799)).toBe("lt_7d");
    expect(uptimeBucket(604_800)).toBe("ge_7d");
  });
});

describe("roots", () => {
  const nohome = () => {
    throw new Error("no home");
  };
  it("accepts HOME only under /home/ or /root, skips anything wider", () => {
    for (const bad of ["/", "/workspaces/w1", "/tmp/.cs", "relative/home", "/home", "/home/../etc", "/rootkit"]) {
      const r = resolveRoots({ HOME: bad }, nohome);
      expect(r.roots.map((x) => x.label), bad).not.toContain("env_home");
    }
    expect(resolveRoots({ HOME: "/home/u1" }, nohome).roots.map((x) => x.path)).toContain("/home/u1");
    expect(resolveRoots({ HOME: "/root" }, nohome).roots.map((x) => x.label)).toContain("env_home");
  });
  it("keeps the earliest label for a duplicate and reports roots_distinct", () => {
    const r = resolveRoots({ HOME: "/home/soleur" }, nohome);
    expect(r.roots.filter((x) => x.path === "/home/soleur")).toHaveLength(1);
    expect(r.roots[0].label).toBe("env_home");
    expect(r.rootsDistinct).toBe(false);
  });
  it("survives an unavailable os.homedir()", () => {
    const r = resolveRoots({}, nohome);
    expect(r.roots.map((x) => x.label)).toEqual(["home_soleur", "root"]);
    expect(r.rootsNote).toBe("homedir_unavailable");
  });
});

// ---------------------------------------------------------------------------------------------
describe("scanner: synthesized HOME known answers", () => {
  it("counts exactly per class", async () => {
    const fs = memFs(homeTree());
    const { scan } = await scanHome(scanOpts(fs));
    const e = (c: string) => scan.classes[c as keyof typeof scan.classes].entries;
    expect(e("history_jsonl")).toBe(1);
    expect(e("debug")).toBe(3);
    expect(e("todos")).toBe(2);
    expect(e("tasks")).toBe(5);
    expect(e("shell_snapshots")).toBe(4);
    expect(e("backups")).toBe(6);
    expect(e("statsig")).toBe(7);
    expect(e("file_history")).toBe(1);
    expect(e("history_dir")).toBe(8);
    expect(e("projects")).toBe(3); // depth-2 transcripts only, the slug directories themselves are not counted
    expect(e("sessions_json")).toBe(2);
    expect(e("sessions_key")).toBe(1);
    expect(e("account_state")).toBe(1);
    expect(e("last_cleanup")).toBe(1);
    expect(e("other_under_claude")).toBe(1);
    expect(scan.classes.debug.groupR).toBe(1); // one 0o640 file
    expect(scan.classes.history_jsonl.otherR).toBe(1);
    expect(scan.truncated).toBe(false);
    for (const c of CLASS_IDS) expect(scan.classes[c].visited, `${c} visited`).toBe(true);
  });

  it("an empty tree reports absent zeros that are still visited", async () => {
    const fs = memFs({ "/home": d(), "/home/t": d() });
    const { scan } = await scanHome(scanOpts(fs));
    for (const c of CLASS_IDS) {
      expect(scan.classes[c].entries).toBe(0);
      expect(scan.classes[c].absent).toBe(true);
      expect(scan.classes[c].visited).toBe(true);
    }
  });

  it("scans the four trigger classes first", async () => {
    const fs = memFs(homeTree());
    await scanHome(scanOpts(fs));
    const firstOpens = fs.calls.filter((c) => c.startsWith("opendir ") && c !== "opendir /home/t").map((c) => c.split("/").pop());
    expect(firstOpens.slice(0, 3)).toEqual(["debug", "todos", "tasks"]);
  });

  it("a symlink is counted and never opened; a symlinked class directory is never opened", async () => {
    const tree = homeTree();
    tree["/home/t/.claude/todos"] = { t: "link" };
    for (const k of Object.keys(tree)) if (k.startsWith("/home/t/.claude/todos/")) delete tree[k];
    tree["/home/t/.claude/debug/canary-link"] = { t: "link" };
    const fs = memFs(tree);
    const { scan } = await scanHome(scanOpts(fs));
    expect(scan.classes.todos.symlink).toBe(1);
    expect(scan.classes.todos.entries).toBe(0);
    expect(fs.calls.filter((c) => c === "opendir /home/t/.claude/todos")).toHaveLength(0);
    expect(scan.classes.debug.symlink).toBe(1);
    expect(scan.classes.debug.entries).toBe(4);
  });

  it("an EACCES directory counts as an error and the class is unknown, not zero", async () => {
    const tree = homeTree();
    tree["/home/t/.claude/tasks"] = { t: "eacces" };
    for (const k of Object.keys(tree)) if (k.startsWith("/home/t/.claude/tasks/")) delete tree[k];
    const { scan } = await scanHome(scanOpts(memFs(tree)));
    expect(scan.classes.tasks.errors).toBe(1);
    expect(scan.classes.debug.errors).toBe(0);
  });

  it("detects a directory swapped for another inode between lstat and opendir", async () => {
    const tree = homeTree();
    const base = memFs(tree);
    let n = 0;
    const fs: CensusFs = {
      opendir: base.opendir,
      async lstat(p: string) {
        const st = await base.lstat(p);
        if (p === "/home/t/.claude/debug" && ++n === 2) return { ...st, ino: 99_999 };
        return st;
      },
    };
    const { scan } = await scanHome(scanOpts(fs));
    expect(scan.classes.debug.errors).toBe(1);
    expect(scan.classes.debug.entries).toBe(0);
  });

  it("an entry cap truncates, names the reason, and later classes are not visited", async () => {
    const { scan } = await scanHome(scanOpts(memFs(homeTree()), { entryCap: 5 }));
    expect(scan.truncated).toBe(true);
    expect(scan.reason).toBe("entry_cap");
    expect(CLASS_IDS.some((c) => !scan.classes[c].visited)).toBe(true);
  });

  it("a load-shed signal stops the scan with its own reason", async () => {
    const { scan } = await scanHome(scanOpts(memFs(homeTree()), { loadShed: () => true, yieldEvery: 1 }));
    expect(scan.truncated).toBe(true);
    expect(scan.reason).toBe("load_shed");
  });

  it("the time cap fires on a stalled filesystem and the abandoned op never reaches a sink", async () => {
    vi.useFakeTimers();
    try {
      const unhandled: unknown[] = [];
      const onUnhandled = (e: unknown) => unhandled.push(e);
      process.on("unhandledRejection", onUnhandled);
      let rejectOrphan: (e: Error) => void = () => {};
      const stalled: CensusFs = {
        lstat: () => new Promise((_, rej) => (rejectOrphan = rej)),
        opendir: async () => {
          throw new Error("unused");
        },
      };
      const pending = scanHome(scanOpts(stalled, { timeCapMs: 20_000 }));
      await vi.advanceTimersByTimeAsync(20_001);
      const { scan, settled } = await pending;
      expect(scan.truncated).toBe(true);
      expect(scan.reason).toBe("time_cap");
      let settledFlag = false;
      void settled.then(() => (settledFlag = true));
      await vi.advanceTimersByTimeAsync(10);
      expect(settledFlag).toBe(false); // the orphan is still pending: the in-flight flag must stay held
      rejectOrphan(Object.assign(new Error(`ENOENT lstat '${CANARY_PATH}'`), { code: "ENOENT" }));
      await vi.advanceTimersByTimeAsync(10);
      expect(settledFlag).toBe(true);
      vi.useRealTimers(); // setImmediate is faked: a real turn of the event loop is needed to observe an unhandled rejection
      await new Promise<void>((r) => setImmediate(r));
      process.off("unhandledRejection", onUnhandled);
      expect(unhandled).toEqual([]);
      expect(JSON.stringify(scan)).not.toContain("canary");
    } finally {
      vi.useRealTimers();
    }
  });
});

// ---------------------------------------------------------------------------------------------
// Guard 2: the census code can only lstat and opendir/read.
// ---------------------------------------------------------------------------------------------
describe("filesystem-call limit (import forms)", () => {
  const stripComments = (s: string) => s.replace(/\/\*[\s\S]*?\*\//g, "").replace(/(^|[^:\\])\/\/.*$/gm, "$1");
  // Closed-set: the module may import EXACTLY {lstat, opendir} from node:fs/promises, nothing else from any fs-like or process-like module,
  // and may not load code any other way (require, createRequire, process.binding, dynamic import).
  const FS_SPEC = /^(?:node:)?(?:graceful-)?fs(?:[-/].*)?$/;
  const PROC_SPEC = /^(?:node:)?(?:child_process|worker_threads|vm|net|http|https|http2|dgram|cluster|tls)$/;
  const MODULES = ["server/home-census.ts"].map((p) => resolve(__dirname, "../..", p));

  function scanModule(path: string): string[] {
    const src = stripComments(readFileSync(path, "utf8"));
    const bad: string[] = [];
    if (/\brequire\s*\(|\bcreateRequire\b|\bprocess\s*\.\s*(?:binding|dlopen|getBuiltinModule)\b|\bmodule\s*\.\s*require\b/.test(src)) bad.push("require-style load");
    if (/\bimport\s*\(/.test(src)) bad.push("dynamic import");
    for (const m of src.matchAll(/\bimport\s*["']([^"']+)["']/g)) {
      if (FS_SPEC.test(m[1]) || PROC_SPEC.test(m[1])) bad.push(`side-effect import of ${m[1]}`);
    }
    for (const m of src.matchAll(/\b(import|export)\b([^;]*?)\bfrom\s*["']([^"']+)["']/g)) {
      const [, kind, clause, spec] = m;
      if (PROC_SPEC.test(spec)) bad.push(`${kind} from ${spec}`);
      if (!FS_SPEC.test(spec)) continue;
      const braces = /^\s*(?:type\s+)?\{([^}]*)\}\s*$/.exec(clause);
      if (kind !== "import" || spec !== "node:fs/promises" || !braces) {
        bad.push(`${kind} of ${spec} outside the closed form`);
        continue;
      }
      for (const n of braces[1].split(",").map((x) => x.trim().split(/\s+as\s+/)[0]).filter(Boolean)) {
        if (!["lstat", "opendir"].includes(n)) bad.push(`fs import of ${n}`);
      }
    }
    for (const m of src.matchAll(/\bfs\.(\w+)/g)) if (!["lstat", "opendir"].includes(m[1])) bad.push(`fs.${m[1]}`);
    for (const m of src.matchAll(/\b(?:dir|d)\.(\w+)\(/g)) if (!["read", "close"].includes(m[1])) bad.push(`dir.${m[1]}`);
    return bad;
  }

  it("scans at least one module (floor) and finds no forbidden form", () => {
    expect(MODULES.length).toBeGreaterThanOrEqual(1);
    for (const m of MODULES) expect(scanModule(m), m).toEqual([]);
  });

  it("the detector itself catches each forbidden form (instrument control)", () => {
    const dir = mkdtempSync(join(tmpdir(), "home-census-import-"));
    try {
      const cases: Array<[string, string]> = [
        ["import { readFile } from 'node:fs/promises';", "fs import of readFile"],
        ["import { lstat, readlink } from 'node:fs/promises';", "fs import of readlink"],
        ["import { stat } from 'fs';", "import of fs outside the closed form"],
        ["import { exec } from 'child_process';", "import from child_process"],
        ["const x = await import('node:fs');", "dynamic import"],
        ["const x = await import(name);", "dynamic import"],
        ["import * as fs from 'node:fs';", "outside the closed form"],
        ["import fs, { lstat } from 'node:fs/promises';", "outside the closed form"],
        ["export { readFile } from 'node:fs/promises';", "export of node:fs/promises outside the closed form"],
        ["export * from 'node:fs';", "export of node:fs outside the closed form"],
        ["const fs = require('node:fs');", "require-style load"],
        ["const r = createRequire(import.meta.url);", "require-style load"],
        ["process.binding('fs');", "require-style load"],
        ["import 'node:fs';", "side-effect import of node:fs"],
        ["import x from 'fs-extra';", "outside the closed form"],
        ["opts.fs.readFile(p);", "fs.readFile"],
        ["fs.promises.readFile(p);", "fs.promises"],
        ["dir.readSync();", "dir.readSync"],
        ["for await (const e of d.entries()) {}", "dir.entries"],
      ];
      for (const [i, [src, expected]] of cases.entries()) {
        const p = join(dir, `m${i}.ts`);
        writeFileSync(p, src);
        expect(scanModule(p).join("|"), src).toContain(expected);
      }
      const ok = join(dir, "ok.ts");
      writeFileSync(ok, "// readFile in a comment is fine\nimport { lstat as a, opendir as b } from 'node:fs/promises';\n/* readlink */\nopts.fs.lstat(p); fs.opendir(q); dir.read(); d.close();");
      expect(scanModule(ok)).toEqual([]);
      expect(() => scanModule(join(dir, "does-not-exist.ts"))).toThrow();
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });

  it("dry_run touches the real filesystem zero times", async () => {
    const calls: string[] = [];
    const spyFs = memFs({}, calls);
    const { deps } = makeDeps({ fs: spyFs });
    const res = await handleHomeCensus(post({ run_id: 1, mode: "dry_run" }), deps);
    expect(res.status).toBe(200);
    expect(calls).toEqual([]);
  });
});

// ---------------------------------------------------------------------------------------------
// The independent allowlist (Guard 1).
// ---------------------------------------------------------------------------------------------
const ALLOWED_STRINGS = new Set([
  ...["0", "1-4", "5-19", "20-99", "100-999", "1000+"],
  ...["dry_run", "real", "synthetic", "container_home", "passed", "failed", "young", "mature"],
  ...["lt_1h", "lt_24h", "lt_7d", "ge_7d", "none", "entry_cap", "time_cap", "load_shed", "class_budget"],
  ...["non_atomic", "file_mode_only_not_reachability", "unmeasured", "true", "false", "unknown"],
  ...["none_counted", "counted", "inconclusive"],
  ...["env_home", "home_soleur", "root"],
  ...["env_home_rejected", "homedir_unavailable"],
  ...["unavailable", "unauthorized", "sunset", "payload_too_large", "invalid_json", "invalid_body", "invalid_mode", "build_mismatch", "young_container", "busy", "rate_limited", "control_failed", "internal"],
  ...["ok", "truncated", "refused"],
  "counted in this container's writable layer at the run; not a statement about earlier containers, other hosts, or any time before or after the run",
  ...CLASS_IDS,
]);
const CLASS_ENTRY_KEYS = ["absent", "class", "class_result", "errors", "n_entries", "n_mode_bits_group_r", "n_mode_bits_other_r", "n_symlink"];
const ROOT_ENTRY_KEYS = ["label", "root_listable", "root_present"];
const TOP_KEYS = new Set([
  "schema_version", "ok", "run_id", "mode", "data_source", "build_sha", "control", "evidence", "uptime_bucket", "sunset_utc", "truncated",
  "truncation_reason", "snapshot", "mode_bits_semantics", "interpretation", "claude_config_dir_set", "outer_wrap_cohorts", "roots",
  "roots_distinct", "roots_note", "classes", "activity_witness", "trigger_class_nonzero", "error_class",
]);

function checkAllowlist(value: unknown, where = "$"): string[] {
  const bad: string[] = [];
  if (value === null) return [`${where}: null`];
  if (typeof value === "boolean") return bad;
  if (typeof value === "number") {
    if (!(where === "$.run_id" || where === "$.schema_version")) bad.push(`${where}: raw number ${value}`);
    return bad;
  }
  if (typeof value === "string") {
    if (where === "$.build_sha" && (/^[0-9a-f]{40}$/.test(value) || value === "dev")) return bad;
    if (where === "$.sunset_utc" && value === SUNSET_UTC) return bad;
    if (!ALLOWED_STRINGS.has(value)) bad.push(`${where}: string outside the allowlist: ${JSON.stringify(value).slice(0, 60)}`);
    return bad;
  }
  if (Array.isArray(value)) {
    value.forEach((v, i) => {
      if (where === "$.classes") {
        if (JSON.stringify(Object.keys(v as object).sort()) !== JSON.stringify(CLASS_ENTRY_KEYS)) bad.push(`${where}[${i}]: keys ${Object.keys(v as object)}`);
      }
      if (where === "$.roots") {
        if (JSON.stringify(Object.keys(v as object).sort()) !== JSON.stringify(ROOT_ENTRY_KEYS)) bad.push(`${where}[${i}]: keys ${Object.keys(v as object)}`);
      }
      bad.push(...checkAllowlist(v, `${where}[${i}]`));
    });
    return bad;
  }
  if (typeof value === "object") {
    for (const [k, v] of Object.entries(value as Record<string, unknown>)) {
      if (where === "$" && !TOP_KEYS.has(k)) bad.push(`$.${k}: key outside the allowlist`);
      bad.push(...checkAllowlist(v, `${where}.${k}`));
    }
    return bad;
  }
  return [`${where}: type ${typeof value}`];
}

// ---------------------------------------------------------------------------------------------
// Harness for the handler: injected clock, uptime, caps, fs, canary directory and log destination.
// ---------------------------------------------------------------------------------------------
const SECRET = "home-census-test-secret-value";
const SHA = "a".repeat(40);

function post(body: unknown, auth: string | null = `Bearer ${SECRET}`): Request {
  const headers = new Headers({ "content-type": "application/json" });
  if (auth !== null) headers.set("authorization", auth);
  return new Request("https://app.soleur.ai/api/internal/home-census", {
    method: "POST",
    headers,
    body: typeof body === "string" ? body : JSON.stringify(body),
  });
}

function makeDeps(over: Partial<CensusDeps> = {}) {
  const lines: string[] = [];
  const canaryRoot = mkdtempSync(join(tmpdir(), "home-census-canary-"));
  mkdirSync(join(canaryRoot, "known"));
  writeFileSync(join(canaryRoot, "known", "present"), "x");
  const deps: CensusDeps = {
    fs: memFs(homeTree("/home/soleur")),
    env: { HOME: "/home/soleur", BUILD_SHA: SHA, CLAUDE_CONFIG_DIR: undefined },
    homedir: () => "/home/soleur",
    now: () => Date.parse("2026-11-05T00:00:00Z"),
    uptime: () => 90_000,
    entryCap: 20_000,
    timeCapMs: 20_000,
    yieldFn: async () => {},
    loadShed: () => false,
    canaryDir: join(canaryRoot, "known"),
    canaryFs: undefined,
    logDest: { write: (s: string) => void lines.push(s) },
    ...over,
  };
  return { deps, lines, canaryRoot };
}

const ORIG_SECRET = process.env.INNGEST_MANUAL_TRIGGER_SECRET;
afterAll(async () => {
  await Sentry.close(1000).catch(() => {});
});
beforeEach(() => {
  process.env.INNGEST_MANUAL_TRIGGER_SECRET = SECRET;
});
afterEach(() => {
  if (ORIG_SECRET === undefined) delete process.env.INNGEST_MANUAL_TRIGGER_SECRET;
  else process.env.INNGEST_MANUAL_TRIGGER_SECRET = ORIG_SECRET;
});

function resetState() {
  const g = globalThis as Record<symbol, unknown>;
  delete g[Symbol.for("soleur.homeCensus.inflight")];
  delete g[Symbol.for("soleur.homeCensus.limiter")];
  delete g[Symbol.for("soleur.homeCensus.dryRunSentry")];
}

// ---------------------------------------------------------------------------------------------
// Real Sentry transport capture.
// ---------------------------------------------------------------------------------------------
type Envelope = [Record<string, unknown>, Array<[{ type: string }, Record<string, unknown>]>];

let sink: Envelope[] = [];
let sentryReady = false;
// Initialized ONCE per file: a re-init after Sentry.close() in the same worker captures nothing (the global
// carrier keeps the closed client), which would make every "no event leaked" assertion vacuous.
function ensureSentry() {
  if (sentryReady) return;
  sentryReady = true;
  Sentry.init({
    dsn: "https://public@o0.ingest.sentry.io/0",
    serverName: "canary-host-name-0000",
    tracesSampleRate: 0,
    sendDefaultPii: true,
    release: "web-platform@test+r1",
    transport: () => ({
      send: async (env: unknown) => {
        sink.push(env as Envelope);
        return { statusCode: 200 };
      },
      flush: async () => true,
    }),
    beforeSend: (e) => scrubSentryEvent(e),
    beforeSendTransaction: (e) => scrubSentryEvent(e),
  });
  Sentry.setUser({ id: "canary-user-id-0000", email: "canary@example.invalid", ip_address: "203.0.113.9" });
  Sentry.addBreadcrumb({ message: "canary breadcrumb /home/canary-tenant/secret", category: "canary" });
  Sentry.setTag("canary_tag", "canary-global-tag");
  Sentry.setContext("canary_ctx", { path: CANARY_PATH });
}

async function withRealSentry<T>(fn: (captured: Envelope[]) => Promise<T>): Promise<{ result: T; envelopes: Envelope[] }> {
  ensureSentry();
  sink = [];
  const result = await fn(sink);
  await Sentry.flush(2000);
  return { result, envelopes: sink };
}

const eventsOf = (envs: Envelope[]) => envs.flatMap(([, items]) => items.filter(([h]) => h.type === "event").map(([, p]) => p));
const txOf = (envs: Envelope[]) => envs.flatMap(([, items]) => items.filter(([h]) => h.type === "transaction"));

describe("emit allowlist over the REAL serialized output of every sink", () => {
  beforeEach(resetState);
  it("response, Sentry envelope and pino bytes each carry exactly one allowlisted record (and the canaries never appear)", async () => {
    const { deps, lines } = makeDeps();
    const { result: res, envelopes } = await withRealSentry(async () => handleHomeCensus(post({ run_id: 7, mode: "real", expect_build_sha: SHA, accept_young: false }), deps));
    expect(res.status).toBe(200);
    const text = await res.text();
    const body = JSON.parse(text);

    // Per-sink floor: exactly one of each BEFORE any content check.
    const events = eventsOf(envelopes);
    expect(events).toHaveLength(1);
    expect(lines).toHaveLength(1);
    expect(txOf(envelopes)).toHaveLength(0);

    expect(checkAllowlist(body)).toEqual([]);
    expect(body.classes).toHaveLength(CLASS_IDS.length);

    const pinoLine = JSON.parse(lines[0]);
    expect(pinoLine.level).toBe(40);
    expect(pinoLine.msg).toBe("home-census result");
    expect(pinoLine).not.toHaveProperty("pid");
    expect(pinoLine).not.toHaveProperty("hostname");
    expect(pinoLine).not.toHaveProperty("time");
    expect(pinoLine).not.toHaveProperty("err");
    const { level: _l, msg: _m, outcome, ...pinoRest } = pinoLine;
    void _l; void _m;
    expect(["ok", "truncated", "failed", "young"]).toContain(outcome === "failed" ? "failed" : outcome);
    expect(checkAllowlist(pinoRest)).toEqual([]);

    const ev = events[0] as Record<string, any>;
    // The SDK adds contexts.trace (two random hex ids) AFTER scope processors run; nothing else may be there.
    expect(Object.keys(ev.contexts ?? {})).toEqual(["trace"]);
    expect(Object.keys(ev.contexts.trace).sort()).toEqual(["span_id", "trace_id"]);
    for (const forbidden of ["server_name", "request", "user", "breadcrumbs", "exception", "modules", "spans", "sdkProcessingMetadata"]) {
      expect(ev, `Sentry event key ${forbidden}`).not.toHaveProperty(forbidden);
    }
    expect(ev.message).toBe("home-census result");
    expect(Object.keys(ev.tags ?? {}).sort()).toEqual(["control", "data_source", "evidence", "mode", "run_id", "trigger_class_nonzero", "truncated"]);
    expect(ev.tags.canary_tag).toBeUndefined();
    expect(Object.keys(ev.extra ?? {}).sort()).toEqual(["activity_witness", "class_result", "n_entries", "truncation_reason", "uptime_bucket"]);
    const flat = JSON.stringify(ev.extra);
    expect(flat).not.toContain("[Object]");
    for (const v of [...Object.values(ev.extra.n_entries), ...Object.values(ev.extra.class_result), ev.extra.uptime_bucket, ev.extra.truncation_reason, ev.extra.activity_witness] as string[]) {
      expect(ALLOWED_STRINGS.has(v), `extra value ${v}`).toBe(true);
    }
    expect(Object.keys(ev.extra.n_entries).sort()).toEqual([...CLASS_IDS].sort());

    const everything = [text, lines.join(""), JSON.stringify(envelopes)].join("\n");
    for (const canary of ["canary", "/home/", "t1.jsonl", "slug", "203.0.113.9", "canary-host-name"]) {
      expect(everything, `sink leaked ${canary}`).not.toContain(canary);
    }
  });

  it("every refusal and error response is built by the same allowlisted builder", async () => {
    const cases: Array<[string, () => Request, Partial<CensusDeps>]> = [
      ["401", () => post({ run_id: 1 }, "Bearer wrong"), {}],
      ["invalid json", () => post("{nope"), {}],
      ["invalid body", () => post({ run_id: "x" }), {}],
      ["invalid mode", () => post({ run_id: 1, mode: "banana" }), {}],
      ["build mismatch", () => post({ run_id: 1, mode: "real", expect_build_sha: "b".repeat(40) }), {}],
      ["young", () => post({ run_id: 1, mode: "real", expect_build_sha: SHA }), { uptime: () => 100 }],
      ["sunset", () => post({ run_id: 1, mode: "dry_run" }), { now: () => Date.parse("2027-01-01T00:00:00Z") }],
    ];
    for (const [name, mk, over] of cases) {
      resetState();
      const { deps } = makeDeps(over);
      const res = await handleHomeCensus(mk(), deps);
      const body = JSON.parse(await res.text());
      expect(res.status, name).toBeGreaterThanOrEqual(400);
      expect(checkAllowlist(body), name).toEqual([]);
      expect(body.ok, name).toBe(false);
    }
  });

  it("a raw fs error whose message embeds a path never reaches a sink: only the errno enum does", async () => {
    resetState();
    const exploding: CensusFs = {
      async lstat() {
        throw Object.assign(new Error(`EIO lstat '${CANARY_PATH}'`), { code: "EIO" });
      },
      async opendir() {
        throw Object.assign(new Error(`EIO opendir '${CANARY_PATH}'`), { code: "EIO" });
      },
    };
    const { deps, lines } = makeDeps({ fs: exploding });
    const { result: res, envelopes } = await withRealSentry(async () => handleHomeCensus(post({ run_id: 2, mode: "real", expect_build_sha: SHA }), deps));
    const text = await res.text();
    expect(eventsOf(envelopes), "an event must have been emitted or the leak check below is vacuous").toHaveLength(1);
    expect([text, lines.join(""), JSON.stringify(envelopes)].join("\n")).not.toContain("canary");
    expect(checkAllowlist(JSON.parse(text))).toEqual([]);
  });

  it("must-PASS non-canonical inputs: all-zero, truncated, young, permuted class order, dry_run", async () => {
    const variants: Array<[string, Partial<CensusDeps>, Record<string, unknown>]> = [
      ["all-zero", { fs: memFs({ "/home": d(), "/home/soleur": d() }) }, { run_id: 3, mode: "real", expect_build_sha: SHA }],
      ["truncated", { entryCap: 3 }, { run_id: 4, mode: "real", expect_build_sha: SHA }],
      ["young", { uptime: () => 100 }, { run_id: 5, mode: "real", expect_build_sha: SHA, accept_young: true }],
      ["dry_run", {}, { run_id: 6, mode: "dry_run" }],
    ];
    for (const [name, over, body] of variants) {
      resetState();
      const { deps, lines } = makeDeps(over);
      const res = await handleHomeCensus(post(body), deps);
      const json = JSON.parse(await res.text());
      expect(res.status, name).toBe(200);
      expect(checkAllowlist(json), name).toEqual([]);
      expect(json.interpretation, `${name}: interpretation is required on every response including zero`).toBeTruthy();
      expect(lines, name).toHaveLength(1);
    }
    // permuted order: the allowlist check does not depend on class position
    const { deps } = makeDeps();
    resetState();
    const json = JSON.parse(await (await handleHomeCensus(post({ run_id: 8, mode: "dry_run" }), deps)).text());
    json.classes.reverse();
    expect(checkAllowlist(json)).toEqual([]);
  });

  it("the allowlist check itself fails on each forbidden shape (instrument control)", () => {
    const base = JSON.parse(JSON.stringify({ schema_version: 1, ok: true, run_id: 1, classes: [{ class: "debug", n_entries: "0", n_mode_bits_group_r: "0", n_mode_bits_other_r: "0", n_symlink: "0", errors: "0", absent: true, class_result: "none_counted" }] }));
    expect(checkAllowlist(base)).toEqual([]);
    expect(checkAllowlist({ ...base, extra_key: "x" }).length).toBeGreaterThan(0);
    expect(checkAllowlist({ ...base, mode: "/home/t/.claude" }).length).toBeGreaterThan(0);
    const raw = JSON.parse(JSON.stringify(base));
    raw.classes[0].n_entries = 3;
    expect(checkAllowlist(raw).length).toBeGreaterThan(0);
    const second = JSON.parse(JSON.stringify(base));
    second.classes.push({ ...second.classes[0], extra: "x" });
    expect(checkAllowlist(second).length).toBeGreaterThan(0);
    expect(checkAllowlist({ ...base, pid: 12 }).length).toBeGreaterThan(0);
  });
});

describe("pino line and Vector filter", () => {
  beforeEach(resetState);
  const VECTOR = readFileSync(resolve(__dirname, "../../infra/vector.toml"), "utf8");
  it("passes Vector's app_container_warn_filter condition (level >= 40)", async () => {
    const m = /\[transforms\.app_container_warn_filter\][\s\S]*?condition = '''([\s\S]*?)'''/.exec(VECTOR);
    expect(m, "the filter block must be found").toBeTruthy();
    expect(m![1]).toMatch(/level_int >= 40/);
    const { deps, lines } = makeDeps();
    await handleHomeCensus(post({ run_id: 9, mode: "dry_run" }), deps);
    const parsed = JSON.parse(lines[0]);
    expect(Number(parsed.level)).toBeGreaterThanOrEqual(40);
  });
  it("carries no key that Vector's pii_scrub_drop_userdata deletes", async () => {
    const m = /\[transforms\.pii_scrub_drop_userdata\][\s\S]*?source = '''([\s\S]*?)'''/.exec(VECTOR);
    expect(m).toBeTruthy();
    const dropped = [...m![1].matchAll(/exists\(parsed_obj\.(\w+)\)/g)].map((x) => x[1]);
    expect(dropped.length).toBeGreaterThanOrEqual(8); // floor: the drop list was actually parsed
    const { deps, lines } = makeDeps();
    await handleHomeCensus(post({ run_id: 9, mode: "dry_run" }), deps);
    const walk = (o: unknown): string[] => (o && typeof o === "object" ? Object.entries(o as object).flatMap(([k, v]) => [k, ...walk(v)]) : []);
    const keys = walk(JSON.parse(lines[0]));
    for (const k of dropped) expect(keys, `census key ${k} collides with the Vector drop list`).not.toContain(k);
  });
});

// ---------------------------------------------------------------------------------------------
// Guard 4: positive control and canary.
// ---------------------------------------------------------------------------------------------
describe("positive control and canary", () => {
  beforeEach(resetState);
  const body = { run_id: 11, mode: "real", expect_build_sha: SHA };

  it("a scanner that returns all zeros turns the control RED: real is refused and nothing is scanned", async () => {
    const { deps } = makeDeps();
    const real = scanHome;
    const zero: typeof scanHome = async (o) => {
      const r = await real({ ...o, fs: memFs({}) });
      return r;
    };
    const res = await handleHomeCensus(post(body), { ...deps, scan: zero });
    expect(res.status).toBe(503);
    expect(JSON.parse(await res.text()).error_class).toBe("control_failed");
  });

  it("the control passes with the genuine scanner", async () => {
    const { deps } = makeDeps();
    const res = await handleHomeCensus(post(body), deps);
    expect(res.status).toBe(200);
    expect(JSON.parse(await res.text()).control).toBe("passed");
  });

  it("a canary directory that is empty or throws ENOENT refuses real; a hard-coded-true canary would not", async () => {
    const empty = mkdtempSync(join(tmpdir(), "home-census-empty-"));
    try {
      resetState();
      const a = makeDeps({ canaryDir: empty });
      expect((await handleHomeCensus(post(body), a.deps)).status).toBe(503);
      resetState();
      const b = makeDeps({ canaryDir: join(empty, "does-not-exist") });
      expect((await handleHomeCensus(post(body), b.deps)).status).toBe(503);
      resetState();
      const c = makeDeps({ canaryFs: memFs({ "/known": d() }), canaryDir: "/known" });
      expect((await handleHomeCensus(post(body), c.deps)).status).toBe(503);
      resetState();
      const ok = makeDeps({ canaryFs: memFs({ "/known": d(), "/known/x": f() }), canaryDir: "/known" });
      expect((await handleHomeCensus(post(body), ok.deps)).status).toBe(200);
    } finally {
      rmSync(empty, { recursive: true, force: true });
    }
  });

  it("an early exit after the first class is caught: a scan that skips a class cannot pass the control", async () => {
    const { deps } = makeDeps();
    const early: typeof scanHome = async (o) => scanHome({ ...o, entryCap: 1 });
    const res = await handleHomeCensus(post(body), { ...deps, scan: early });
    expect(res.status).toBe(503);
  });

  it("a swap of two classes' counts is caught by the control", async () => {
    const { deps } = makeDeps();
    const swapped: typeof scanHome = async (o) => {
      const r = await scanHome(o);
      const { debug, tasks } = r.scan.classes;
      r.scan.classes.debug = tasks;
      r.scan.classes.tasks = debug;
      return r;
    };
    const res = await handleHomeCensus(post(body), { ...deps, scan: swapped });
    expect(res.status).toBe(503);
  });

  it("a class that was never visited is unknown and a trigger zero without a witness is inconclusive", async () => {
    const tree: Record<string, Node> = { "/home": d(), "/home/soleur": d(), "/home/soleur/.claude": d(), "/home/soleur/.claude/debug": d() };
    const { deps } = makeDeps({ fs: memFs(tree) });
    const res = await handleHomeCensus(post(body), deps);
    const json = JSON.parse(await res.text());
    const byClass = Object.fromEntries(json.classes.map((c: any) => [c.class, c]));
    expect(json.activity_witness).toBe(false);
    for (const c of TRIGGER_CLASSES) expect(byClass[c].class_result, c).toBe("inconclusive");
    expect(json.trigger_class_nonzero, "all-inconclusive must not read as a negative").toBe("inconclusive");
    // account_state (.claude.json) is written by any CLI start: it is NOT a witness
    resetState();
    const accountOnly = { ...tree, "/home/soleur/.claude.json": f() };
    const r1 = JSON.parse(await (await handleHomeCensus(post(body), makeDeps({ fs: memFs(accountOnly) }).deps)).text());
    expect(r1.activity_witness).toBe(false);
    expect(r1.trigger_class_nonzero).toBe("inconclusive");
    // with a session artifact the same zeros read as none_counted
    resetState();
    const withWitness = { ...tree, "/home/soleur/.claude/sessions": d(), "/home/soleur/.claude/sessions/1.json": f() };
    const r2 = JSON.parse(await (await handleHomeCensus(post(body), makeDeps({ fs: memFs(withWitness) }).deps)).text());
    const b2 = Object.fromEntries(r2.classes.map((c: any) => [c.class, c]));
    expect(r2.activity_witness).toBe(true);
    for (const c of TRIGGER_CLASSES) expect(b2[c].class_result, c).toBe("none_counted");
    // a nonzero trigger class flips trigger_class_nonzero
    resetState();
    const r3 = JSON.parse(await (await handleHomeCensus(post(body), makeDeps().deps)).text());
    expect(r3.trigger_class_nonzero).toBe("true");
  });

  it("evidence boundary: 23h59 is young and 24h00 is mature", async () => {
    for (const [uptime, evidence] of [[86_399, "young"], [86_400, "mature"]] as const) {
      resetState();
      const { deps } = makeDeps({ uptime: () => uptime });
      const res = await handleHomeCensus(post({ ...body, accept_young: true }), deps);
      expect(JSON.parse(await res.text()).evidence, String(uptime)).toBe(evidence);
    }
  });
});

// ---------------------------------------------------------------------------------------------
// Class-table drift: a CLI state class named by the repository's own sources must be in the table.
// ---------------------------------------------------------------------------------------------
describe("class-table drift", () => {
  const ID_MAP: Record<string, string> = {
    todos: "todos",
    "shell-snapshots": "shell_snapshots",
    statsig: "statsig",
    backups: "backups",
    debug: "debug",
    history: "history_dir",
    "file-history": "file_history",
  };
  const sandboxTest = readFileSync(resolve(__dirname, "../sandbox-wrapped-command-runtime.test.ts"), "utf8");
  const parseList = (name: string) => {
    const m = new RegExp(`const ${name} = \\[([\\s\\S]*?)\\];`).exec(sandboxTest);
    return m ? [...m[1].matchAll(/"([^"]+)"/g)].map((x) => x[1]) : [];
  };
  const classOf = (state: string): string | null => {
    if (state === ".claude.json") return "account_state";
    if (state === ".claude/.last-cleanup") return "last_cleanup";
    const mm = /^\.claude\/([^/]+)/.exec(state);
    if (!mm) return null;
    return { sessions: "sessions_json", "shell-snapshots": "shell_snapshots", backups: "backups" }[mm[1]] ?? null;
  };

  it("every HOME_SESSION_DIRS entry maps to a class in the table", () => {
    expect(HOME_SESSION_DIRS.length).toBeGreaterThan(0);
    for (const dir of HOME_SESSION_DIRS) {
      expect(ID_MAP[dir], `no id mapping for ${dir}`).toBeTruthy();
      expect(CLASS_IDS as readonly string[], `class ${ID_MAP[dir]} missing from the census table`).toContain(ID_MAP[dir]);
    }
  });
  it("every REQUIRED/OPTIONAL_HOME_STATE entry of the sandbox test maps to a class in the table", () => {
    const states = [...parseList("REQUIRED_HOME_STATE"), ...parseList("OPTIONAL_HOME_STATE")];
    expect(states.length).toBeGreaterThan(0); // count-above-zero positive control: the locals were parsed
    for (const s of states) {
      const cls = classOf(s);
      expect(cls, `unmapped state ${s}`).toBeTruthy();
      expect(CLASS_IDS as readonly string[]).toContain(cls!);
    }
  });
  it("a class removed from a copy of the table is detected (negative row)", () => {
    const copy = (CLASS_IDS as readonly string[]).filter((c) => c !== "shell_snapshots");
    expect(HOME_SESSION_DIRS.map((x) => ID_MAP[x]).every((c) => copy.includes(c))).toBe(false);
  });
  it("the four trigger classes are in the table and scanned in the trigger set", () => {
    for (const c of ["history_jsonl", "debug", "todos", "tasks"]) expect(TRIGGER_CLASSES as readonly string[]).toContain(c);
  });
});

// ---------------------------------------------------------------------------------------------
// Review round: false zeros, mislabelled records, production defaults and wiring.
// ---------------------------------------------------------------------------------------------
describe("review round: a zero must not be read as a finding it did not establish", () => {
  beforeEach(resetState);
  const real = { run_id: 21, mode: "real", expect_build_sha: SHA };
  const run = async (tree: Record<string, Node>, over: Partial<CensusDeps> = {}) => {
    const { deps, lines } = makeDeps({ fs: memFs(tree), ...over });
    const res = await handleHomeCensus(post(real), deps);
    const json = JSON.parse(await res.text());
    const by = Object.fromEntries((json.classes ?? []).map((c: any) => [c.class, c]));
    return { json, by, lines, status: res.status };
  };
  const base = (): Record<string, Node> => ({ "/home": d(), "/home/soleur": d(), "/home/soleur/.claude": d() });

  it("a symlinked class directory is unknown, not zero, and the headline is unknown or true, never false", async () => {
    const tree = { ...base(), "/home/soleur/.claude/todos": { t: "link" } as Node, "/home/soleur/.claude/sessions": d(), "/home/soleur/.claude/sessions/1.json": f() };
    const { by, json } = await run(tree);
    expect(by.todos.class_result).toBe("unknown");
    expect(by.todos.n_symlink).toBe("1-4");
    expect(json.trigger_class_nonzero).toBe("unknown");
  });

  it("an unlistable sessions directory makes ALL its classes unknown, including the peer-key class", async () => {
    const { by } = await run({ ...base(), "/home/soleur/.claude/sessions": { t: "eacces" } as Node });
    for (const c of ["sessions_json", "sessions_key", "other_under_claude"]) {
      expect(by[c].class_result, c).toBe("unknown");
      expect(by[c].errors, c).toBe("1-4");
    }
  });

  it("an erroring or cut-off trigger class is unknown through the handler; cut classes with entries stay counted", async () => {
    const tree = { ...base(), "/home/soleur/.claude/tasks": { t: "eacces" } as Node, "/home/soleur/.claude/sessions": d(), "/home/soleur/.claude/sessions/1.json": f() };
    const a = await run(tree);
    expect(a.by.tasks.class_result).toBe("unknown");
    expect(a.json.trigger_class_nonzero).toBe("unknown");
    expect(a.by.debug.class_result).toBe("none_counted"); // witness present, class genuinely absent
    resetState();
    const b = await run(homeTreeAt("/home/soleur"), { entryCap: 5 });
    expect(b.json.truncated).toBe(true);
    expect(b.json.truncation_reason).toBe("entry_cap");
    expect(b.by.debug.class_result).toBe("counted"); // 3 entries seen before the cap: a lower bound is still a count
    expect(b.by.backups.class_result).toBe("unknown"); // never visited
    expect(JSON.parse(b.lines[0]).outcome).toBe("truncated");
  });

  it("account_state alone is not a witness; sessions_json alone is", async () => {
    const acc = await run({ ...base(), "/home/soleur/.claude.json": f() });
    expect(acc.json.activity_witness).toBe(false);
    expect(acc.by.debug.class_result).toBe("inconclusive");
    resetState();
    const ses = await run({ ...base(), "/home/soleur/.claude/sessions": d(), "/home/soleur/.claude/sessions/9.json": f() });
    expect(ses.json.activity_witness).toBe(true);
    expect(ses.by.debug.class_result).toBe("none_counted");
    expect(ses.json.trigger_class_nonzero).toBe("false");
  });

  it("the witness classes are scanned before projects, so a huge projects tree cannot starve them", async () => {
    const tree = homeTreeAt("/home/soleur");
    for (let i = 0; i < 40; i++) tree[`/home/soleur/.claude/projects/p${i}`] = d(), (tree[`/home/soleur/.claude/projects/p${i}/t`] = f());
    const { by, json } = await run(tree, { entryCap: 30 });
    expect(json.activity_witness).toBe(true);
    expect(by.sessions_json.class_result).toBe("counted");
    expect(json.truncated).toBe(true);
  });

  it("projects: a nested directory is one counted depth-2 entry and does NOT truncate the run", async () => {
    const tree = {
      ...base(),
      "/home/soleur/.claude/projects": d(),
      "/home/soleur/.claude/projects/s": d(),
      "/home/soleur/.claude/projects/s/t.jsonl": f(),
      "/home/soleur/.claude/projects/s/subagents": d(),
      "/home/soleur/.claude/projects/s/subagents/deep": d(),
      "/home/soleur/.claude/projects/s/subagents/deep/x": f(),
    };
    const { by, json } = await run(tree);
    expect(json.truncated).toBe(false);
    expect(by.projects.n_entries).toBe("1-4");
    const { scan } = await scanHome(scanOpts(memFs({ ...tree, "/home/t": d(), "/home/t/.claude": d() })));
    void scan;
    const direct = await scanHome(scanOpts(memFs(Object.fromEntries(Object.entries(tree).map(([k, v]) => [k.replace("/home/soleur", "/home/t"), v]))), {}));
    expect(direct.scan.classes.projects.entries).toBe(2); // t.jsonl and the subagents directory
  });

  it("mode bits: a symlink and an uncounted depth-1 directory are not tallied", async () => {
    const tree: Record<string, Node> = {
      "/home": d(), "/home/t": d(), "/home/t/.claude": d(),
      "/home/t/.claude/debug": d(), "/home/t/.claude/debug/link": { t: "link", mode: 0o777 }, "/home/t/.claude/debug/file": f(0o600),
      "/home/t/.claude/projects": d(), "/home/t/.claude/projects/slug": { t: "dir", mode: 0o755 },
    };
    const { scan } = await scanHome(scanOpts(memFs(tree)));
    expect(scan.classes.debug.symlink).toBe(1);
    expect(scan.classes.debug.groupR).toBe(0);
    expect(scan.classes.debug.otherR).toBe(0);
    expect(scan.classes.projects.groupR).toBe(0);
    expect(scan.classes.projects.entries).toBe(0);
  });

  it("the dev/ino re-check happens AFTER the open", async () => {
    const fs = memFs(homeTree());
    await scanHome(scanOpts(fs));
    const calls = fs.calls.filter((c) => c.endsWith(" /home/t/.claude/debug"));
    expect(calls).toEqual(["lstat /home/t/.claude/debug", "opendir /home/t/.claude/debug", "lstat /home/t/.claude/debug"]);
  });

  it("the production load-shed default does not truncate a normal scan (default histogram path runs)", async () => {
    const tree: Record<string, Node> = { "/home": d(), "/home/t": d(), "/home/t/.claude": d(), "/home/t/.claude/debug": d() };
    for (let i = 0; i < 600; i++) tree[`/home/t/.claude/debug/f${i}`] = f();
    const { scan } = await scanHome({ fs: memFs(tree), roots: ROOT() });
    expect(scan.truncated).toBe(false);
    expect(scan.classes.debug.entries).toBe(600);
  });

  it("a hung canary fails the run with control_failed and releases the flag and the slot", async () => {
    vi.useFakeTimers();
    try {
      const hung: CensusFs = { lstat: async () => Promise.reject(new Error("unused")), opendir: () => new Promise(() => {}) };
      const { deps } = makeDeps({ canaryFs: hung, canaryDir: "/known" });
      const pending = handleHomeCensus(post(real), deps);
      await vi.advanceTimersByTimeAsync(3_100);
      const res = await pending;
      expect(res.status).toBe(503);
      expect(JSON.parse(await res.text()).error_class).toBe("control_failed");
      const g = globalThis as Record<symbol, any>;
      expect(g[Symbol.for("soleur.homeCensus.inflight")]).toBe(false);
      expect(g[Symbol.for("soleur.homeCensus.limiter")].starts).toEqual([]);
    } finally {
      vi.useRealTimers();
    }
  });

  it("a control failure emits a refusal record with NO class counts and never a result labelled container_home", async () => {
    const empty = mkdtempSync(join(tmpdir(), "home-census-empty-"));
    try {
      const { deps, lines } = makeDeps({ canaryDir: empty });
      const { result: res, envelopes } = await withRealSentry(async () => handleHomeCensus(post(real), deps));
      expect(res.status).toBe(503);
      expect(lines).toHaveLength(1);
      const line = JSON.parse(lines[0]);
      expect(line.msg).toBe("home-census refused");
      expect(line.error_class).toBe("control_failed");
      expect(line).not.toHaveProperty("classes");
      expect(line).not.toHaveProperty("data_source");
      const ev = eventsOf(envelopes) as Array<Record<string, any>>;
      expect(ev).toHaveLength(1);
      expect(ev[0].message).toBe("home-census refused");
      expect(ev[0].level).toBe("error");
    } finally {
      rmSync(empty, { recursive: true, force: true });
    }
  });

  it("a dry_run is info-level and tagged synthetic: it never reads as a counted trigger class", async () => {
    const { deps } = makeDeps();
    const { envelopes } = await withRealSentry(async () => handleHomeCensus(post({ run_id: 31, mode: "dry_run" }), deps));
    const ev = eventsOf(envelopes) as Array<Record<string, any>>;
    expect(ev).toHaveLength(1);
    expect(ev[0].level).toBe("info");
    expect(ev[0].tags.data_source).toBe("synthetic");
  });

  it("a real scan with a counted trigger class is a warning tagged container_home", async () => {
    const { deps } = makeDeps();
    const { envelopes } = await withRealSentry(async () => handleHomeCensus(post(real), deps));
    const ev = eventsOf(envelopes) as Array<Record<string, any>>;
    expect(ev[0].level).toBe("warning");
    expect(ev[0].tags.data_source).toBe("container_home");
    expect(ev[0].tags.trigger_class_nonzero).toBe("true");
  });

  it("the non-secret non-tenant state files the outer wrap binds are never counted", async () => {
    expect([...HOME_STATE_FILES].sort()).toEqual([".credentials.json", "settings.json"]);
    const tree: Record<string, Node> = { "/home": d(), "/home/t": d(), "/home/t/.claude": d() };
    for (const name of HOME_STATE_FILES) tree[`/home/t/.claude/${name}`] = f();
    const { scan } = await scanHome(scanOpts(memFs(tree)));
    expect(scan.classes.other_under_claude.entries).toBe(0);
  });

  it("resolveRoots refuses // and a trailing slash and keeps /home/. out", () => {
    const nohome = () => {
      throw new Error("x");
    };
    for (const bad of ["/home//x", "/home/x/", "/home/./x", "/root//", "/home/x/../y"]) {
      expect(resolveRoots({ HOME: bad }, nohome).roots.map((r) => r.label), bad).not.toContain("env_home");
    }
  });

  it("production defaults: the canary directory is non-empty and the real adapter lists a temp directory", async () => {
    const def = defaultCensusDeps();
    expect(def.canaryDir).toBeTruthy();
    expect(readdirSync(def.canaryDir).length).toBeGreaterThan(0);
    const dir = mkdtempSync(join(tmpdir(), "home-census-real-"));
    try {
      writeFileSync(join(dir, "x"), "x");
      const st = await def.fs.lstat(dir);
      expect(st.isDirectory()).toBe(true);
      const dh = await def.fs.opendir(dir);
      expect((await dh.read())?.name).toBe("x");
      expect(await dh.read()).toBeNull();
      await dh.close();
      await expect(def.fs.lstat(join(dir, "missing"))).rejects.toMatchObject({ code: "ENOENT" });
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });
});

function homeTreeAt(root: string): Record<string, Node> {
  const t = homeTree("/home/t");
  return Object.fromEntries(Object.entries(t).map(([k, v]) => [k.replace("/home/t", root), v]));
}

// ---------------------------------------------------------------------------------------------
// Parity: the trigger script's jq schema must accept exactly what the server emits (no hand-copied list may drift).
// ---------------------------------------------------------------------------------------------
describe("trigger script schema parity", () => {
  beforeEach(resetState);
  const script = readFileSync(resolve(__dirname, "../../scripts/home-census-trigger.sh"), "utf8");
  const interp = /^INTERPRETATION="([^"]*)"$/m.exec(script)?.[1] ?? "";
  const program = (name: string) => {
    const m = new RegExp(`${name}\\(\\) \\{[\\s\\S]*?jq -e[r]? --arg interp "\\$INTERPRETATION" '([\\s\\S]*?)'`).exec(script);
    return m?.[1] ?? "";
  };
  const jq = (prog: string, json: unknown) => spawnSync("jq", ["-e", "--arg", "interp", interp, prog], { input: JSON.stringify(json) });

  it("the script's INTERPRETATION equals the one the server emits", async () => {
    const { deps } = makeDeps();
    const body = JSON.parse(await (await handleHomeCensus(post({ run_id: 5, mode: "dry_run" }), deps)).text());
    expect(interp.length).toBeGreaterThan(20);
    expect(body.interpretation).toBe(interp);
  });

  it("body_valid accepts every server variant: dry_run, real, truncated, young, all-zero", async () => {
    const prog = program("body_valid");
    expect(prog.length, "the jq program was extracted").toBeGreaterThan(200);
    const variants: Array<[string, Partial<CensusDeps>, Record<string, unknown>]> = [
      ["dry_run", {}, { run_id: 1, mode: "dry_run" }],
      ["real", {}, { run_id: 2, mode: "real", expect_build_sha: SHA }],
      ["truncated", { entryCap: 3 }, { run_id: 3, mode: "real", expect_build_sha: SHA }],
      ["young", { uptime: () => 100 }, { run_id: 4, mode: "real", expect_build_sha: SHA, accept_young: true }],
      ["all-zero", { fs: memFs({ "/home": d(), "/home/soleur": d() }) }, { run_id: 5, mode: "real", expect_build_sha: SHA }],
    ];
    for (const [name, over, body] of variants) {
      resetState();
      const { deps } = makeDeps(over);
      const json = JSON.parse(await (await handleHomeCensus(post(body), deps)).text());
      const r = jq(prog, json);
      expect(r.status, `${name}: ${r.stderr}`).toBe(0);
    }
    // and it refuses a body the server never emits
    const { deps } = makeDeps();
    const json = JSON.parse(await (await handleHomeCensus(post({ run_id: 6, mode: "dry_run" }), deps)).text());
    json.classes[0].extra = "x";
    expect(jq(prog, json).status).not.toBe(0);
  });

  it("failure_class accepts every failure body the server emits and nothing else", async () => {
    const prog = program("failure_class");
    expect(prog.length).toBeGreaterThan(100);
    const { deps } = makeDeps();
    const res = await handleHomeCensus(post({ run_id: 1, mode: "dry_run" }, "Bearer wrong"), deps);
    const json = JSON.parse(await res.text());
    const ok = jq(`select(${prog.replace(/^select\(/, "").replace(/\) \| \.error_class$/, "")}) | .error_class`, json);
    expect(ok.stdout.toString().trim()).toBe('"unauthorized"');
    json.extra = "x";
    expect(jq(`select(${prog.replace(/^select\(/, "").replace(/\) \| \.error_class$/, "")}) | .error_class`, json).status).not.toBe(0);
  });
});
