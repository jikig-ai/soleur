// Counts-only census of the shared HOME (Ref #10455). Passive: nothing arms it, a deploy cannot run it.
//
// Property: for each CLI-state class, count entries with lstat and opendir/read only, classify in-loop,
// never retain a name, and emit ONE bucketed-counts object. Nothing but bucket labels, booleans and
// members of closed enums may reach any sink (the HTTP response, one Sentry event, one pino line).
// The reasoning lives in knowledge-base/project/plans/2026-10-31-feat-prod-home-census-plan.md and the
// ADR-075 addendum; this file keeps only the load-bearing constraints.
//
// The HOME is the container's writable layer; it is wiped when the container is recreated (every deploy), so a zero is never
// "clean": every response carries `interpretation`, `evidence` and `uptime_bucket`.
//
// Removal: the sunset below makes the route return 410; #11714 tracks deleting this file, the route,
// the trigger script and the `lib/routes.ts` entry.

import { lstat as fsLstat, opendir as fsOpendir } from "node:fs/promises";
import { monitorEventLoopDelay } from "node:perf_hooks";
import { homedir as osHomedir } from "node:os";
import pino from "pino";
import * as Sentry from "@sentry/nextjs";

import { bearerMatches, readInternalBearerSecret } from "@/lib/internal-auth";

// ------------------------------------------------------------------------------------------------
// Constants
// ------------------------------------------------------------------------------------------------
export const SCHEMA_VERSION = 1;
/** Merge date + 30 days. Set when the PR is marked ready; corrected before merge if the merge slips. */
export const SUNSET_UTC = "2026-11-30T00:00:00Z";
export const MAX_BODY_BYTES = 64 * 1024;
const ENTRY_CAP = 20_000;
const TIME_CAP_MS = 20_000;
// Directories are descended to depth 2 only (projects/<slug>/<entry>); a directory found at depth 2 is one counted entry.
const DESCEND_DEPTH = 2;
// The top bucket is `1000+`, so 1,001 entries per trigger class already fixes the label; reading more is wasted I/O.
const TRIGGER_CLASS_BUDGET = 1_001;
const PROJECTS_BUDGET = 5_000;
const CANARY_TIMEOUT_MS = 3_000;
const YIELD_EVERY = 256;
const YOUNG_UPTIME_S = 86_400;
const LIMITER_MAX_REAL = 2;
const LIMITER_GAP_MS = 3_600_000;
const DRY_RUN_SENTRY_GAP_MS = 600_000;
const LOAD_SHED_MAX_MS = 150;
const MESSAGE = "home-census result";
const REFUSED_MESSAGE = "home-census refused";
const INTERPRETATION =
  "counted in this container's writable layer at the run; not a statement about earlier containers, other hosts, or any time before or after the run";

export const CLASS_IDS = [
  "history_jsonl",
  "debug",
  "todos",
  "tasks",
  "history_dir",
  "projects",
  "sessions_json",
  "sessions_key",
  "shell_snapshots",
  "account_state",
  "backups",
  "last_cleanup",
  "statsig",
  "file_history",
  "other_under_claude",
] as const;
export type ClassId = (typeof CLASS_IDS)[number];
export const TRIGGER_CLASSES = ["history_jsonl", "debug", "todos", "tasks"] as const satisfies readonly ClassId[];
// Session artifacts only: .claude.json is written by any CLI start, so it does not show that a tenant session ran.
const WITNESS_CLASSES = ["sessions_json", "shell_snapshots"] as const satisfies readonly ClassId[];

type Step = {
  ids: readonly ClassId[];
  rel: string;
  kind: "file" | "dir";
  recurse?: boolean;
  /** Classes this step fully enumerates (visited/absent are set only for these); the rest are classification fallbacks. */
  own?: readonly ClassId[];
  classify?: (name: string) => ClassId;
  skipNames?: ReadonlySet<string>;
};
// Order matters: the four trigger classes are scanned FIRST, then the cheap witness classes, so a large `projects`
// tree cannot use up the entry cap before the witness is established.
// `.credentials.json` and `settings.json` are non-tenant state the outer wrap binds read-write (HOME_STATE_FILES); they
// are skipped, never counted or opened.
const CLAUDE_KNOWN = new Set(["history.jsonl", "history", "debug", "todos", "tasks", "projects", "sessions", "shell-snapshots", "backups", "statsig", "file-history", ".last-cleanup", ".credentials.json", "settings.json"]);
const STEPS: readonly Step[] = [
  { ids: ["history_jsonl"], rel: ".claude/history.jsonl", kind: "file" },
  { ids: ["debug"], rel: ".claude/debug", kind: "dir" },
  { ids: ["todos"], rel: ".claude/todos", kind: "dir" },
  { ids: ["tasks"], rel: ".claude/tasks", kind: "dir" },
  { ids: ["account_state"], rel: ".claude.json", kind: "file" },
  {
    ids: ["sessions_json", "sessions_key", "other_under_claude"],
    own: ["sessions_json", "sessions_key"],
    rel: ".claude/sessions",
    kind: "dir",
    classify: (n) => (n.endsWith(".key") ? "sessions_key" : n.endsWith(".json") ? "sessions_json" : "other_under_claude"),
  },
  { ids: ["shell_snapshots"], rel: ".claude/shell-snapshots", kind: "dir" },
  { ids: ["history_dir"], rel: ".claude/history", kind: "dir" },
  { ids: ["projects"], rel: ".claude/projects", kind: "dir", recurse: true },
  { ids: ["backups"], rel: ".claude/backups", kind: "dir" },
  { ids: ["last_cleanup"], rel: ".claude/.last-cleanup", kind: "file" },
  { ids: ["statsig"], rel: ".claude/statsig", kind: "dir" },
  { ids: ["file_history"], rel: ".claude/file-history", kind: "dir" },
  { ids: ["other_under_claude"], rel: ".claude", kind: "dir", skipNames: CLAUDE_KNOWN },
];

// ------------------------------------------------------------------------------------------------
// Types
// ------------------------------------------------------------------------------------------------
export interface StatLike {
  mode: number;
  dev: number | bigint;
  ino: number | bigint;
  isDirectory(): boolean;
  isSymbolicLink(): boolean;
}
export interface DirLike {
  read(): Promise<{ name: string } | null>;
  close(): Promise<void>;
}
/** The ONLY filesystem surface the census can reach: lstat and opendir. */
export interface CensusFs {
  lstat(p: string): Promise<StatLike>;
  opendir(p: string): Promise<DirLike>;
}
export type RootLabel = "env_home" | "home_soleur" | "root";
export interface Root {
  label: RootLabel;
  path: string;
}
type Reason = "entry_cap" | "time_cap" | "load_shed" | "class_budget";
interface Acc {
  entries: number;
  groupR: number;
  otherR: number;
  symlink: number;
  errors: number;
  absent: boolean;
  visited: boolean;
  cut: boolean;
}
export interface InternalScan {
  classes: Record<ClassId, Acc>;
  truncated: boolean;
  reason: Reason | null;
  roots: Array<{ label: RootLabel; present: boolean; listable: boolean }>;
}
export interface ScanOptions {
  fs: CensusFs;
  roots: Root[];
  entryCap?: number;
  timeCapMs?: number;
  yieldFn?: () => Promise<void>;
  yieldEvery?: number;
  loadShed?: () => boolean;
}
export type ScanFn = (o: ScanOptions) => Promise<{ scan: InternalScan; settled: Promise<void> }>;

// ------------------------------------------------------------------------------------------------
// Small pure helpers
// ------------------------------------------------------------------------------------------------
export function bucketCount(n: number): string {
  if (n <= 0) return "0";
  if (n < 5) return "1-4";
  if (n < 20) return "5-19";
  if (n < 100) return "20-99";
  if (n < 1000) return "100-999";
  return "1000+";
}
export function uptimeBucket(seconds: number): "lt_1h" | "lt_24h" | "lt_7d" | "ge_7d" {
  if (seconds < 3600) return "lt_1h";
  if (seconds < 86_400) return "lt_24h";
  if (seconds < 604_800) return "lt_7d";
  return "ge_7d";
}
const noop = () => {};
const newAcc = (): Acc => ({ entries: 0, groupR: 0, otherR: 0, symlink: 0, errors: 0, absent: true, visited: false, cut: false });
const errCode = (e: unknown): string => (typeof (e as { code?: unknown })?.code === "string" ? (e as { code: string }).code : "");

export function resolveRoots(
  env: Record<string, string | undefined>,
  homedir: () => string,
): { roots: Root[]; rootsDistinct: boolean; rootsNote: "none" | "env_home_rejected" | "homedir_unavailable" } {
  let note: "none" | "env_home_rejected" | "homedir_unavailable" = "none";
  let envHome = env.HOME;
  if (envHome === undefined || envHome === "") {
    try {
      envHome = homedir();
    } catch {
      envHome = undefined;
      note = "homedir_unavailable";
    }
  }
  const acceptable = (p: string | undefined): p is string =>
    typeof p === "string" &&
    p.startsWith("/") &&
    !p.split("/").some((seg) => seg === ".." || seg === ".") &&
    !p.includes("//") &&
    !p.endsWith("/") &&
    (p.startsWith("/home/") || p === "/root" || p.startsWith("/root/"));
  const candidates: Root[] = [];
  if (envHome !== undefined) {
    if (acceptable(envHome)) candidates.push({ label: "env_home", path: envHome });
    else note = "env_home_rejected";
  }
  candidates.push({ label: "home_soleur", path: "/home/soleur" }, { label: "root", path: "/root" });
  const seen = new Set<string>();
  const roots: Root[] = [];
  let distinct = true;
  for (const c of candidates) {
    if (seen.has(c.path)) {
      distinct = false;
      continue;
    }
    seen.add(c.path);
    roots.push(c);
  }
  return { roots, rootsDistinct: distinct, rootsNote: note };
}

// ------------------------------------------------------------------------------------------------
// The scanner
// ------------------------------------------------------------------------------------------------
class StopScan extends Error {}

export const scanHome: ScanFn = async (opts) => {
  const entryCap = opts.entryCap ?? ENTRY_CAP;
  const timeCapMs = opts.timeCapMs ?? TIME_CAP_MS;
  const yieldFn = opts.yieldFn ?? (() => new Promise<void>((r) => setImmediate(r)));
  const yieldEvery = opts.yieldEvery ?? YIELD_EVERY;
  const classes = Object.fromEntries(CLASS_IDS.map((c) => [c, newAcc()])) as Record<ClassId, Acc>;
  const scan: InternalScan = { classes, truncated: false, reason: null, roots: [] };
  const pending = new Set<Promise<void>>();
  let total = 0;

  let timer: ReturnType<typeof setTimeout> | undefined;
  const deadline = new Promise<never>((_, rej) => {
    timer = setTimeout(() => rej(new StopScan("time_cap")), timeCapMs);
  });
  deadline.catch(noop);

  let histogram: ReturnType<typeof monitorEventLoopDelay> | undefined;
  let loadShed = opts.loadShed;
  if (!loadShed) {
    histogram = monitorEventLoopDelay({ resolution: 20 });
    histogram.enable();
    const h = histogram;
    loadShed = () => {
      // max, not mean: a 256-entry window often holds no sample at all, and a mean over a mostly-idle window hides a stall.
      const maxMs = h.max / 1e6;
      h.reset();
      return Number.isFinite(maxMs) && maxMs > LOAD_SHED_MAX_MS;
    };
  }

  let finished = false;
  // A Dir handle that resolves after the scan returned (an op abandoned by the cap) is closed here; only handles have close().
  const closeLate = (v: unknown) => {
    if (finished && v && typeof (v as { close?: unknown }).close === "function") {
      void Promise.resolve()
        .then(() => (v as DirLike).close())
        .catch(noop);
    }
  };

  // Every fs promise gets a terminal catch AT CREATION: an op abandoned by the time cap can reject later
  // with a message that carries a path, and that must never surface as an unhandled rejection.
  const call = <T>(fn: () => Promise<T>): Promise<T> => {
    let p: Promise<T>;
    try {
      p = fn();
    } catch (e) {
      p = Promise.reject(e);
    }
    const settled = p.then(closeLate, noop);
    pending.add(settled);
    void settled.then(() => pending.delete(settled));
    return Promise.race([p, deadline]);
  };

  const stop = (reason: Reason): never => {
    scan.truncated = true;
    scan.reason = reason; // the stop that actually ended the scan wins over an earlier per-class budget cut
    throw new StopScan(reason);
  };
  const bumpErr = (step: Step) => {
    for (const id of step.ids) classes[id].errors++;
  };
  const cutAll = (step: Step) => {
    for (const id of step.ids) classes[id].cut = true;
  };

  // A symlink is counted and nothing else (lstat reports mode 0777 for a link). Mode bits are tallied only for counted entries.
  const tally = (acc: Acc, st: StatLike, counted: boolean) => {
    if (st.isSymbolicLink()) {
      acc.symlink++;
      return;
    }
    if (!counted) return;
    if ((st.mode & 0o040) !== 0) acc.groupR++;
    if ((st.mode & 0o004) !== 0) acc.otherR++;
  };

  async function walk(path: string, depth: number, step: Step, primary: Acc, budget: { left: number }, expect: StatLike): Promise<void> {
    let dir: DirLike;
    try {
      dir = await call(() => opts.fs.opendir(path));
    } catch (e) {
      if (e instanceof StopScan) throw e;
      if (errCode(e) !== "ENOENT") bumpErr(step);
      return;
    }
    try {
      // Re-lstat AFTER the open and compare dev/ino: a tenant can swap a directory for a symlink between the first lstat
      // and the open (the HOME is writable by tenant sessions). A mismatch is an error, never a count.
      let again: StatLike;
      try {
        again = await call(() => opts.fs.lstat(path));
      } catch (e) {
        if (e instanceof StopScan) throw e;
        bumpErr(step);
        return;
      }
      if (again.dev !== expect.dev || again.ino !== expect.ino || again.isSymbolicLink()) {
        bumpErr(step);
        return;
      }
      for (;;) {
        let ent: { name: string } | null;
        try {
          ent = await call(() => dir.read());
        } catch (e) {
          if (e instanceof StopScan) throw e;
          bumpErr(step);
          return;
        }
        if (ent === null) return;
        const name = ent.name;
        if (step.skipNames?.has(name)) continue;
        if (total >= entryCap) {
          primary.cut = true;
          stop("entry_cap");
        }
        if (budget.left <= 0) {
          cutAll(step);
          scan.truncated = true;
          scan.reason = scan.reason ?? "class_budget";
          return;
        }
        total++;
        budget.left--;
        if (total % yieldEvery === 0) {
          await yieldFn();
          if (loadShed!()) {
            primary.cut = true;
            stop("load_shed");
          }
        }
        const acc = step.classify && depth === 1 ? classes[step.classify(name)] : primary;
        const child = `${path}/${name}`;
        let st: StatLike;
        try {
          st = await call(() => opts.fs.lstat(child));
        } catch (e) {
          if (e instanceof StopScan) throw e;
          acc.entries++;
          acc.errors++;
          continue;
        }
        const counted = !step.recurse || depth >= DESCEND_DEPTH || !st.isDirectory();
        if (counted) acc.entries++;
        tally(acc, st, counted);
        if (step.recurse && depth < DESCEND_DEPTH && st.isDirectory() && !st.isSymbolicLink()) {
          await walk(child, depth + 1, step, primary, budget, st);
        }
      }
    } finally {
      void Promise.resolve()
        .then(() => dir.close())
        .catch(noop);
    }
  }

  const claudeState = new Map<RootLabel, "dir" | "absent" | "link" | "error">();

  async function scanStep(root: Root, step: Step): Promise<void> {
    const primary = classes[step.ids[0]];
    for (const id of step.own ?? step.ids) {
      classes[id].visited = true;
    }
    try {
      // An intermediate symlink (or an unreadable .claude) is invisible to lstat of the leaf: the whole family is unknown.
      if (step.rel.startsWith(".claude") && claudeState.get(root.label) !== "dir" && claudeState.get(root.label) !== "absent") {
        cutAll(step);
        return;
      }
      await scanStepInner(root, step, primary);
    } catch (e) {
      // a class that was in progress when the scan stopped is unknown, never zero
      if (e instanceof StopScan) cutAll(step);
      throw e;
    }
  }

  async function scanStepInner(root: Root, step: Step, primary: Acc): Promise<void> {
    const path = `${root.path}/${step.rel}`;
    let st: StatLike;
    try {
      st = await call(() => opts.fs.lstat(path));
    } catch (e) {
      if (e instanceof StopScan) throw e;
      const code = errCode(e);
      if (code !== "ENOENT" && code !== "ENOTDIR") bumpErr(step);
      return;
    }
    for (const id of step.own ?? step.ids) classes[id].absent = false;
    if (st.isSymbolicLink()) {
      // A symlink (including a class directory that is itself a link) is counted and never opened. The CLI would follow
      // it, so the class is unknown, never zero.
      primary.symlink++;
      cutAll(step);
      return;
    }
    if (step.kind === "file" || !st.isDirectory()) {
      primary.entries++;
      tally(primary, st, true);
      return;
    }
    const isTrigger = (TRIGGER_CLASSES as readonly string[]).includes(step.ids[0]);
    const budget = { left: isTrigger ? TRIGGER_CLASS_BUDGET : step.ids[0] === "projects" ? PROJECTS_BUDGET : Number.POSITIVE_INFINITY };
    await walk(path, 1, step, primary, budget, st);
  }

  try {
    // Root presence and listability, once per root.
    for (const root of opts.roots) {
      let present = false;
      let listable = false;
      try {
        const st = await call(() => opts.fs.lstat(root.path));
        present = st.isDirectory() && !st.isSymbolicLink();
        if (present) {
          const dir = await call(() => opts.fs.opendir(root.path));
          listable = true;
          void Promise.resolve()
            .then(() => dir.close())
            .catch(noop);
          try {
            const cst = await call(() => opts.fs.lstat(`${root.path}/.claude`));
            claudeState.set(root.label, cst.isSymbolicLink() ? "link" : cst.isDirectory() ? "dir" : "error");
          } catch (e) {
            if (e instanceof StopScan) throw e;
            claudeState.set(root.label, errCode(e) === "ENOENT" ? "absent" : "error");
          }
        }
      } catch (e) {
        if (e instanceof StopScan) throw e;
      }
      scan.roots.push({ label: root.label, present, listable });
    }
    for (const step of STEPS) {
      for (const root of opts.roots) {
        // A root that exists but cannot be listed (for example another user's home) is reported and not scanned: it is
        // not a per-class error, and counting it as one would make every class unknown.
        const info = scan.roots.find((r) => r.label === root.label);
        if (!info?.present || !info.listable) continue;
        await scanStep(root, step);
      }
    }
  } catch (e) {
    scan.truncated = true;
    scan.reason = e instanceof StopScan ? (e.message as Reason) : (scan.reason ?? "time_cap");
  } finally {
    finished = true;
    if (timer !== undefined) clearTimeout(timer);
    histogram?.disable();
  }
  const settled = Promise.all([...pending]).then(noop);
  return { scan, settled };
};

// ------------------------------------------------------------------------------------------------
// In-memory synthetic HOME: positive control and dry_run source (never touches the real filesystem)
// ------------------------------------------------------------------------------------------------
type Kind = "dir" | "file";
function buildSyntheticFs(): { fs: CensusFs; root: string } {
  const nodes = new Map<string, { kind: Kind; mode: number; ino: number }>();
  let ino = 1;
  const root = "/synthetic/home";
  const add = (p: string, kind: Kind, mode = kind === "dir" ? 0o700 : 0o600) => void nodes.set(p, { kind, mode, ino: ino++ });
  add("/synthetic", "dir");
  add(root, "dir");
  add(`${root}/.claude`, "dir");
  add(`${root}/.claude.json`, "file", 0o644);
  for (const [name, n] of Object.entries(CONTROL_DIRS)) {
    add(`${root}/.claude/${name}`, "dir");
    for (let i = 0; i < n; i++) add(`${root}/.claude/${name}/f${i}`, "file", i === 0 ? 0o640 : 0o600);
  }
  add(`${root}/.claude/history.jsonl`, "file", 0o644);
  add(`${root}/.claude/.last-cleanup`, "file");
  add(`${root}/.claude/projects`, "dir");
  add(`${root}/.claude/projects/a`, "dir");
  add(`${root}/.claude/projects/a/t1`, "file");
  add(`${root}/.claude/projects/a/t2`, "file");
  add(`${root}/.claude/projects/b`, "dir");
  add(`${root}/.claude/projects/b/t3`, "file");
  add(`${root}/.claude/sessions`, "dir");
  add(`${root}/.claude/sessions/1.json`, "file");
  add(`${root}/.claude/sessions/2.json`, "file");
  add(`${root}/.claude/sessions/1.k.key`, "file", 0o644);
  add(`${root}/.claude/extra`, "file");
  const children = (dir: string) => [...nodes.keys()].filter((k) => k.startsWith(`${dir}/`) && !k.slice(dir.length + 1).includes("/")).map((k) => k.slice(dir.length + 1));
  const fs: CensusFs = {
    async lstat(p) {
      const n = nodes.get(p);
      if (!n) throw Object.assign(new Error("ENOENT"), { code: "ENOENT" });
      return { mode: n.mode, dev: 1, ino: n.ino, isDirectory: () => n.kind === "dir", isSymbolicLink: () => false };
    },
    async opendir(p) {
      const n = nodes.get(p);
      if (!n || n.kind !== "dir") throw Object.assign(new Error("ENOENT"), { code: "ENOENT" });
      const names = children(p);
      let i = 0;
      return { read: async () => (i < names.length ? { name: names[i++] } : null), close: async () => {} };
    },
  };
  return { fs, root };
}
const CONTROL_DIRS: Record<string, number> = { debug: 3, todos: 2, tasks: 5, "shell-snapshots": 4, backups: 6, statsig: 7, "file-history": 1, history: 8 };
// Known answers for the synthetic tree above. A different count per class so a swap cannot hide.
const CONTROL_EXPECTED: Record<ClassId, number> = {
  history_jsonl: 1, debug: 3, todos: 2, tasks: 5, history_dir: 8, projects: 3, sessions_json: 2, sessions_key: 1,
  shell_snapshots: 4, account_state: 1, backups: 6, last_cleanup: 1, statsig: 7, file_history: 1, other_under_claude: 1,
};

// Expected [group-readable, other-readable] entry counts for the synthetic tree (first file of each directory is 0o640).
const CONTROL_MODE: Record<ClassId, readonly [number, number]> = {
  history_jsonl: [1, 1], debug: [1, 0], todos: [1, 0], tasks: [1, 0], history_dir: [1, 0], projects: [0, 0], sessions_json: [0, 0],
  sessions_key: [1, 1], shell_snapshots: [1, 0], account_state: [1, 1], backups: [1, 0], last_cleanup: [0, 0], statsig: [1, 0],
  file_history: [1, 0], other_under_claude: [0, 0],
};

function controlMatches(scan: InternalScan): boolean {
  if (scan.truncated) return false;
  for (const c of CLASS_IDS) {
    const a = scan.classes[c];
    if (!a.visited || a.errors !== 0 || a.entries !== CONTROL_EXPECTED[c]) return false;
    if (a.groupR !== CONTROL_MODE[c][0] || a.otherR !== CONTROL_MODE[c][1] || a.symlink !== 0) return false;
  }
  return true;
}

async function canaryOk(fs: CensusFs, dir: string): Promise<boolean> {
  // Bounded: a hung canary would otherwise hold the in-flight flag and a limiter slot until restart.
  let timer: ReturnType<typeof setTimeout> | undefined;
  const timeout = new Promise<boolean>((resolve) => {
    timer = setTimeout(() => resolve(false), CANARY_TIMEOUT_MS);
  });
  const probe = (async () => {
    try {
      const d = await fs.opendir(dir);
      try {
        return (await d.read()) !== null;
      } finally {
        void Promise.resolve()
          .then(() => d.close())
          .catch(noop);
      }
    } catch {
      return false;
    }
  })();
  try {
    return await Promise.race([probe, timeout]);
  } finally {
    if (timer !== undefined) clearTimeout(timer);
  }
}

// ------------------------------------------------------------------------------------------------
// The allowlisted builder. Every response body is made here and checked before it leaves.
// ------------------------------------------------------------------------------------------------
type ClassResult = "none_counted" | "counted" | "unknown" | "inconclusive";
export interface Meta {
  runId: number;
  mode: "dry_run" | "real";
  dataSource: "synthetic" | "container_home";
  buildSha: string;
  control: "passed" | "failed";
  uptimeS: number;
  claudeConfigDirSet: boolean;
  rootsDistinct: boolean;
  rootsNote: "none" | "env_home_rejected" | "homedir_unavailable";
}
const ERROR_CLASSES = ["unavailable", "unauthorized", "sunset", "payload_too_large", "invalid_json", "invalid_body", "invalid_mode", "build_mismatch", "young_container", "busy", "rate_limited", "control_failed", "internal"] as const;
export type ErrorClass = (typeof ERROR_CLASSES)[number];

function classResult(scan: InternalScan, id: ClassId, witness: boolean): ClassResult {
  const a = scan.classes[id];
  if (a.visited && a.entries > 0) return "counted"; // a lower bound is still a count, even when the class was cut off
  if (!a.visited || a.cut || a.errors > 0 || (a.entries === 0 && a.symlink > 0)) return "unknown"; // a link may lead to content
  if ((TRIGGER_CLASSES as readonly string[]).includes(id) && !witness) return "inconclusive";
  return "none_counted";
}

export function buildResult(scan: InternalScan, m: Meta) {
  const witness = WITNESS_CLASSES.some((c) => scan.classes[c].entries > 0);
  const results = Object.fromEntries(CLASS_IDS.map((c) => [c, classResult(scan, c, witness)])) as Record<ClassId, ClassResult>;
  const anyTrigger = TRIGGER_CLASSES.some((c) => scan.classes[c].entries > 0);
  const anyUnknown = TRIGGER_CLASSES.some((c) => results[c] === "unknown");
  const body = {
    schema_version: SCHEMA_VERSION,
    ok: true as const,
    run_id: m.runId,
    mode: m.mode,
    data_source: m.dataSource,
    build_sha: m.buildSha,
    control: m.control,
    evidence: m.uptimeS < YOUNG_UPTIME_S ? ("young" as const) : ("mature" as const),
    uptime_bucket: uptimeBucket(m.uptimeS),
    sunset_utc: SUNSET_UTC,
    truncated: scan.truncated,
    truncation_reason: scan.reason ?? "none",
    snapshot: "non_atomic" as const,
    mode_bits_semantics: "file_mode_only_not_reachability" as const,
    interpretation: INTERPRETATION,
    claude_config_dir_set: m.claudeConfigDirSet,
    outer_wrap_cohorts: "unmeasured" as const,
    roots: scan.roots.map((r) => ({ label: r.label, root_present: r.present, root_listable: r.listable })),
    roots_distinct: m.rootsDistinct,
    roots_note: m.rootsNote,
    activity_witness: witness,
    trigger_class_nonzero: anyTrigger
      ? "true"
      : anyUnknown
        ? "unknown"
        : TRIGGER_CLASSES.some((c) => results[c] === "inconclusive")
          ? "inconclusive"
          : "false",
    classes: CLASS_IDS.map((c) => ({
      class: c,
      n_entries: bucketCount(scan.classes[c].entries),
      n_mode_bits_group_r: bucketCount(scan.classes[c].groupR),
      n_mode_bits_other_r: bucketCount(scan.classes[c].otherR),
      n_symlink: bucketCount(scan.classes[c].symlink),
      errors: bucketCount(scan.classes[c].errors),
      absent: scan.classes[c].absent,
      class_result: results[c],
    })),
  };
  return body;
}
export type CensusResult = ReturnType<typeof buildResult>;

export function buildFailure(errorClass: ErrorClass) {
  return { schema_version: SCHEMA_VERSION, ok: false as const, error_class: errorClass, interpretation: INTERPRETATION };
}

const BUCKETS = new Set(["0", "1-4", "5-19", "20-99", "100-999", "1000+"]);
const CLASS_RESULTS = new Set<string>(["none_counted", "counted", "unknown", "inconclusive"]);
const REASONS = new Set<string>(["none", "entry_cap", "time_cap", "load_shed", "class_budget"]);
const OK_KEYS = new Set(["schema_version", "ok", "run_id", "mode", "data_source", "build_sha", "control", "evidence", "uptime_bucket", "sunset_utc", "truncated", "truncation_reason", "snapshot", "mode_bits_semantics", "interpretation", "claude_config_dir_set", "outer_wrap_cohorts", "roots", "roots_distinct", "roots_note", "activity_witness", "trigger_class_nonzero", "classes"]);

/** Throws (message is constant) when a value is outside the closed allowlist. The route then answers 500. */
export function assertAllowlisted(body: CensusResult | ReturnType<typeof buildFailure>): void {
  const bad = (): never => {
    throw new Error("home-census allowlist violation");
  };
  if (body.ok === false) {
    if (!ERROR_CLASSES.includes(body.error_class) || body.interpretation !== INTERPRETATION || Object.keys(body).length !== 4) bad();
    return;
  }
  for (const k of Object.keys(body)) if (!OK_KEYS.has(k)) bad();
  if (Object.keys(body).length !== OK_KEYS.size) bad();
  if (!Number.isSafeInteger(body.run_id) || body.run_id < 1 || body.run_id > 1e9) bad();
  if (!(body.build_sha === "dev" || /^[0-9a-f]{40}$/.test(body.build_sha))) bad();
  if (!["dry_run", "real"].includes(body.mode) || !["synthetic", "container_home"].includes(body.data_source)) bad();
  if (!REASONS.has(body.truncation_reason)) bad();
  if (!["true", "false", "unknown", "inconclusive"].includes(body.trigger_class_nonzero)) bad();
  if (!Array.isArray(body.classes) || body.classes.length !== CLASS_IDS.length) bad();
  for (const c of body.classes) {
    if (Object.keys(c).length !== 8) bad();
    if (!(CLASS_IDS as readonly string[]).includes(c.class) || !CLASS_RESULTS.has(c.class_result)) bad();
    for (const k of ["n_entries", "n_mode_bits_group_r", "n_mode_bits_other_r", "n_symlink", "errors"] as const) if (!BUCKETS.has(c[k])) bad();
    if (typeof c.absent !== "boolean") bad();
  }
  for (const r of body.roots) if (Object.keys(r).length !== 3 || !["env_home", "home_soleur", "root"].includes(r.label)) bad();
}

// ------------------------------------------------------------------------------------------------
// The single emitter: one Sentry event + one pino line
// ------------------------------------------------------------------------------------------------
export interface LogDest {
  write(chunk: string): unknown;
}
type Outcome = "ok" | "truncated" | "young" | "failed" | "refused";

let defaultLogger: ReturnType<typeof makeCensusLogger> | undefined;
function makeCensusLogger(dest?: LogDest) {
  // A dedicated instance: base undefined drops pid and hostname, timestamp false drops the time field,
  // level warn so Vector's `level >= 40` filter ships the line, a synchronous destination so the line
  // is written before the response (and a full pipe drops the line instead of blocking the loop: retryEAGAIN false).
  // It has no Sentry-mirroring hook, so a warn line makes no breadcrumb.
  return pino({ level: "warn", base: undefined, timestamp: false }, dest ?? pino.destination({ dest: 1, sync: true, retryEAGAIN: () => false }));
}
// The default (stdout) logger is built once per process; a test-injected destination gets its own instance.
function censusLogger(dest?: LogDest) {
  return dest ? makeCensusLogger(dest) : (defaultLogger ??= makeCensusLogger());
}

function stripToAllowlist(event: Sentry.ErrorEvent, keep: { message: string; level: Sentry.SeverityLevel; tags: Record<string, string>; extra?: Record<string, unknown> }): Sentry.ErrorEvent {
  // BUILT from an allowlist and returned (returning null would drop the event).
  const out: Sentry.ErrorEvent = { message: keep.message, level: keep.level, tags: keep.tags } as Sentry.ErrorEvent;
  if (event.event_id) out.event_id = event.event_id;
  if (event.timestamp) out.timestamp = event.timestamp;
  if (event.platform) out.platform = event.platform;
  if (event.release) out.release = event.release;
  if (event.environment) out.environment = event.environment;
  if (keep.extra) out.extra = keep.extra;
  return out;
}

function sentryEmit(message: string, level: Sentry.SeverityLevel, tags: Record<string, string>, extra?: Record<string, unknown>): void {
  try {
    Sentry.withIsolationScope((iso) => {
      iso.clear();
      Sentry.withScope((scope) => {
        scope.addEventProcessor((event) => stripToAllowlist(event as Sentry.ErrorEvent, { message, level, tags, extra }));
        scope.setTags(tags);
        Sentry.captureMessage(message, level);
      });
    });
  } catch {
    // observability must never break the caller; no value is logged
  }
}

function emitResult(result: CensusResult, outcome: Outcome, deps: CensusDeps): void {
  try {
    censusLogger(deps.logDest).warn({ outcome, ...result }, MESSAGE);
  } catch {
    // never throws into the request
  }
  // A synthetic dry_run is never a finding: only a REAL scan with a counted trigger class is a warning.
  const nonzero = result.mode === "real" && result.trigger_class_nonzero === "true";
  const level: Sentry.SeverityLevel = result.control === "failed" ? "error" : nonzero ? "warning" : "info";
  const tags = {
    run_id: String(result.run_id),
    data_source: result.data_source,
    evidence: result.evidence,
    truncated: String(result.truncated),
    control: result.control,
    mode: result.mode,
    trigger_class_nonzero: result.trigger_class_nonzero,
  };
  const g = globalThis as Record<symbol, unknown>;
  if (result.mode === "dry_run") {
    const key = Symbol.for("soleur.homeCensus.dryRunSentry");
    const last = typeof g[key] === "number" ? (g[key] as number) : 0;
    const t = deps.now();
    if (level !== "error" && t - last < DRY_RUN_SENTRY_GAP_MS && last !== 0) return; // a failed control is never throttled away
    g[key] = t;
  }
  // Flat and shallow on purpose: Sentry normalizes `extra` to depth 3 and would turn the class array into "[Object]".
  const extra = {
    n_entries: Object.fromEntries(result.classes.map((c) => [c.class, c.n_entries])),
    class_result: Object.fromEntries(result.classes.map((c) => [c.class, c.class_result])),
    uptime_bucket: result.uptime_bucket,
    truncation_reason: result.truncation_reason,
    activity_witness: String(result.activity_witness),
  };
  sentryEmit(MESSAGE, level, tags, extra);
}

function emitFailure(errorClass: ErrorClass, mode: "dry_run" | "real" | "unknown", level: Sentry.SeverityLevel, deps: CensusDeps): void {
  try {
    censusLogger(deps.logDest).warn({ outcome: "refused" satisfies Outcome, schema_version: SCHEMA_VERSION, ok: false, error_class: errorClass, mode }, REFUSED_MESSAGE);
  } catch {
    // never throws into the request
  }
  sentryEmit(REFUSED_MESSAGE, level, { error_class: errorClass, mode });
}

// ------------------------------------------------------------------------------------------------
// The request handler (the route is a one-line wrapper; route files may export only HTTP methods)
// ------------------------------------------------------------------------------------------------
export interface CensusDeps {
  fs: CensusFs;
  env: Record<string, string | undefined>;
  homedir: () => string;
  now: () => number;
  uptime: () => number;
  entryCap?: number;
  timeCapMs?: number;
  yieldFn?: () => Promise<void>;
  loadShed?: () => boolean;
  /** Always-present directory listed on the real adapter before a real scan. */
  canaryDir: string;
  /** Filesystem used for the canary only; tests inject a fake, production uses the real adapter. */
  canaryFs?: CensusFs;
  logDest?: LogDest;
  scan?: ScanFn;
}

// The synthetic tree is immutable: build it once per process, not once per request.
let syntheticCache: { fs: CensusFs; root: string } | undefined;
const syntheticFs = () => (syntheticCache ??= buildSyntheticFs());

const REAL_FS: CensusFs = { lstat: (p) => fsLstat(p), opendir: (p) => fsOpendir(p) };

export function defaultCensusDeps(): CensusDeps {
  return {
    fs: REAL_FS,
    env: process.env as Record<string, string | undefined>,
    homedir: osHomedir,
    now: () => Date.now(),
    uptime: () => process.uptime(),
    canaryDir: "/etc",
  };
}

function respond(status: number, body: CensusResult | ReturnType<typeof buildFailure>): Response {
  assertAllowlisted(body);
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json", "cache-control": "no-store" },
  });
}

const HEX40 = /^[0-9a-f]{40}$/;
const inflightKey = Symbol.for("soleur.homeCensus.inflight");
const limiterKey = Symbol.for("soleur.homeCensus.limiter");

export async function handleHomeCensus(request: Request, deps: CensusDeps = defaultCensusDeps()): Promise<Response> {
  const g = globalThis as Record<symbol, unknown>;
  const fail = (status: number, errorClass: ErrorClass, mode: "dry_run" | "real" | "unknown" = "unknown", emit = false): Response => {
    if (emit) emitFailure(errorClass, mode, "warning", deps);
    return respond(status, buildFailure(errorClass));
  };
  try {
    // 1. authenticate (uniform 401 for an absent or wrong token; 503 when the secret is not configured)
    const secret = readInternalBearerSecret();
    if (!secret) return fail(503, "unavailable");
    if (!bearerMatches(request.headers.get("authorization"), secret)) return fail(401, "unauthorized");

    // 2. sunset
    if (deps.now() >= Date.parse(SUNSET_UTC)) return fail(410, "sunset");

    // 3. parse (bounded, strict; the body is never echoed). Content-Length is checked before the body is read.
    if (Number(request.headers.get("content-length")) > MAX_BODY_BYTES) return fail(413, "payload_too_large");
    let raw: string;
    try {
      raw = await request.text();
    } catch {
      return fail(400, "invalid_json");
    }
    if (Buffer.byteLength(raw, "utf8") > MAX_BODY_BYTES) return fail(413, "payload_too_large");
    let parsed: unknown;
    try {
      parsed = JSON.parse(raw);
    } catch {
      return fail(400, "invalid_json");
    }
    if (typeof parsed !== "object" || parsed === null || Array.isArray(parsed)) return fail(400, "invalid_body");
    const body = parsed as Record<string, unknown>;
    const allowedKeys = new Set(["run_id", "mode", "expect_build_sha", "accept_young"]);
    if (Object.keys(body).some((k) => !allowedKeys.has(k))) return fail(400, "invalid_body");
    const runId = body.run_id;
    if (typeof runId !== "number" || !Number.isSafeInteger(runId) || runId < 1 || runId > 1e9) return fail(400, "invalid_body");

    // 4. mode
    const modeRaw = body.mode === undefined ? "dry_run" : body.mode;
    if (modeRaw !== "dry_run" && modeRaw !== "real") return fail(400, "invalid_mode");
    const mode: "dry_run" | "real" = modeRaw;
    if (body.accept_young !== undefined && typeof body.accept_young !== "boolean") return fail(400, "invalid_body");
    if (body.expect_build_sha !== undefined && (typeof body.expect_build_sha !== "string" || !HEX40.test(body.expect_build_sha))) return fail(400, "invalid_body");

    const uptimeS = deps.uptime();
    const buildSha = deps.env.BUILD_SHA && (HEX40.test(deps.env.BUILD_SHA) || deps.env.BUILD_SHA === "dev") ? deps.env.BUILD_SHA : "dev";
    const { roots, rootsDistinct, rootsNote } = resolveRoots(deps.env, deps.homedir);
    const claudeConfigDirSet = typeof deps.env.CLAUDE_CONFIG_DIR === "string" && deps.env.CLAUDE_CONFIG_DIR !== "";
    const scanFn = deps.scan ?? scanHome;
    const common = { entryCap: deps.entryCap, timeCapMs: deps.timeCapMs, yieldFn: deps.yieldFn, loadShed: deps.loadShed };
    // The known-answer control always runs with the production caps: a small injected cap must truncate the real scan, not the control.
    const controlCommon = { yieldFn: deps.yieldFn, loadShed: deps.loadShed };

    if (mode === "dry_run") {
      // A synthetic in-memory HOME only: no real filesystem call, no run_id consumed, real uptime/build/sunset.
      const synth = syntheticFs();
      const { scan } = await scanFn({ ...controlCommon, fs: synth.fs, roots: [{ label: "env_home", path: synth.root }] });
      const result = buildResult(scan, { runId, mode, dataSource: "synthetic", buildSha, control: controlMatches(scan) ? "passed" : "failed", uptimeS, claudeConfigDirSet, rootsDistinct: true, rootsNote: "none" });
      assertAllowlisted(result); // before any sink, so a violation reaches none of them
      emitResult(result, "ok", deps);
      return respond(200, result);
    }

    // 5. real: build must match, then the young gate, then ONE synchronous claim step (no await between check and set)
    if (body.expect_build_sha !== buildSha) return fail(409, "build_mismatch", mode, true);
    if (uptimeS < YOUNG_UPTIME_S && body.accept_young !== true) return fail(409, "young_container", mode, true);

    const now = deps.now();
    const lim = (g[limiterKey] as { starts: number[] } | undefined) ?? { starts: [] };
    g[limiterKey] = lim;
    if (g[inflightKey]) return fail(409, "busy", mode, true);
    if (lim.starts.length >= LIMITER_MAX_REAL || (lim.starts.length > 0 && now - lim.starts[lim.starts.length - 1] < LIMITER_GAP_MS)) {
      return fail(429, "rate_limited", mode, true);
    }
    g[inflightKey] = true;
    lim.starts.push(now);
    let release = true;
    let scanStarted = false;
    try {
      // 6. positive control (known-answer in-memory scan) and the real-adapter canary
      const synth = syntheticFs();
      const controlScan = await scanFn({ ...controlCommon, fs: synth.fs, roots: [{ label: "env_home", path: synth.root }] });
      const canary = await canaryOk(deps.canaryFs ?? REAL_FS, deps.canaryDir);
      if (!controlMatches(controlScan.scan) || !canary) {
        // No result object is emitted: the only counts here are the synthetic control's, and they must not be labelled as the HOME's.
        emitFailure("control_failed", mode, "error", deps);
        return fail(503, "control_failed", mode);
      }
      // 7. scan; the in-flight flag is held until any fs op abandoned by the cap has settled
      scanStarted = true;
      const { scan, settled } = await scanFn({ ...common, fs: deps.fs, roots });
      release = false;
      void settled.then(() => {
        g[inflightKey] = false;
      });
      const result = buildResult(scan, { runId, mode, dataSource: "container_home", buildSha, control: "passed", uptimeS, claudeConfigDirSet, rootsDistinct, rootsNote });
      const outcome: Outcome = scan.truncated ? "truncated" : result.evidence === "young" ? "young" : "ok";
      assertAllowlisted(result); // before any sink, so a violation reaches none of them
      emitResult(result, outcome, deps);
      return respond(200, result);
    } finally {
      // The slot is consumed when a real scan STARTS: any exit before that (control or canary failure, a throw) refunds it.
      if (!scanStarted) lim.starts.pop();
      if (release) g[inflightKey] = false;
    }
  } catch {
    // Never rethrow, never print: constant answer and a constant-message Sentry error with no value.
    sentryEmit("home-census internal error", "error", { error_class: "internal" });
    return new Response(JSON.stringify(buildFailure("internal")), { status: 500, headers: { "content-type": "application/json", "cache-control": "no-store" } });
  }
}
