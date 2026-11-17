// ---------------------------------------------------------------------------
// KB sync held files (#12714, rulings W1, W2, W4, D29(1), D38(5), D39(b)-(e)).
//
// How many code (non-KB) files the KB-only sync holds back from the repository's main branch. Display-only: the value
// goes to `workspaces.kb_sync_held_files` (migration 187) for the Settings notice and the agent line, and no gate,
// approval or push decision reads it.
//
// What is counted:
//   - HEAD (W1): the non-KB FILES of `diff --name-only --no-renames -z <T>...<head>` (three-dot: from the merge base, so
//     upstream changes not yet pulled are not counted). Files, not commits: a commit count stays stale after a squash
//     merge and drops to 0 under pathspec history simplification while the work is still unmerged (probe6 C1-C3).
//   - every set-aside tip (W4, D39(c)/(d)): the recovered kb-sync branches (`refs/heads/soleur/recovered-kb-sync-*`, the
//     legacy self-heal's) and the rescued store tips (`refs/heads/soleur-store-tip-<12 hex>`, the git-data overlay's).
//     A tip's files are the INTERSECTION of the three-dot `<T>...<tip>` and the two-dot `<T> <tip>` diffs: changed since
//     the merge base AND still different from `T`, so work GitHub squash- or rebase-merged clears (arch F3).
//   - the union, deduplicated, clamped to 0..HELD_FILES_MAX. A stored HELD_FILES_MAX means "HELD_FILES_MAX or more"
//     (D39(e)); the copy renders it as a lower bound, and no column records the clamp.
// `T` is the authoritative tip the hardened `ls-remote` returned in that run, never `refs/remotes/origin/*`. Every
// revision is a HEX40 value, never a symbolic name (`HEAD` inside the isolated dir would be the isolated dir's own HEAD).
//
// Where it runs (W2): token-free, through `runIsolatedGitLocal`, in an isolated dir the caller already holds; the tips'
// objects are reachable through the workspace alternate. One budget (HELD_COUNT_BUDGET_MS) covers every child, each
// child's timeout is the remaining budget, and the tip diffs run at most HELD_DIFF_CONCURRENCY at a time (D38(5)).
// Every failure is `null` (unknown: nothing is shown), never 0 or a partial count, and the `kb-sync.held-files` line
// names its closed cause (`nullCause`, D39(b), obs F6).
//
// `readRecoveredKbSyncTips` reads the set-aside refs as data (no git): lstat on every directory in the chain (a symlink
// anywhere gives null), loose files of at most 64 bytes each (O_NOFOLLOW, regular files only), plus the matching
// `packed-refs` lines from a file of at most 1 MiB. At most RECOVERED_TIPS_MAX refs across both families are read: past
// that, the first in sorted ref order, and one `tips_truncated` warning. A forged ref or object can only skew the
// number that workspace's own users see.
// ---------------------------------------------------------------------------

import { lstatSync, readdirSync, realpathSync } from "node:fs";
import { join } from "node:path";

import { HEX40, readSmallRegularFile, SmallFileError } from "./approval/workspace-head";
import { runIsolatedGitLocal } from "./git-isolated-local";
import type { IsolatedPushDir } from "./git-hardened-env";
import { KB_ROOT } from "./kb-root";
import { createChildLogger } from "./logger";

const log = createChildLogger("kb-sync-held");

/** Upper bound of the stored count (migration 187's named range check); a stored value of exactly this means "or more". */
export const HELD_FILES_MAX = 10_000;
/** At most this many set-aside tips are read, across the recovered and the store-tip families together (W4, D39(d)). */
export const RECOVERED_TIPS_MAX = 20;
/** The total budget of one count, every child included (D38(5)). */
export const HELD_COUNT_BUDGET_MS = 5_000;
/** At most this many set-aside tips are diffed at once (D38(5)). */
export const HELD_DIFF_CONCURRENCY = 4;
/** The branch prefix the legacy self-heal set work aside on (`server/workspace-sync.ts`, the recovery-branch block). */
export const RECOVERED_REF_PREFIX = "refs/heads/soleur/recovered-kb-sync-";
/** The branch prefix the git-data overlay parks a rescued store tip on (`soleur-store-tip-<12 hex>`, ensure-workspace-repo). */
export const STORE_TIP_REF_PREFIX = "refs/heads/soleur-store-tip-";

/** Why a count is null (D39(b)): the closed `nullCause` of the `kb-sync.held-files` line. */
export type HeldNullCause = "recovered_unreadable" | "no_merge_base" | "git_failed" | "invalid_rev" | "budget";

const RECOVERED_LEAF = /^recovered-kb-sync-[0-9A-Za-z_-]{1,64}$/;
const STORE_TIP_LEAF = /^soleur-store-tip-[0-9a-f]{12}$/;
const RECOVERED_REF = /^refs\/heads\/soleur\/recovered-kb-sync-[0-9A-Za-z_-]{1,64}$/;
const STORE_TIP_REF = /^refs\/heads\/soleur-store-tip-[0-9a-f]{12}$/;
const LOOSE_REF_MAX_BYTES = 64;
const PACKED_REFS_MAX_BYTES = 1024 * 1024;
const EXCLUDE_KB = `:(exclude)${KB_ROOT}/`;

export interface HeldFiles {
  /** Distinct non-KB files on HEAD and every set-aside tip, clamped to 0..HELD_FILES_MAX. The stored value. */
  readonly total: number;
  /** Distinct non-KB files on the set-aside tips alone (the agent line's recovered clause when > 0), clamped. */
  readonly onRecovered: number;
}

export interface ComputeHeldFilesInput {
  readonly isolated: IsolatedPushDir;
  /** `T`: the remote default-branch tip the hardened `ls-remote` returned in this run. */
  readonly base: string;
  /** The workspace HEAD sha (never the symbolic name). */
  readonly head: string;
  /** `readRecoveredKbSyncTips(workspacePath)`; the caller handles its `null` (`recovered_unreadable`) itself. */
  readonly recovered: readonly string[];
  /** Log context only; never part of the computation. */
  readonly workspaceId?: string;
}

/** The value bucket of the `kb-sync.held-files` log line (no paths, no exact count). */
export function heldFilesBucket(total: number | null): "null" | "0" | "1-9" | "10+" {
  if (total === null) return "null";
  if (total === 0) return "0";
  return total < 10 ? "1-9" : "10+";
}

/**
 * The one `kb-sync.held-files` line per count attempt (obs F6): the bucket, and for a null the closed `nullCause`. Info
 * level; the persistent `recovered_unreadable` is ALSO a debounced warning (server/kb-sync-held-refresh.ts).
 */
export function logHeldFiles(result: HeldFiles | null, nullCause: HeldNullCause | null, workspaceId?: string): void {
  log.info(
    {
      op: "kb-sync.held-files",
      bucket: heldFilesBucket(result?.total ?? null),
      onRecoveredBucket: heldFilesBucket(result?.onRecovered ?? null),
      ...(result === null && nullCause !== null ? { nullCause } : {}),
      ...(workspaceId ? { workspaceId } : {}),
    },
    "kb sync held files computed",
  );
}

class HeldCountFailure extends Error {
  constructor(readonly nullCause: Exclude<HeldNullCause, "recovered_unreadable">) {
    super(`held count failed (${nullCause})`);
  }
}

/** One non-KB name-only diff over `range` (`<a>...<b>` or `<a> <b>`), bounded by the remaining budget. Throws a cause. */
async function nonKbFiles(isolated: IsolatedPushDir, range: readonly string[], deadline: number): Promise<Set<string>> {
  const remaining = deadline - Date.now();
  if (remaining <= 0) throw new HeldCountFailure("budget");
  const r = await runIsolatedGitLocal(
    isolated,
    ["diff", "--name-only", "--no-renames", "--no-ext-diff", "--no-textconv", "-z", ...range, "--", ".", EXCLUDE_KB],
    { timeoutMs: remaining },
  );
  if (r.timedOut) throw new HeldCountFailure("budget");
  if (r.code !== 0) {
    if (/no merge base/i.test(r.stderr)) throw new HeldCountFailure("no_merge_base");
    if (/bad revision|unknown revision|bad object|invalid symmetric difference|not a valid object/i.test(r.stderr)) {
      throw new HeldCountFailure("invalid_rev");
    }
    throw new HeldCountFailure("git_failed");
  }
  const names = new Set<string>();
  for (const n of r.stdout.toString("utf8").split("\0")) if (n !== "") names.add(n);
  return names;
}

/** A set-aside tip's files (D39(c)): changed since its merge base with `T` AND still different from `T`. */
async function setAsideFiles(isolated: IsolatedPushDir, base: string, tip: string, deadline: number): Promise<Set<string>> {
  const [sinceBase, vsBase] = await Promise.all([
    nonKbFiles(isolated, [`${base}...${tip}`], deadline),
    nonKbFiles(isolated, [base, tip], deadline),
  ]);
  return new Set([...sinceBase].filter((n) => vsBase.has(n)));
}

/** Runs `fn` over `items` with at most `limit` in flight; rejects with the first failure (the others still settle). */
async function mapLimited<T, R>(items: readonly T[], limit: number, fn: (t: T) => Promise<R>): Promise<R[]> {
  const out: R[] = new Array(items.length);
  let next = 0;
  let failed: unknown = null;
  const worker = async (): Promise<void> => {
    while (failed === null && next < items.length) {
      const i = next++;
      try {
        out[i] = await fn(items[i]);
      } catch (err) {
        if (failed === null) failed = err;
      }
    }
  };
  await Promise.all(Array.from({ length: Math.min(limit, items.length) }, worker));
  if (failed !== null) throw failed;
  return out;
}

/**
 * The held-files count over `<base>...<head>` and every set-aside tip (W1, W4, D39(c)). `null` on a non-HEX40
 * revision, no merge base, an absent object, any git failure or an expired budget; the `kb-sync.held-files` line names
 * which. `opts.cap` is a test seam for the clamp, `opts.budgetMs` for the budget; production passes nothing.
 */
export async function computeHeldFiles(
  input: ComputeHeldFilesInput,
  opts: { readonly cap?: number; readonly budgetMs?: number } = {},
): Promise<HeldFiles | null> {
  let result: HeldFiles | null = null;
  let nullCause: HeldNullCause | null = null;
  try {
    result = await compute(input, opts.cap ?? HELD_FILES_MAX, Date.now() + (opts.budgetMs ?? HELD_COUNT_BUDGET_MS));
  } catch (err) {
    nullCause = err instanceof HeldCountFailure ? err.nullCause : "git_failed";
  }
  logHeldFiles(result, nullCause, input.workspaceId);
  return result;
}

async function compute(input: ComputeHeldFilesInput, cap: number, deadline: number): Promise<HeldFiles> {
  const { isolated, base, head, recovered } = input;
  if (!HEX40.test(base) || !HEX40.test(head) || !recovered.every((t) => HEX40.test(t))) {
    throw new HeldCountFailure("invalid_rev");
  }
  const onHead = await nonKbFiles(isolated, [`${base}...${head}`], deadline);
  const perTip = await mapLimited([...new Set(recovered)], HELD_DIFF_CONCURRENCY, (tip) =>
    setAsideFiles(isolated, base, tip, deadline),
  );
  const onRecovered = new Set<string>(perTip.flatMap((names) => [...names]));
  const all = new Set<string>([...onHead, ...onRecovered]);
  return { total: Math.min(all.size, cap), onRecovered: Math.min(onRecovered.size, cap) };
}

type DirState = "dir" | "absent" | "refuse";

function dirState(path: string): DirState {
  try {
    const st = lstatSync(path);
    if (st.isSymbolicLink() || !st.isDirectory()) return "refuse";
    return "dir";
  } catch (err) {
    const code = (err as NodeJS.ErrnoException)?.code;
    return code === "ENOENT" || code === "ENOTDIR" ? "absent" : "refuse";
  }
}

function stripOneNewline(body: string): string {
  return body.endsWith("\n") ? body.slice(0, -1) : body;
}

/** The loose leaf names of `dir` that match `leaf`; `[]` when the dir is absent, `null` when it cannot be read safely. */
function looseLeaves(dir: string, leaf: RegExp): string[] | null {
  const st = dirState(dir);
  if (st === "absent") return [];
  if (st === "refuse") return null;
  try {
    return readdirSync(dir).filter((n) => leaf.test(n));
  } catch {
    return null;
  }
}

/**
 * The set-aside tips of the workspace (W4, D39(d)): the recovered kb-sync branches and the rescued store tips, the first
 * RECOVERED_TIPS_MAX full refnames in sorted ref order (one `tips_truncated` warning past that), deduplicated by sha.
 * `[]` when there are none; `null` when the refs cannot be read safely (a symlink in the chain, an oversized,
 * non-regular or non-HEX40 ref, an oversized or unreadable `packed-refs`, a reftable repository). Spawns nothing.
 */
export function readRecoveredKbSyncTips(workspacePath: string, opts: { readonly workspaceId?: string } = {}): string[] | null {
  let ws: string;
  try {
    ws = realpathSync(workspacePath);
  } catch {
    return null;
  }
  const gitDir = join(ws, ".git");
  if (dirState(gitDir) !== "dir") return null;
  if (dirState(join(gitDir, "reftable")) !== "absent") return null;

  // Loose refs (full refname -> file path; no file is read yet). refs/ and refs/heads/ must be real directories.
  const loose = new Map<string, string>();
  const refsState = dirState(join(gitDir, "refs"));
  if (refsState === "refuse") return null;
  if (refsState === "dir") {
    const headsDir = join(gitDir, "refs", "heads");
    const storeLeaves = looseLeaves(headsDir, STORE_TIP_LEAF);
    if (storeLeaves === null) return null;
    for (const n of storeLeaves) loose.set(`refs/heads/${n}`, join(headsDir, n));
    if (dirState(headsDir) === "dir") {
      const recoveredDir = join(headsDir, "soleur");
      const recoveredLeaves = looseLeaves(recoveredDir, RECOVERED_LEAF);
      if (recoveredLeaves === null) return null;
      for (const n of recoveredLeaves) loose.set(`refs/heads/soleur/${n}`, join(recoveredDir, n));
    }
  }

  // packed-refs lines matching either family.
  const packed = new Map<string, string>();
  const packedPath = join(gitDir, "packed-refs");
  let packedBody: string | null = null;
  try {
    const st = lstatSync(packedPath);
    if (st.isSymbolicLink()) return null;
    packedBody = readSmallRegularFile(packedPath, PACKED_REFS_MAX_BYTES);
  } catch (err) {
    const code = err instanceof SmallFileError ? err.code : (err as NodeJS.ErrnoException)?.code;
    if (code !== "ENOENT" && code !== "ENOTDIR") return null;
  }
  if (packedBody !== null) {
    for (const line of packedBody.split("\n")) {
      if (line === "" || line.startsWith("#") || line.startsWith("^")) continue;
      const sp = line.indexOf(" ");
      if (sp < 0) continue;
      const name = line.slice(sp + 1);
      if (!RECOVERED_REF.test(name) && !STORE_TIP_REF.test(name)) continue;
      const sha = line.slice(0, sp);
      if (!HEX40.test(sha)) return null;
      packed.set(name, sha);
    }
  }

  // Byte order of the full refname, as `git for-each-ref` sorts (so `soleur-store-tip-*` precedes `soleur/`).
  const all = [...new Set([...loose.keys(), ...packed.keys()])].sort((a, b) => (a < b ? -1 : a > b ? 1 : 0));
  if (all.length > RECOVERED_TIPS_MAX) {
    log.warn(
      {
        op: "kb-sync.held-files",
        reason: "tips_truncated",
        refs: all.length,
        counted: RECOVERED_TIPS_MAX,
        ...(opts.workspaceId ? { workspaceId: opts.workspaceId } : {}),
      },
      "More set-aside tips than the count reads; the first in sorted ref order are counted",
    );
  }
  const tips: string[] = [];
  for (const name of all.slice(0, RECOVERED_TIPS_MAX)) {
    let sha: string | undefined;
    const file = loose.get(name);
    if (file !== undefined) {
      // A loose file wins over its packed line (git's own precedence).
      try {
        sha = stripOneNewline(readSmallRegularFile(file, LOOSE_REF_MAX_BYTES));
      } catch {
        return null;
      }
      if (!HEX40.test(sha)) return null;
    } else {
      sha = packed.get(name);
    }
    if (sha !== undefined && !tips.includes(sha)) tips.push(sha);
  }
  return tips;
}
