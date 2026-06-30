// ---------------------------------------------------------------------------
// On-disk git work-tree VALIDITY probes (ADR-044 dispatch-readiness, 2026-06-19).
//
// The Concierge dispatch readiness gate used to test mere `.git` PRESENCE
// (`existsSync(<ws>/.git)`). A directory named `.git` that exists but is not a
// valid git work tree (a partial/interrupted clone, or a leftover from a failed
// atomic-rename) passed that gate, so the self-heal/graft was skipped, the agent
// spawned into a corrupt repo, and `/soleur:go` Step 0.0's
// `git rev-parse --is-inside-work-tree` reported "no git repository" — silently.
//
// This module supplies TWO distinct probes (deepen-plan F1/F2), each with a
// deliberately narrow role:
//
//   1. `isValidGitWorkTree`  — SYNC structural fast-path gate. Replaces the
//      presence check on the hot path. Valid = `.git` is a FILE (a `gitdir:`
//      linked-worktree/submodule pointer — treated valid, never removed) OR a
//      directory containing BOTH `HEAD` and `objects`. A Start-Fresh `git init`
//      tree (HEAD+objects, no origin) is VALID and preserved.
//
//   2. `isEmptyCorruptGitDir` — SYNC POSITIVE fingerprint that ALONE authorizes
//      the destructive re-clone `rm`. True ONLY when `.git` is a DIRECTORY AND
//      `HEAD` is ENOENT AND `objects` is ENOENT. An EACCES/EIO blip on a
//      populated `.git`, or a `.git` FILE, returns false → never rm'd. An empty
//      `.git` has no objects = no commits to lose, so removing it is provably
//      safe.
//
// No installation token is needed — every probe is a local read-only filesystem
// operation.
// ---------------------------------------------------------------------------

import {
  lstatSync,
  existsSync,
  readFileSync,
  openSync,
  fstatSync,
  closeSync,
  constants,
  realpathSync,
} from "node:fs";
import { join, isAbsolute, resolve, sep } from "node:path";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import {
  reportAgentReadinessSelfStop,
  reportAgentReadinessProbeInconclusive,
} from "@/server/repo-resolver-divergence";

const execFileAsync = promisify(execFile);

/**
 * SYNC structural validity of `<workspacePath>/.git` — the hot-path gate.
 *
 * Returns true when `.git` is:
 *   - a FILE (a `gitdir:` pointer for a linked worktree/submodule — a real,
 *     non-removable tree we must never classify corrupt), OR
 *   - a DIRECTORY containing both `HEAD` and `objects` (an ordinary repo,
 *     including a Start-Fresh `git init` with no origin).
 *
 * Returns false when `.git` is absent, or is a directory missing `HEAD` or
 * `objects` (a bare `mkdir .git`, or a partial/interrupted clone). A read error
 * (EACCES/EIO) is treated as NOT-valid (the workspace is not usable as-is) — but
 * note that NOT-valid does NOT authorize removal; only `isEmptyCorruptGitDir`
 * does. Cost: 1-3 `lstat`/`existsSync` syscalls; no subprocess, no await.
 */
export function isValidGitWorkTree(workspacePath: string): boolean {
  const gitPath = join(workspacePath, ".git");
  let st;
  try {
    st = lstatSync(gitPath);
  } catch {
    return false; // ENOENT (absent) or unreadable → not a usable work tree
  }
  // A `.git` FILE is a gitdir pointer (linked worktree / submodule). Treat as
  // VALID and never removable — resolving the pointed-to dir is out of scope and
  // such trees are real (F2).
  if (st.isFile()) return true;
  if (!st.isDirectory()) return false;
  // Ordinary repo: require both HEAD and the object store. A bare `mkdir .git`
  // (the residual-fixture / failed-atomic-rename shape) has neither.
  return (
    existsSync(join(gitPath, "HEAD")) && existsSync(join(gitPath, "objects"))
  );
}

/**
 * Structural shape of `<workspacePath>/.git` (#5733). A SYNC, read-only
 * classification used by the dispatch readiness gate + the agent-readiness
 * observability mirror. The load-bearing case is `"file-pointer"`: a `.git`
 * FILE that `isValidGitWorkTree` passes (line 60) but the agent's IN-BWRAP `git
 * rev-parse --is-inside-work-tree` strands on — especially when the `gitdir:`
 * target resolves OUTSIDE the workspace (e.g. under `/workspaces`, which the
 * agent sandbox `denyRead`s). A personal workspace root is NEVER a legitimate
 * linked-worktree/submodule, so a `.git` FILE there is an anomalous stale
 * pointer. `gitdirEscapesWorkspace` enriches the signal (a target inside the
 * workspace would still be readable in-sandbox).
 *
 * Cost: 1 `lstat` + (for a FILE only) 1 small `readFileSync`. No subprocess.
 */
export interface GitWorktreeShape {
  kind: "absent" | "file-pointer" | "dir-valid" | "dir-invalid" | "other";
  /** The raw `gitdir:` target string, for a file-pointer (best-effort). */
  gitdirTarget?: string;
  /** True when the gitdir target resolves OUTSIDE `workspacePath`. */
  gitdirEscapesWorkspace?: boolean;
}

export function probeGitWorktreeShape(workspacePath: string): GitWorktreeShape {
  const gitPath = join(workspacePath, ".git");
  // Open ONCE and stat+read on the SAME file descriptor — no lstat-then-readFile
  // TOCTOU (CodeQL js/file-system-race). `O_NOFOLLOW` preserves the no-follow
  // semantics of `isValidGitWorkTree`'s lstat: a `.git` SYMLINK fails to open
  // (ELOOP) and is classified `"other"`, never followed.
  let fd: number;
  try {
    fd = openSync(gitPath, constants.O_RDONLY | constants.O_NOFOLLOW);
  } catch (err) {
    // ENOENT → genuinely absent; ELOOP (symlink) / EACCES / other → an
    // unusable plain `.git`, conservatively bucketed `"other"` (not ready,
    // never destructively healed).
    return (err as NodeJS.ErrnoException).code === "ENOENT"
      ? { kind: "absent" }
      : { kind: "other" };
  }
  try {
    const st = fstatSync(fd);
    if (st.isFile()) {
      let gitdirTarget: string | undefined;
      let gitdirEscapesWorkspace: boolean | undefined;
      try {
        const body = readFileSync(fd, "utf8"); // reads from the open fd — same file
        const m = body.match(/^gitdir:\s*(.+?)\s*$/m);
        gitdirTarget = m?.[1];
        if (gitdirTarget) {
          const resolved = isAbsolute(gitdirTarget)
            ? resolve(gitdirTarget)
            : resolve(workspacePath, gitdirTarget);
          const root = resolve(workspacePath);
          gitdirEscapesWorkspace =
            resolved !== root && !resolved.startsWith(root + sep);
        }
      } catch {
        // Unreadable pointer body — still a file-pointer (escapes unknown).
      }
      return { kind: "file-pointer", gitdirTarget, gitdirEscapesWorkspace };
    }
    if (st.isDirectory()) {
      return {
        kind: isValidGitWorkTree(workspacePath) ? "dir-valid" : "dir-invalid",
      };
    }
    return { kind: "other" }; // socket / fifo / etc. — never the file-pointer path
  } finally {
    closeSync(fd);
  }
}

/**
 * A `.git` FILE pointer that STRANDS the agent's in-bwrap `git rev-parse`
 * (#5733). The strand is specific: only a pointer whose `gitdir:` target
 * resolves OUTSIDE the workspace (e.g. under `/workspaces`, which the agent
 * sandbox `denyRead`s) is unreadable in-sandbox and fails `rev-parse`. A pointer
 * whose target stays INSIDE the workspace is readable in-sandbox and works — it
 * does NOT strand, so it is left untouched (never destructively re-cloned). An
 * unreadable pointer body (`gitdirEscapesWorkspace === undefined`) is treated as
 * stranding — a workspace-root `.git` FILE we cannot classify is anomalous and a
 * personal workspace root is never a legitimate linked worktree. This is the
 * predicate the destructive heal gates on, so it is deliberately narrow.
 */
export function isStrandingFilePointer(shape: GitWorktreeShape): boolean {
  return shape.kind === "file-pointer" && shape.gitdirEscapesWorkspace !== false;
}

/**
 * READINESS-grade validity (#5733). `isValidGitWorkTree` is the STRUCTURAL
 * fast-path gate, but it returns `true` for a `.git` FILE pointer — and an
 * ESCAPING pointer strands the agent's in-bwrap `git rev-parse`. The dispatch +
 * reconcile readiness gates use THIS: ready = a self-contained valid dir OR a
 * NON-escaping in-workspace pointer (readable in-sandbox). A stranding (escaping
 * / unclassifiable) pointer is NOT ready, so it routes into
 * `ensureWorkspaceRepoCloned` (which unlinks the stale pointer + re-clones a
 * self-contained `.git`) rather than fast-pathing a doomed agent spawn. This is
 * `rev-parse`-AWARE structural readiness — it closes the dominant rev-parse
 * strand case (the escaping pointer); it does not itself run `rev-parse`. Cost:
 * a single `probeGitWorktreeShape` (sync lstat(s); the small pointer-body read
 * happens only when `.git` is actually a FILE) — no subprocess, no double-probe.
 */
export function isReadyGitWorkTree(workspacePath: string): boolean {
  const shape = probeGitWorktreeShape(workspacePath);
  if (shape.kind === "dir-valid") return true;
  // A non-escaping in-workspace pointer is functional in-sandbox → ready.
  if (shape.kind === "file-pointer") return shape.gitdirEscapesWorkspace === false;
  return false; // absent / dir-invalid / other (symlink) → not ready
}

/**
 * SYNC POSITIVE empty-corrupt fingerprint — the ONLY authorization for the
 * destructive re-clone `rm` (deepen-plan F2).
 *
 * True ONLY when `.git` exists AND is a DIRECTORY AND `HEAD` is ENOENT AND
 * `objects` is ENOENT. Deliberately conservative:
 *   - A `.git` FILE (gitdir pointer) → false (never rm a linked-worktree).
 *   - A populated `.git` (HEAD or objects present) → false (may hold un-pushed
 *     commits; honest-block instead).
 *   - An EACCES/EIO on `.git` itself → false (a transient unreadable populated
 *     repo must NOT be destroyed). We distinguish ENOENT (genuinely absent) from
 *     other errno: only an explicit ENOENT on HEAD/objects counts as "empty".
 *
 * Never trigger removal on the NEGATION of `isValidGitWorkTree` — that collapses
 * ENOENT with EACCES and would destroy a populated repo on a blip.
 */
export function isEmptyCorruptGitDir(workspacePath: string): boolean {
  const gitPath = join(workspacePath, ".git");
  let st;
  try {
    st = lstatSync(gitPath);
  } catch {
    return false; // absent or unreadable → not the empty-corrupt fingerprint
  }
  if (!st.isDirectory()) return false; // a `.git` FILE is never the fingerprint

  // Positive ENOENT on BOTH HEAD and objects. `existsSync` is false for both
  // ENOENT and a permission error; to keep this a POSITIVE fingerprint we use
  // lstatSync and require an explicit ENOENT (not EACCES/EIO) on each marker.
  const markerIsEnoent = (name: string): boolean => {
    try {
      lstatSync(join(gitPath, name));
      return false; // marker exists → not empty
    } catch (err) {
      return (err as NodeJS.ErrnoException).code === "ENOENT";
    }
  };
  return markerIsEnoent("HEAD") && markerIsEnoent("objects");
}

// ---------------------------------------------------------------------------
// #5733 deliverable A — an AUTHORITATIVE host `git rev-parse` confirm for the ONE
// shape the sync lstat verdict (`isReadyGitWorkTree`) greenlights but the agent
// can still strand on: a `dir-valid` `.git` (HEAD+objects present) that `git`
// itself cannot resolve as a work tree (broken `config`/`commondir`/refs/gitdir
// indirection). The escaping-pointer + dir-invalid realizations are already
// healed on main by the lstat verdict, so this subprocess's net-new coverage is
// EXACTLY the corrupt-`dir-valid` slice (it is blind to the escaping pointer —
// host git is not sandboxed — and to object-store corruption, the documented
// out-of-scope residual; deliverable C2 surfaces those).
//
// Hardened like the `git-auth.ts` spawn precedent: `execFile` array form (no
// shell), `GIT_CONFIG_NOSYSTEM` / `GIT_CONFIG_GLOBAL=/dev/null` /
// `GIT_TERMINAL_PROMPT=0`, and a `GIT_CEILING_DIRECTORIES` set to the absolute,
// symlink-resolved PARENT so host git cannot ascend into a parent `.git` (e.g.
// `/workspaces/.git`) and false-pass. NO installation token / askpass — this is a
// local, read-only, network-free probe.
// ---------------------------------------------------------------------------

/**
 * Build the hardened, ceiling-pinned env for the host `rev-parse` probe.
 * Returns `null` when the workspace parent cannot be symlink-resolved (the
 * discovery ceiling cannot be bounded safely → the caller treats it as
 * inconclusive and FAILS-OPEN). Exported so the env hardening (no install token,
 * no askpass, ceiling = realpath parent) is unit-asserted directly (AC1/AC2).
 */
export function buildGitProbeEnv(
  workspacePath: string,
): { env: NodeJS.ProcessEnv } | null {
  let ceiling: string;
  try {
    // `realpathSync` resolves a symlinked `/workspaces` path component so the
    // ceiling matches the realpath git canonicalizes the cwd to (AC2).
    ceiling = realpathSync(resolve(workspacePath, ".."));
  } catch {
    return null;
  }
  const env: NodeJS.ProcessEnv = {
    ...process.env,
    GIT_CEILING_DIRECTORIES: ceiling,
    GIT_CONFIG_NOSYSTEM: "1",
    GIT_CONFIG_GLOBAL: "/dev/null",
    GIT_TERMINAL_PROMPT: "0",
  };
  // Defense-in-depth: a read-only local probe must NEVER carry a credential or an
  // askpass helper, even if the ambient process env happens to hold one.
  delete env.GIT_INSTALLATION_TOKEN;
  delete env.GIT_ASKPASS;
  delete env.GIT_USERNAME;
  return { env };
}

/** Probe outcome: `worktree` (git confirmed a work tree), `not-a-worktree` (git's
 *  deterministic exit-128 "not a git repository"), or `inconclusive` (spawn
 *  error / timeout / EACCES — the caller FAILS-OPEN, never honest-blocks). */
export type GitRevParseOutcome = "worktree" | "not-a-worktree" | "inconclusive";

/** Injected runner seam (CTO flag — the probe must be unit-testable without a
 *  live git). Resolves the rev-parse stdout, or rejects with the `execFile`
 *  error (carrying numeric `.code` for a non-zero exit, string errno for a spawn
 *  failure, `.killed` for a timeout). */
export type GitRevParseRunner = (input: {
  workspacePath: string;
  env: NodeJS.ProcessEnv;
}) => Promise<{ stdout: string }>;

const realGitRevParseRunner: GitRevParseRunner = async ({ workspacePath, env }) => {
  const { stdout } = await execFileAsync(
    "git",
    ["-C", workspacePath, "rev-parse", "--is-inside-work-tree"],
    {
      timeout: 2000, // ~2s — a local rev-parse is sub-ms; a hang is a strand, not a wait
      killSignal: "SIGKILL",
      maxBuffer: 1024 * 1024, // cap stdout (a healthy probe prints just "true")
      env,
    },
  );
  return { stdout: stdout.toString() };
};

export async function hostGitRevParseOutcome(
  workspacePath: string,
  run: GitRevParseRunner = realGitRevParseRunner,
): Promise<GitRevParseOutcome> {
  const probeEnv = buildGitProbeEnv(workspacePath);
  if (probeEnv === null) return "inconclusive"; // parent unresolvable → fail-open
  try {
    const { stdout } = await run({ workspacePath, env: probeEnv.env });
    // A work tree prints exactly "true"; anything else is treated conservatively
    // as inconclusive (NOT a confirmed strand — never honest-block on ambiguity).
    return stdout.trim() === "true" ? "worktree" : "inconclusive";
  } catch (err) {
    const e = err as NodeJS.ErrnoException & {
      code?: number | string;
      killed?: boolean;
      signal?: NodeJS.Signals | null;
    };
    // Timeout / killed → transient → inconclusive (FAIL-OPEN upstream).
    if (e.killed || e.signal) return "inconclusive";
    // Spawn failure (string errno: ENOENT git missing / EACCES) → inconclusive.
    if (typeof e.code === "string") return "inconclusive";
    // git's clean "not a git repository" is exit 128 — the deterministic strand.
    if (e.code === 128) return "not-a-worktree";
    // Any other non-zero exit → ambiguous → inconclusive (do not honest-block).
    return "inconclusive";
  }
}

/** Caller-held context for the shared readiness gate. `connected` = a repoUrl is
 *  present; `dbReady` = the DB `repo_status` readiness check passed. */
export interface AgentReadinessContext {
  userId: string;
  activeWorkspaceId: string;
  connected: boolean;
  dbReady: boolean;
}

/**
 * #5733 — the ONE shared readiness gate across the cold (cc-dispatcher), warm
 * (cc-reprovision), and reconcile (workspace-reconcile-on-push) dispatch paths.
 * Sharing the emit + heal-route + re-probe + fail-open decision STRUCTURALLY (not
 * re-specified per gate) is the direct fix for the cold-only-emit / warm+reconcile
 * dark drift that left the 26×-fired strand unqueryable.
 *
 * Runs ONLY for the `dir-valid` shape inside the lstat-ready + connected +
 * DB-ready population — every other shape (absent / dir-invalid / escaping or
 * in-workspace pointer / not-connected / not-DB-ready) keeps the cheap sync
 * routing the on-main lstat verdict already owns. For a `dir-valid`:
 *   - `worktree`        → ready (fast path, common case)
 *   - `not-a-worktree`  → emit the self-stop (gitRevParseValid=false) + `block`
 *                         (the caller surfaces RepoNotReadyError; NEVER destroy a
 *                         populated `.git` — `ensureWorkspaceRepoCloned` no-ops on
 *                         it by design, so honest-block is the only safe outcome)
 *   - `inconclusive`×2  → FAIL-OPEN to `ready` + a low-signal breadcrumb (a probe
 *                         blip must never honest-block a healthy repo — that
 *                         manufactures the exact #5733 strand)
 *
 * The `probe` seam defaults to the real host confirm; tests inject deterministic
 * outcomes. NO memoization (a stale positive masks sub-lstat corruption).
 */
export async function evaluateAgentReadiness(
  workspacePath: string,
  ctx: AgentReadinessContext,
  probe: (p: string) => Promise<GitRevParseOutcome> = hostGitRevParseOutcome,
): Promise<"ready" | "block"> {
  if (!ctx.connected || !ctx.dbReady) return "ready";
  // dir-valid ONLY: the one slice lstat cannot adjudicate. The lstat verdict has
  // already routed escaping pointers + dir-invalid to the heal before this gate.
  if (probeGitWorktreeShape(workspacePath).kind !== "dir-valid") return "ready";

  let outcome = await probe(workspacePath);
  if (outcome === "inconclusive") outcome = await probe(workspacePath); // re-probe once

  if (outcome === "worktree") return "ready";
  if (outcome === "inconclusive") {
    // FAIL-OPEN — spawn rather than honest-block a (probably healthy) repo.
    reportAgentReadinessProbeInconclusive({
      userId: ctx.userId,
      activeWorkspaceId: ctx.activeWorkspaceId,
    });
    return "ready";
  }
  // not-a-worktree — a dir-valid `.git` git itself cannot resolve: the strand.
  reportAgentReadinessSelfStop({
    userId: ctx.userId,
    activeWorkspaceId: ctx.activeWorkspaceId,
    gitValid: true, // dir-valid passes lstat — this IS the proxy-vs-invariant divergence
    gitRevParseValid: false,
    gitKind: "dir-valid",
    source: "host-pre-heal",
  });
  return "block";
}
