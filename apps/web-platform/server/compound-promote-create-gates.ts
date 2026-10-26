// WikiSkill Phase 2 (#10550) -- the create arm's gates that SPAWN a process or read the clone.
//
// Two repo scripts run through ONE helper, `spawnRepoScript`: the skill security scan and the README count sync. The
// Cursor generator does not run in the runner image (Phase 0, CTO G3), so the stub is rendered by the pure renderer in
// `compound-promote-create.ts`.
//
// Contract (Guard 1):
//   - the spawn environment is an ALLOWLIST (no installation token, no secret, no GIT_* location variable);
//   - the script must be a REGULAR file inside the real repo root (no symlink, no traversal), with a timeout and a
//     group kill;
//   - the scan gate accepts ONLY exit 0 AND a first stdout line exactly `# skill-security-scan verdict: LOW-RISK`
//     (the scanner exits 0 even on HIGH-RISK and returns LOW-RISK on EMPTY input, so both are checked here);
//   - the README sync may change exactly the two README files, by digits only;
//   - every refusal is a returned value with a closed class/detail; infrastructure failures (spawn error, git
//     failure) are additionally mirrored to Sentry so a gate that cannot run is never silent.
//
// Nothing here runs a model, reads a secret or touches the network (the scanner runs offline).

import { execFile, spawn } from "node:child_process";
import { accessSync, constants, statSync } from "node:fs";
import { lstat, readFile, readlink, realpath, stat } from "node:fs/promises";
import { createHash } from "node:crypto";
import { tmpdir } from "node:os";
import { delimiter, isAbsolute, join, sep } from "node:path";
import { reportSilentFallback } from "@/server/observability";
import { SYNTHETIC_CHECK_NAMES } from "@/server/inngest/functions/_cron-safe-commit";
import { GIT_HARDENING_ARGS, GIT_HARDENING_ENV } from "@/server/inngest/functions/_git-hardening";
import { createPathList } from "@/server/compound-promote-create";

/** The Sentry feature name of the create arm and its gates (the arm re-exports it as `CREATE_ARM_FEATURE`; a leaf constant here avoids an import cycle). */
export const CREATE_FEATURE_NAME = "cron-compound-promote";

// =============================================================================
// Constants
// =============================================================================

export const SKILL_SCAN_SCRIPT = "plugins/soleur/skills/skill-security-scan/scripts/run-scan.sh";
export const README_SYNC_SCRIPT = "scripts/sync-readme-counts.sh";
export const README_PATHS = ["README.md", "plugins/soleur/README.md"] as const;
/** The exact first stdout line of an accepted scan. Anything else, however similar, is refused. */
export const SCAN_LOW_RISK_LINE = "# skill-security-scan verdict: LOW-RISK";
const SCAN_HIGH_RISK_LINE = "# skill-security-scan verdict: HIGH-RISK";
const SCAN_REVIEW_LINE = "# skill-security-scan verdict: REVIEW";
/** The scanner returns LOW-RISK on empty input; a rendered skill file is never smaller than this. */
export const SCAN_MIN_INPUT_BYTES = 200;
export const SCAN_TIMEOUT_MS = 60_000;
export const README_SYNC_TIMEOUT_MS = 30_000;
/**
 * Tools the scripts the gates spawn need (bash plus the coreutils/jq they shell to). Checked before any scan. The
 * closed set doubles as the vocabulary of `missing_tool_names` in the Sentry extra (a name outside it is never echoed).
 */
export const SCAN_REQUIRED_TOOLS = [
  "bash", "jq", "sha256sum", "awk", "sed", "grep", "find", "mktemp", "tr", "timeout",
  "cut", "head", "date", "cat", "rm", "mv", "mkdir", "id", "dirname", "basename",
] as const;
export const SPAWN_MAX_STDOUT_BYTES = 1024 * 1024;
const SPAWN_MAX_STDERR_BYTES = 4096;
/** Largest single file the collector will hand to `safeCommitAndPr` as expected content. */
export const COLLECT_MAX_FILE_BYTES = 2 * 1024 * 1024;
export const GIT_TIMEOUT_MS = 30_000;
/** The largest timeout one git call may be given (a caller with a deadline is still capped here). */
export const GIT_MAX_TIMEOUT_MS = GIT_TIMEOUT_MS * 2;
const GIT_MAX_BUFFER = 16 * 1024 * 1024;

/**
 * Guard 1 row 8: the create PR must NOT inherit the edit arm's synthetic checks. A faked green
 * `skill-security-scan PR gate` is the #8203 class; a faked `test` would hide a real components.test failure.
 */
export const CREATE_EXCLUDED_SYNTHETIC_CHECKS = ["test", "skill-security-scan PR gate"] as const;

export function createSyntheticCheckNames(): readonly string[] {
  const all: readonly string[] = SYNTHETIC_CHECK_NAMES;
  for (const x of CREATE_EXCLUDED_SYNTHETIC_CHECKS) {
    // A rename in the edit arm's list would turn the exclusion into a silent no-op; fail loudly instead.
    if (!all.includes(x)) throw new Error(`create: excluded synthetic check is not in SYNTHETIC_CHECK_NAMES: ${x}`);
  }
  return all.filter((n) => !(CREATE_EXCLUDED_SYNTHETIC_CHECKS as readonly string[]).includes(n));
}

// =============================================================================
// Scrubbed environment and the shared spawn helper
// =============================================================================

type BaseEnv = Readonly<Record<string, string | undefined>>;

// Names an extra may never carry: anything secret-shaped, a GitHub/Anthropic/Doppler credential namespace, or a git
// location variable (a git child honours GIT_DIR over cwd and -C).
const FORBIDDEN_EXTRA_RE = /TOKEN|SECRET|PASSWORD|PASSWD|CREDENTIAL|API_?KEY|PRIVATE|^GH_|^GITHUB_|^ANTHROPIC|^DOPPLER|^GIT_/i;
const EXTRA_NAME_RE = /^[A-Z][A-Z0-9_]*$/;

/**
 * The environment of every gate child. An ALLOWLIST from the base environment (PATH, LANG, LC_ALL, TMPDIR, HOME) plus
 * explicit extras; nothing else is inherited, so no installation token, API key or Doppler credential can reach a
 * script that runs in a clone. HOME is NOT the real home (no `~/.config/gh`, no git config): it is the temp dir.
 */
export function buildScrubbedEnv(extra: Readonly<Record<string, string>>, base: BaseEnv = process.env): Record<string, string> {
  const env: Record<string, string> = {
    PATH: base.PATH ?? "/usr/bin:/bin",
    LANG: base.LANG ?? "C.UTF-8",
    LC_ALL: "C.UTF-8",
    TMPDIR: tmpdir(),
    HOME: tmpdir(),
  };
  for (const [name, value] of Object.entries(extra)) {
    if (!EXTRA_NAME_RE.test(name) || FORBIDDEN_EXTRA_RE.test(name) || typeof value !== "string" || value.includes("\u0000")) {
      throw new Error("scrubbed env: refused an extra variable");
    }
    env[name] = value;
  }
  return env;
}

export type SpawnScriptResult =
  | { kind: "exit"; code: number | null; signal: string | null; stdout: string; stderr: string }
  | { kind: "timeout" }
  | { kind: "spawn-error"; detail: string }
  | { kind: "script-not-regular" }
  | { kind: "output-overflow" };

export interface SpawnRepoScriptOpts {
  repoRoot: string;
  /** Repo-relative path of the script. Must be a regular file under the REAL repo root. */
  script: string;
  stdin?: string;
  extraEnv: Readonly<Record<string, string>>;
  timeoutMs: number;
  maxStdoutBytes?: number;
  baseEnv?: BaseEnv;
}

/**
 * Resolve `rel` under the real `repoRoot` to an absolute path, only if every component is a real (non-symlink) entry
 * and the final one is a regular file. Returns the absolute path or `null`.
 */
async function resolveRegularFile(repoRoot: string, rel: string): Promise<{ abs: string; size: number } | null> {
  if (rel === "" || isAbsolute(rel) || rel.split("/").includes("..")) return null;
  let root: string;
  try {
    root = await realpath(repoRoot);
  } catch {
    return null;
  }
  const abs = join(root, rel);
  try {
    const st = await lstat(abs);
    if (!st.isFile()) return null; // lstat: a symlink is not a regular file
    if ((await realpath(abs)) !== abs) return null; // a symlinked directory component
    return { abs, size: st.size };
  } catch {
    return null;
  }
}

/**
 * The ONE place a repo script is spawned. `bash <script>` with cwd = the real repo root, the scrubbed environment,
 * stdin piped, bounded output, a timeout and a process-group kill (a backgrounded child dies with the script).
 */
export async function spawnRepoScript(o: SpawnRepoScriptOpts): Promise<SpawnScriptResult> {
  const file = await resolveRegularFile(o.repoRoot, o.script);
  if (!file) return { kind: "script-not-regular" };
  const root = await realpath(o.repoRoot);
  const env = buildScrubbedEnv(o.extraEnv, o.baseEnv ?? process.env);
  const maxOut = o.maxStdoutBytes ?? SPAWN_MAX_STDOUT_BYTES;
  return new Promise<SpawnScriptResult>((resolve) => {
    let settled = false;
    let stdout = "";
    let stdoutBytes = 0;
    let stderr = "";
    // A child environment is legitimately partial; the repo's ProcessEnv augmentation (NODE_ENV required) is for READING.
    const child = spawn("bash", [file.abs], {
      cwd: root,
      env: env as NodeJS.ProcessEnv,
      stdio: ["pipe", "pipe", "pipe"] as const,
      detached: true,
    });
    const killGroup = (): void => {
      try {
        if (child.pid !== undefined) process.kill(-child.pid, "SIGKILL");
      } catch {
        try {
          child.kill("SIGKILL");
        } catch {
          // already gone
        }
      }
    };
    const finish = (r: SpawnScriptResult): void => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      resolve(r);
    };
    const timer = setTimeout(() => {
      killGroup();
      finish({ kind: "timeout" });
    }, o.timeoutMs);
    child.stdout.setEncoding("utf8");
    child.stdout.on("data", (chunk: string) => {
      stdoutBytes += Buffer.byteLength(chunk, "utf8");
      if (stdoutBytes > maxOut) {
        killGroup();
        finish({ kind: "output-overflow" });
        return;
      }
      stdout += chunk;
    });
    child.stderr.setEncoding("utf8");
    child.stderr.on("data", (chunk: string) => {
      if (stderr.length < SPAWN_MAX_STDERR_BYTES) stderr = (stderr + chunk).slice(0, SPAWN_MAX_STDERR_BYTES);
    });
    child.on("error", (err: NodeJS.ErrnoException) => {
      // An interpreter that cannot be spawned is an infrastructure fault, not a verdict: surface it to Sentry.
      reportSilentFallback(err, { feature: CREATE_FEATURE_NAME, op: "create-gate-spawn", extra: { script: o.script, code: err.code ?? "unknown" } });
      finish({ kind: "spawn-error", detail: err.code ?? "unknown" });
    });
    child.on("close", (code, signal) => finish({ kind: "exit", code, signal, stdout, stderr }));
    child.stdin.on("error", () => {
      // EPIPE when the script exits without reading stdin: the exit status is the evidence, not this.
    });
    child.stdin.end(o.stdin ?? "");
  });
}

// =============================================================================
// Scan gate
// =============================================================================

export type PreflightResult = { ok: true } | { ok: false; missing: string[] };

/** Every tool the scanner shells to must be an executable regular file somewhere on `pathEnv`. */
export function preflightTools(pathEnv: string, tools: readonly string[] = SCAN_REQUIRED_TOOLS): PreflightResult {
  const dirs = pathEnv.split(delimiter).filter(Boolean);
  const missing = tools.filter((tool) => {
    for (const dir of dirs) {
      try {
        const p = join(dir, tool);
        if (statSync(p).isFile()) {
          accessSync(p, constants.X_OK);
          return false;
        }
      } catch {
        // not in this directory
      }
    }
    return true;
  });
  return missing.length === 0 ? { ok: true } : { ok: false, missing: [...missing] };
}

/** Process evidence of a failed gate script: the exit code and the signal NAME (closed: `SIG*`, else `other`). */
export interface ScriptEvidence {
  exit?: number;
  signal?: string;
}

function evidenceOf(r: SpawnScriptResult): ScriptEvidence {
  if (r.kind !== "exit") return {};
  return {
    ...(typeof r.code === "number" ? { exit: r.code } : {}),
    ...(r.signal ? { signal: /^SIG[A-Z0-9]{2,12}$/.test(r.signal) ? r.signal : "other" } : {}),
  };
}

export type ScanEvaluation = { ok: true } | ({ ok: false; detail: string } & ScriptEvidence);

/**
 * Accept ONLY exit 0 AND a first stdout line exactly equal to the LOW-RISK banner. Everything else is a refusal with
 * a closed detail. The first line is compared verbatim: no trimming, no case folding, no "contains".
 */
export function evaluateScanOutput(r: SpawnScriptResult): ScanEvaluation {
  if (r.kind === "timeout") return { ok: false, detail: "timeout" };
  if (r.kind === "spawn-error") return { ok: false, detail: "spawn-error" };
  if (r.kind === "script-not-regular") return { ok: false, detail: "script-not-regular" };
  if (r.kind === "output-overflow") return { ok: false, detail: "output-overflow" };
  if (r.code !== 0) return { ok: false, detail: "non-zero", ...evidenceOf(r) };
  if (r.stdout.trim() === "") return { ok: false, detail: "empty-output", ...evidenceOf(r) };
  const first = r.stdout.split("\n")[0];
  if (first === SCAN_LOW_RISK_LINE) return { ok: true };
  if (first === SCAN_HIGH_RISK_LINE) return { ok: false, detail: "high-risk", ...evidenceOf(r) };
  if (first === SCAN_REVIEW_LINE) return { ok: false, detail: "review", ...evidenceOf(r) };
  return { ok: false, detail: "unrecognised", ...evidenceOf(r) };
}

export type ScanResult =
  | { ok: true }
  | ({
      ok: false;
      detail: string;
      path?: string;
      /** Index of the refused file in `relPaths` (0 = SKILL.md, 1 = PURPOSE.md). */
      fileIndex?: number;
      /** Names of the missing tools, always members of `SCAN_REQUIRED_TOOLS`. */
      missing?: string[];
    } & ScriptEvidence);

export interface RunSkillScanOpts {
  repoRoot: string;
  /** Repo-relative paths of the files to scan (both rendered files; they must already be on disk). */
  relPaths: readonly string[];
  /** Existing directory OUTSIDE the clone where the scanner writes `.scan-meta.json`. */
  metaBase: string;
  timeoutMs?: number;
  baseEnv?: BaseEnv;
  /** Test seam (a spawn spy); defaults to the shared helper. */
  spawn?: typeof spawnRepoScript;
}

const scanRefusal = (detail: string, extra?: Omit<Extract<ScanResult, { ok: false }>, "ok" | "detail">): ScanResult => ({ ok: false, detail, ...extra });

/**
 * Run the offline skill security scan on EVERY file and require an explicit LOW-RISK for each. Order: non-empty file
 * list, meta base outside the clone, tool preflight, every input read and size-checked, then the scans one by one
 * (a failure stops the run and names the file).
 */
export async function runSkillScan(o: RunSkillScanOpts): Promise<ScanResult> {
  if (o.relPaths.length === 0) return scanRefusal("no-input");

  let meta: string;
  let root: string;
  try {
    meta = await realpath(o.metaBase);
    root = await realpath(o.repoRoot);
    if (!(await stat(meta)).isDirectory()) return scanRefusal("meta-base-invalid");
  } catch {
    return scanRefusal("meta-base-invalid");
  }
  if (meta === root || meta.startsWith(root + sep)) return scanRefusal("meta-base-invalid");

  const baseEnv = o.baseEnv ?? process.env;
  const pre = preflightTools(baseEnv.PATH ?? "");
  if (!pre.ok) return scanRefusal("missing-tool", { missing: pre.missing.filter((t) => (SCAN_REQUIRED_TOOLS as readonly string[]).includes(t)) });

  const inputs: Array<{ path: string; content: string }> = [];
  for (const rel of o.relPaths) {
    const file = await resolveRegularFile(o.repoRoot, rel);
    if (!file) return scanRefusal("input-unreadable", { path: rel, fileIndex: inputs.length });
    if (file.size < SCAN_MIN_INPUT_BYTES) return scanRefusal("input-too-small", { path: rel, fileIndex: inputs.length });
    inputs.push({ path: rel, content: await readFile(file.abs, "utf8") });
  }

  const run = o.spawn ?? spawnRepoScript;
  for (const [fileIndex, input] of inputs.entries()) {
    const result = await run({
      repoRoot: o.repoRoot,
      script: SKILL_SCAN_SCRIPT,
      stdin: input.content,
      extraEnv: { SKILL_SECURITY_SCAN_OFFLINE: "1", SKILL_SCAN_META_BASE: o.metaBase },
      timeoutMs: o.timeoutMs ?? SCAN_TIMEOUT_MS,
      baseEnv,
    });
    const verdict = evaluateScanOutput(result);
    if (!verdict.ok) {
      const { ok: _ok, detail, ...evidence } = verdict;
      return scanRefusal(detail, { path: input.path, fileIndex, ...evidence });
    }
  }
  return { ok: true };
}

// =============================================================================
// Git view of the clone (hardened, scrubbed)
// =============================================================================

/** Closed evidence of a failed git call: the exit status, the signal NAME (closed `SIG*` pattern) and whether the timeout fired. Never stderr. */
export interface GitEvidence {
  exit?: number;
  signal?: string;
  timedOut: boolean;
}

export type GitResult = { ok: true; stdout: string } | ({ ok: false } & GitEvidence);

export interface RunGitOpts {
  baseEnv?: BaseEnv;
  /** Clamped to `[1, GIT_MAX_TIMEOUT_MS]` (the default is `GIT_TIMEOUT_MS`); a caller with a deadline passes the time it has left. */
  timeoutMs?: number;
}

/** The effective timeout of one git call: the request (default `GIT_TIMEOUT_MS`), at least 1 ms and at most `GIT_MAX_TIMEOUT_MS`. */
export function clampGitTimeout(requested: number | undefined): number {
  return Math.max(1, Math.min(requested ?? GIT_TIMEOUT_MS, GIT_MAX_TIMEOUT_MS));
}

const SIGNAL_NAME_RE = /^SIG[A-Z0-9]{2,12}$/;
const GIT_SUB_RE = /^[a-z][a-z-]{0,23}$/;

/**
 * The ONE hardened, scrubbed git invocation of the create arm (the arm's clone hygiene uses it too): hardening args,
 * hardening env, the scrubbed environment (no token, no `GIT_*` location variable), a bounded buffer and timeout.
 *
 * A failure is returned as CLOSED evidence (`exit`, `signal`, `timedOut`) and mirrored to Sentry (`create-gate-git`) as
 * a SYNTHETIC Error plus a closed `extra`. The raw execFile Error is never forwarded: its message carries the command
 * line and git's stderr, and a failed fetch against the tokenized origin echoes the remote URL there.
 */
export function runGit(root: string, args: readonly string[], opts: RunGitOpts = {}): Promise<GitResult> {
  const env = { ...buildScrubbedEnv({}, opts.baseEnv ?? process.env), ...GIT_HARDENING_ENV, GIT_TERMINAL_PROMPT: "0" } as unknown as NodeJS.ProcessEnv;
  const timeout = clampGitTimeout(opts.timeoutMs);
  return new Promise((resolve) => {
    execFile("git", [...GIT_HARDENING_ARGS, "-C", root, ...args], { env, maxBuffer: GIT_MAX_BUFFER, timeout, encoding: "utf8" }, (err, stdout) => {
      if (err) {
        const e = err as NodeJS.ErrnoException & { killed?: boolean; signal?: string | null };
        const exit = typeof e.code === "number" && Number.isInteger(e.code) ? e.code : undefined;
        const signal = typeof e.signal === "string" && e.signal !== "" ? (SIGNAL_NAME_RE.test(e.signal) ? e.signal : "other") : undefined;
        const killed = e.killed === true;
        // execFile kills with SIGTERM when the timeout fires; a kill for any other reason (maxBuffer) is not a timeout.
        const timedOut = killed && e.signal === "SIGTERM" && e.code !== "ERR_CHILD_PROCESS_STDIO_MAXBUFFER";
        const sub = typeof args[0] === "string" && GIT_SUB_RE.test(args[0]) ? args[0] : "other";
        reportSilentFallback(new Error(`git ${sub} failed`), {
          feature: CREATE_FEATURE_NAME,
          op: "create-gate-git",
          extra: { sub, ...(exit === undefined ? {} : { exit }), ...(signal === undefined ? {} : { signal }), killed, timedOut },
        });
        resolve({ ok: false, ...(exit === undefined ? {} : { exit }), ...(signal === undefined ? {} : { signal }), timedOut });
        return;
      }
      resolve({ ok: true, stdout });
    });
  });
}

/** Every path git reports as changed, deleted or untracked (one per file, no rename detection). */
async function changedPaths(root: string, baseEnv: BaseEnv): Promise<string[] | null> {
  const r = await runGit(root, ["status", "--porcelain=v1", "-z", "-uall", "--no-renames"], { baseEnv });
  if (!r.ok) return null;
  return r.stdout
    .split("\u0000")
    .filter((e) => e.length > 3)
    .map((e) => e.slice(3));
}

export type CloneSnapshot = Map<string, string>;

/** path -> content hash (or "deleted" / "link:<target>") for every path git reports; the basis for "what did this step change". */
export async function snapshotClone(root: string, baseEnv: BaseEnv = process.env): Promise<CloneSnapshot | null> {
  const paths = await changedPaths(root, baseEnv);
  if (!paths) return null;
  const out: CloneSnapshot = new Map();
  for (const p of paths) {
    try {
      const abs = join(root, p);
      const st = await lstat(abs);
      out.set(p, st.isSymbolicLink() ? `link:${await readlink(abs)}` : createHash("sha256").update(await readFile(abs)).digest("hex"));
    } catch {
      out.set(p, "deleted");
    }
  }
  return out;
}

// =============================================================================
// README count sync
// =============================================================================

export type ReadmeSyncResult =
  | { ok: true }
  | ({
      ok: false;
      detail: string;
      /** `unexpected-change`: how many non-README paths differ. `no-change`: how many README files changed (0 or 1). */
      changedCount?: number;
    } & ScriptEvidence);

export interface SyncReadmeCountsOpts {
  repoRoot: string;
  timeoutMs?: number;
  baseEnv?: BaseEnv;
  spawn?: typeof spawnRepoScript;
  /**
   * A clone snapshot taken BEFORE the scanner ran. When given it is the baseline for the "nothing else changed" guard,
   * so a scan-time write to any non-README path is caught too; otherwise the baseline is taken here, before the sync.
   */
  since?: CloneSnapshot;
}

const readmeRefusal = (detail: string, extra?: Omit<Extract<ReadmeSyncResult, { ok: false }>, "ok" | "detail">): ReadmeSyncResult => ({ ok: false, detail, ...extra });

/** Same line count, and every differing line differs only in its digit runs. */
export function digitOnlyLineDiff(before: string, after: string): boolean {
  const a = before.split("\n");
  const b = after.split("\n");
  if (a.length !== b.length) return false;
  for (let i = 0; i < a.length; i++) {
    if (a[i] !== b[i] && a[i].replace(/\d+/g, "#") !== b[i].replace(/\d+/g, "#")) return false;
  }
  return true;
}

async function readRegularUtf8(root: string, rel: string): Promise<string | null> {
  const f = await resolveRegularFile(root, rel);
  if (!f) return null;
  try {
    return await readFile(f.abs, "utf8");
  } catch {
    return null;
  }
}

/**
 * Run `scripts/sync-readme-counts.sh` in the clone and require that it changed EXACTLY the two README files, each by
 * digits only. (The script itself edits only those two files; the unexpected-change guard is the tripwire for a
 * script defect or a scan-time write, not a description of normal behaviour.)
 */
export async function syncReadmeCounts(o: SyncReadmeCountsOpts): Promise<ReadmeSyncResult> {
  const baseEnv = o.baseEnv ?? process.env;
  const before: Record<string, string> = {};
  for (const rel of README_PATHS) {
    const text = await readRegularUtf8(o.repoRoot, rel);
    if (text === null) return readmeRefusal("readme-unreadable");
    before[rel] = text;
  }
  const snapBefore = o.since ?? (await snapshotClone(o.repoRoot, baseEnv));
  if (!snapBefore) return readmeRefusal("git-failed");

  const run = o.spawn ?? spawnRepoScript;
  const r = await run({ repoRoot: o.repoRoot, script: README_SYNC_SCRIPT, extraEnv: {}, timeoutMs: o.timeoutMs ?? README_SYNC_TIMEOUT_MS, baseEnv });
  if (r.kind === "timeout") return readmeRefusal("timeout");
  if (r.kind === "script-not-regular") return readmeRefusal("script-not-regular");
  if (r.kind !== "exit" || r.code !== 0) return readmeRefusal("script-failed", evidenceOf(r));

  const snapAfter = await snapshotClone(o.repoRoot, baseEnv);
  if (!snapAfter) return readmeRefusal("git-failed");
  const readmes = new Set<string>(README_PATHS);
  let unexpected = 0;
  for (const p of new Set([...snapBefore.keys(), ...snapAfter.keys()])) {
    if (readmes.has(p)) continue;
    if (snapBefore.get(p) !== snapAfter.get(p)) unexpected += 1;
  }
  if (unexpected > 0) return readmeRefusal("unexpected-change", { changedCount: unexpected });

  const after: Record<string, string> = {};
  for (const rel of README_PATHS) {
    const text = await readRegularUtf8(o.repoRoot, rel);
    if (text === null) return readmeRefusal("readme-unreadable");
    after[rel] = text;
  }
  // The new skill must move BOTH counts; a README the script left alone means the counts and the tree disagree.
  const changed = README_PATHS.filter((rel) => after[rel] !== before[rel]).length;
  if (changed < README_PATHS.length) return readmeRefusal("no-change", { changedCount: changed });
  if (README_PATHS.some((rel) => !digitOnlyLineDiff(before[rel], after[rel]))) return readmeRefusal("non-digit-change");
  return { ok: true };
}

// =============================================================================
// Content collector (the bytes handed to safeCommitAndPr)
// =============================================================================

export type CollectResult =
  | { ok: true; exactPaths: readonly string[]; expectedContent: Record<string, string> }
  | { ok: false; detail: string; index?: number };

export interface CollectCreateContentOpts {
  repoRoot: string;
  slug: string;
  baseEnv?: BaseEnv;
}

const collectRefusal = (detail: string, index?: number): CollectResult => (index === undefined ? { ok: false, detail } : { ok: false, detail, index });

/**
 * Read the six create paths from the clone as the exact strings `expectedContent` needs, and require that git sees
 * EXACTLY those six paths changed (a seventh changed path, a script or any stray file, is `changed-set-mismatch`).
 * Throws on an invalid slug (a programming error, not a model outcome).
 */
export async function collectCreateContent(o: CollectCreateContentOpts): Promise<CollectResult> {
  const paths = createPathList(o.slug);
  const expectedContent: Record<string, string> = {};
  for (const [index, rel] of paths.entries()) {
    const file = await resolveRegularFile(o.repoRoot, rel);
    if (!file) {
      let missing = false;
      try {
        await lstat(join(await realpath(o.repoRoot), rel));
      } catch {
        missing = true;
      }
      return collectRefusal(missing ? "path-missing" : "path-not-regular", index);
    }
    if (file.size === 0) return collectRefusal("path-empty", index);
    if (file.size > COLLECT_MAX_FILE_BYTES) return collectRefusal("path-too-large", index);
    const buf = await readFile(file.abs);
    const text = buf.toString("utf8");
    if (text.includes("\u0000")) return collectRefusal("path-nul", index);
    if (!Buffer.from(text, "utf8").equals(buf)) return collectRefusal("path-not-utf8", index);
    expectedContent[rel] = text;
  }
  const changed = await changedPaths(o.repoRoot, o.baseEnv ?? process.env);
  if (!changed) return collectRefusal("git-failed");
  const want = new Set<string>(paths);
  const got = new Set(changed);
  if (got.size !== want.size || [...want].some((p) => !got.has(p))) return collectRefusal("changed-set-mismatch");
  return { ok: true, exactPaths: paths, expectedContent };
}
