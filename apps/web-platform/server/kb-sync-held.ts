// ---------------------------------------------------------------------------
// KB sync held files (#12714, rulings W1, W2, W4, D29(1)).
//
// How many code (non-KB) files the KB-only sync holds back from the repository's main branch. Display-only: the value
// goes to `workspaces.kb_sync_held_files` (migration 187) for the Settings notice and the agent line, and no gate,
// approval or push decision reads it.
//
// What is counted (W1): the non-KB FILES of `diff --name-only --no-renames -z <T>...<head>` (three-dot: from the merge
// base, so upstream changes not yet pulled are not counted), unioned with the same diff for every recovered kb-sync
// branch tip (W4: work set aside by the legacy self-heal still exists only on a local branch), deduplicated, clamped to
// 0..HELD_FILES_MAX. Files, not commits: a commit count stays stale after a squash merge and drops to 0 under pathspec
// history simplification while the work is still unmerged (probe6 C1-C3). `T` is the authoritative tip the hardened
// `ls-remote` returned in that sync run, never `refs/remotes/origin/*`. Every revision is a HEX40 value, never a symbolic
// name (`HEAD` inside the isolated dir would be the isolated dir's own HEAD).
//
// Where it runs (W2): token-free, through `runIsolatedGitLocal`, in an isolated dir the sync already holds; the
// recovered tips' objects are reachable through the workspace alternate. No merge base, an unreadable ref or any git
// failure gives `null` (unknown: nothing is shown), never 0.
//
// `readRecoveredKbSyncTips` reads the workspace's recovered refs as data (no git): lstat on every directory in the
// chain (a symlink anywhere gives null), at most RECOVERED_TIPS_MAX loose files of at most 64 bytes each (O_NOFOLLOW,
// regular files only), plus the matching `packed-refs` lines from a file of at most 1 MiB. A forged ref or object can
// only skew the number that workspace's own users see.
// ---------------------------------------------------------------------------

import { lstatSync, readdirSync, realpathSync } from "node:fs";
import { join } from "node:path";

import { HEX40, readSmallRegularFile, SmallFileError } from "./approval/workspace-head";
import { runIsolatedGitLocal } from "./git-isolated-local";
import type { IsolatedPushDir } from "./git-hardened-env";
import { KB_ROOT } from "./kb-root";
import { createChildLogger } from "./logger";

const log = createChildLogger("kb-sync-held");

/** Upper bound of the stored count (migration 187's named range check). */
export const HELD_FILES_MAX = 10_000;
/** At most this many recovered kb-sync tips are read (W4). */
export const RECOVERED_TIPS_MAX = 20;
/** The branch prefix the legacy self-heal set work aside on (`server/workspace-sync.ts`, the recovery-branch block). */
export const RECOVERED_REF_PREFIX = "refs/heads/soleur/recovered-kb-sync-";
/**
 * The branch prefix the git-data overlay parks a rescued store tip on (`soleur-store-tip-<12 hex>`). D39(d) adds these
 * tips to the count with WP3; Phase 0 exports the prefix only.
 */
export const STORE_TIP_REF_PREFIX = "refs/heads/soleur-store-tip-";

const RECOVERED_LEAF = /^recovered-kb-sync-[0-9A-Za-z_-]{1,64}$/;
const RECOVERED_REF = /^refs\/heads\/soleur\/recovered-kb-sync-[0-9A-Za-z_-]{1,64}$/;
const LOOSE_REF_MAX_BYTES = 64;
const PACKED_REFS_MAX_BYTES = 1024 * 1024;
const EXCLUDE_KB = `:(exclude)${KB_ROOT}/`;

export interface HeldFiles {
  /** Distinct non-KB files on HEAD and every recovered tip, clamped to 0..HELD_FILES_MAX. The stored value. */
  readonly total: number;
  /** Distinct non-KB files on the recovered tips alone (the agent line names the branches when > 0), clamped. */
  readonly onRecovered: number;
}

export interface ComputeHeldFilesInput {
  readonly isolated: IsolatedPushDir;
  /** `T`: the remote default-branch tip the hardened `ls-remote` returned in this sync run. */
  readonly base: string;
  /** The workspace HEAD sha (never the symbolic name). */
  readonly head: string;
  /** `readRecoveredKbSyncTips(workspacePath)`; the caller passes `null` through as "unknown" by not calling. */
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

async function nonKbFiles(isolated: IsolatedPushDir, base: string, tip: string): Promise<Set<string> | null> {
  const r = await runIsolatedGitLocal(isolated, [
    "diff",
    "--name-only",
    "--no-renames",
    "--no-ext-diff",
    "--no-textconv",
    "-z",
    `${base}...${tip}`,
    "--",
    ".",
    EXCLUDE_KB,
  ]);
  if (r.code !== 0) return null;
  const names = new Set<string>();
  for (const n of r.stdout.toString("utf8").split("\0")) if (n !== "") names.add(n);
  return names;
}

/**
 * The held-files count over `<base>...<head>` and every recovered tip (W1, W4). `null` on a non-HEX40 revision, no merge
 * base, an absent object or any git failure. `opts.cap` is a test seam for the clamp; production passes nothing.
 */
export async function computeHeldFiles(
  input: ComputeHeldFilesInput,
  opts: { readonly cap?: number } = {},
): Promise<HeldFiles | null> {
  const cap = opts.cap ?? HELD_FILES_MAX;
  const result = await compute(input, cap);
  log.info(
    {
      op: "kb-sync.held-files",
      bucket: heldFilesBucket(result?.total ?? null),
      onRecoveredBucket: heldFilesBucket(result?.onRecovered ?? null),
      ...(input.workspaceId ? { workspaceId: input.workspaceId } : {}),
    },
    "kb sync held files computed",
  );
  return result;
}

async function compute(input: ComputeHeldFilesInput, cap: number): Promise<HeldFiles | null> {
  const { isolated, base, head, recovered } = input;
  if (!HEX40.test(base) || !HEX40.test(head) || !recovered.every((t) => HEX40.test(t))) return null;
  if (recovered.length > RECOVERED_TIPS_MAX) return null;

  const onHead = await nonKbFiles(isolated, base, head);
  if (onHead === null) return null;
  const onRecovered = new Set<string>();
  for (const tip of new Set(recovered)) {
    const names = await nonKbFiles(isolated, base, tip);
    if (names === null) return null;
    for (const n of names) onRecovered.add(n);
  }
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

/**
 * The recovered kb-sync branch tips of the workspace, newest names first, deduplicated, at most RECOVERED_TIPS_MAX.
 * `[]` when there are none; `null` when the refs cannot be read safely (a symlink in the chain, an oversized, non-regular
 * or non-HEX40 ref, an oversized or unreadable `packed-refs`, a reftable repository). Spawns nothing.
 */
export function readRecoveredKbSyncTips(workspacePath: string): string[] | null {
  let ws: string;
  try {
    ws = realpathSync(workspacePath);
  } catch {
    return null;
  }
  const gitDir = join(ws, ".git");
  if (dirState(gitDir) !== "dir") return null;
  if (dirState(join(gitDir, "reftable")) !== "absent") return null;

  // Loose names (no file is read yet).
  const looseDir = join(gitDir, "refs", "heads", "soleur");
  let looseNames: string[] = [];
  const chain = [join(gitDir, "refs"), join(gitDir, "refs", "heads"), looseDir];
  let chainPresent = true;
  for (const p of chain) {
    const s = dirState(p);
    if (s === "refuse") return null;
    if (s === "absent") {
      chainPresent = false;
      break;
    }
  }
  if (chainPresent) {
    try {
      looseNames = readdirSync(looseDir).filter((n) => RECOVERED_LEAF.test(n));
    } catch {
      return null;
    }
  }

  // packed-refs lines matching the recovered-ref regex.
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
      if (!RECOVERED_REF.test(name)) continue;
      const sha = line.slice(0, sp);
      if (!HEX40.test(sha)) return null;
      packed.set(name.slice("refs/heads/soleur/".length), sha);
    }
  }

  const loose = new Set(looseNames);
  const names = [...new Set([...looseNames, ...packed.keys()])].sort().reverse().slice(0, RECOVERED_TIPS_MAX);
  const tips: string[] = [];
  for (const name of names) {
    let sha: string | undefined;
    if (loose.has(name)) {
      try {
        sha = stripOneNewline(readSmallRegularFile(join(looseDir, name), LOOSE_REF_MAX_BYTES));
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
