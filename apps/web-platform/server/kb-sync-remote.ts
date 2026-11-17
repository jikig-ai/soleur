// ---------------------------------------------------------------------------
// KB sync remote: the token-bearing reads of the KB sync, both on the hardened arm (#12718, rulings D25(1), X1).
//
// `readRemoteState` (one `ls-remote --symref`) and `fetchIntoIsolated` (one non-force fetch of a single named branch into
// the server-owned isolated directory) are the only calls here that carry the installation token. Both run from the
// isolated directory against the literal `https://github.com/<owner>/<repo>.git` URL, never `remote.origin.url`, so no
// workspace config, ref or hook takes part. A leaf: it imports neither kb-sync-publish.ts nor push-branch.ts. Errors are
// a neutral `KbRemoteError` with a closed reason; a fetch refusal is a result, never a throw.
// ---------------------------------------------------------------------------

import { readFileSync } from "node:fs";
import { join } from "node:path";
import { HEX40 } from "./approval/workspace-head";
import { validateBranchFormat } from "./branch-validation";
import { gitWithInstallationAuth } from "./git-auth";
import { parseConnectedRepo } from "./github-repo-parse";
import { ISOLATED_LOCAL_TIMEOUT_MS, runIsolatedGitLocal, verifyObject } from "./git-isolated-local";
import type { IsolatedPushDirHandle } from "./git-isolated-push-dir";

/** The durable side branch of the protected-branch fallback (#5426), in the user's own repo. */
export const KB_SYNC_SIDE_BRANCH = "soleur/kb-sync";
export const SIDE_REF = `refs/heads/${KB_SYNC_SIDE_BRANCH}`;

const LS_REMOTE_TIMEOUT_MS = 30_000;
/** Upper bound of one isolated fetch: a stalled transfer costs at most this long (X1). */
const FETCH_TIMEOUT_MS = 120_000;

/**
 * A child's timeout under a caller's remaining budget (D38(2)): `min(own cap, remaining)`, never below 1 ms (a 0 timeout
 * would mean "no timeout" to `execFile`). No budget: the own cap.
 */
export function cappedTimeout(ownMs: number, budgetMs: number | undefined): number {
  return budgetMs === undefined ? ownMs : Math.max(1, Math.min(ownMs, Math.floor(budgetMs)));
}

/** A failed remote read, with a closed reason and a static message: never git's error, whose argv names the URL. */
export type KbRemoteErrorReason = "ls_remote_failed" | "remote_state_invalid";

export class KbRemoteError extends Error {
  constructor(readonly reason: KbRemoteErrorReason) {
    super(`KB sync remote read failed (${reason})`);
    this.name = "KbRemoteError";
  }
}

export interface RemoteState {
  readonly defaultBranch: string;
  readonly tip: string;
  readonly sideTip: string | null;
  /** When this run's `ls-remote` returned `tip` (D39(f): the held count's `checkedAt`, not the instant of the write). */
  readonly readAt: Date;
}

/** What the `ls-remote` output alone says: the remote state without the instant it was read. */
export type ParsedRemoteState = Omit<RemoteState, "readAt">;

/** A default-branch name the sync may put in an argv: git's ref-format rules and no leading `-` (D26(5)). */
function isSafeBranchName(branch: string): boolean {
  if (branch.startsWith("-")) return false;
  try {
    validateBranchFormat(branch);
    return true;
  } catch {
    return false;
  }
}

/**
 * Parse `ls-remote --symref <url> HEAD refs/heads/soleur/kb-sync` (R2, R17): exactly one `ref: refs/heads/<D>\tHEAD`
 * line, one `<sha>\tHEAD` line, at most one exact `refs/heads/soleur/kb-sync` line. Other refs the tail-matching
 * patterns may return (`refs/x/HEAD`) are ignored; a duplicate or malformed line of the three throws. `null` = the remote
 * has no resolvable HEAD (`remote_branch_absent`).
 */
export function parseRemoteState(out: string): ParsedRemoteState | null {
  let defaultBranch: string | null = null;
  let tip: string | null = null;
  let sideTip: string | null = null;
  let seenSide = false;
  for (const line of out.split("\n")) {
    if (line === "") continue;
    const tab = line.indexOf("\t");
    if (tab < 0) throw new KbRemoteError("remote_state_invalid");
    const left = line.slice(0, tab);
    const name = line.slice(tab + 1);
    if (left.startsWith("ref: ")) {
      if (name !== "HEAD") continue;
      if (defaultBranch !== null) throw new KbRemoteError("remote_state_invalid");
      const target = left.slice("ref: ".length);
      if (!target.startsWith("refs/heads/")) throw new KbRemoteError("remote_state_invalid");
      const branch = target.slice("refs/heads/".length);
      if (!isSafeBranchName(branch)) throw new KbRemoteError("remote_state_invalid");
      defaultBranch = branch;
      continue;
    }
    if (!HEX40.test(left)) throw new KbRemoteError("remote_state_invalid");
    if (name === "HEAD") {
      if (tip !== null) throw new KbRemoteError("remote_state_invalid");
      tip = left;
    } else if (name === SIDE_REF) {
      if (seenSide) throw new KbRemoteError("remote_state_invalid");
      seenSide = true;
      sideTip = left;
    }
  }
  if (defaultBranch === null || tip === null) return null;
  return { defaultBranch, tip, sideTip };
}

/** One hardened `ls-remote --symref` against the literal URL; no agent-chosen name in argv. */
export async function readRemoteState(
  isolated: IsolatedPushDirHandle,
  installationId: number,
  url: string,
  opts: { readonly timeoutMs?: number } = {},
): Promise<RemoteState | null> {
  let out: Buffer;
  try {
    out = await gitWithInstallationAuth(["ls-remote", "--symref", url, "HEAD", SIDE_REF], installationId, {
      hardened: isolated,
      timeout: cappedTimeout(LS_REMOTE_TIMEOUT_MS, opts.timeoutMs),
    });
  } catch {
    throw new KbRemoteError("ls_remote_failed");
  }
  const readAt = new Date();
  const parsed = parseRemoteState(out.toString("utf8"));
  return parsed === null ? null : { ...parsed, readAt };
}

/**
 * `{owner, repo}` from a connected-repo URL through the ONE shared parser (`parseConnectedRepo`, server/github-repo-parse.ts,
 * pattern P3-12), so the KB sync and the c4 gate never disagree on the same workspace. Empty strings when the URL is null
 * or malformed.
 */
export function parseOwnerRepo(repoUrl: string | null): { owner: string; repo: string } {
  return parseConnectedRepo(repoUrl) ?? { owner: "", repo: "" };
}

/** The literal `https://github.com/<owner>/<repo>.git` URL (R2) from the workspace row: never `remote.origin.url`. */
export async function resolveRepoUrl(userId: string, workspaceId: string): Promise<{ url: string; owner: string; repo: string }> {
  const { getCurrentRepoUrl } = await import("./current-repo-url");
  const { owner, repo } = parseOwnerRepo(await getCurrentRepoUrl(userId, workspaceId));
  if (!owner || !repo) throw new KbRemoteError("remote_state_invalid");
  return { url: `https://github.com/${owner}/${repo}.git`, owner, repo };
}

/** Why an isolated fetch did not yield the expected, verified tip (the `fetch-stage` reasons of the pull, X1). */
type KbFetchRefusal = "fetch_failed" | "tip_mismatch" | "shallow_changed";

interface FetchSpec {
  /** The remote branch, already checked by `parseRemoteState` (`D`, or `soleur/kb-sync`). */
  readonly branch: string;
  /** The isolated destination branch: `fetched` (the default branch) or `fetched-side` (the side tip). */
  readonly dest: "fetched" | "fetched-side";
  /** The tip `ls-remote` named: the fetched ref must equal it and hash-verify. */
  readonly expected: string;
  /** Commits the workspace has, offered as haves through server-written isolated refs (never a workspace ref). */
  readonly haves: readonly string[];
}

const readShallow = (isolated: IsolatedPushDirHandle): string | null => {
  try {
    return readFileSync(join(isolated.gitDir, "shallow"), "utf8");
  } catch {
    return null;
  }
};

/**
 * Fetch ONE branch into the isolated directory (X1): `fetch --no-tags --no-recurse-submodules --no-write-fetch-head <url>
 * refs/heads/<branch>:refs/heads/<dest>`, no `+`, no glob, no `--depth`, an explicit timeout, the hardened arm. The haves
 * are written as isolated refs first (the alternate's refs are never advertised: `core.alternateRefsCommand=true`). Then
 * the tip is read with `rev-parse --verify refs/heads/<dest>^{commit}`, must equal `expected`, and must hash-verify.
 *   - the fetch fails, or a local step could not run: `fetch_failed`;
 *   - the isolated `shallow` file changed, or the fetch exited 0 without writing the ref (measured, probe8: git refuses a
 *     ref whose history would move the shallow roots, prints a warning, and exits 0): `shallow_changed`;
 *   - the tip differs from `expected`, or its bytes do not hash to its id: `tip_mismatch`.
 */
export async function fetchIntoIsolated(
  isolated: IsolatedPushDirHandle,
  installationId: number,
  url: string,
  spec: FetchSpec,
  opts: { readonly timeoutMs?: number } = {},
): Promise<{ readonly ok: true } | { readonly ok: false; readonly reason: KbFetchRefusal }> {
  if (!HEX40.test(spec.expected) || !isSafeBranchName(spec.branch)) return { ok: false, reason: "fetch_failed" };
  let i = 0;
  const local = (): { timeoutMs: number } => ({ timeoutMs: cappedTimeout(ISOLATED_LOCAL_TIMEOUT_MS, opts.timeoutMs) });
  for (const have of new Set(spec.haves)) {
    if (!HEX40.test(have)) return { ok: false, reason: "fetch_failed" };
    const r = await runIsolatedGitLocal(isolated, ["update-ref", "--no-deref", `refs/heads/have-${spec.dest}-${i++}`, have], local());
    if (r.code !== 0) return { ok: false, reason: "fetch_failed" };
  }
  const shallowBefore = readShallow(isolated);
  try {
    await gitWithInstallationAuth(
      ["fetch", "--no-tags", "--no-recurse-submodules", "--no-write-fetch-head", url, `refs/heads/${spec.branch}:refs/heads/${spec.dest}`],
      installationId,
      { hardened: isolated, timeout: cappedTimeout(FETCH_TIMEOUT_MS, opts.timeoutMs) },
    );
  } catch (err) {
    const stderr = String((err as { stderr?: unknown } | null)?.stderr ?? "");
    return { ok: false, reason: /shallow roots are not allowed to be updated/.test(stderr) ? "shallow_changed" : "fetch_failed" };
  }
  if (readShallow(isolated) !== shallowBefore) return { ok: false, reason: "shallow_changed" };
  const tip = await runIsolatedGitLocal(isolated, ["rev-parse", "--verify", "--quiet", `refs/heads/${spec.dest}^{commit}`], local());
  if (tip.code === -1) return { ok: false, reason: "fetch_failed" };
  if (tip.code !== 0) return { ok: false, reason: "shallow_changed" };
  if (tip.stdout.toString("utf8").trim() !== spec.expected) return { ok: false, reason: "tip_mismatch" };
  const v = await verifyObject(isolated, "commit", spec.expected);
  if (v.kind === "failed") return { ok: false, reason: "fetch_failed" };
  return v.kind === "verified" ? { ok: true } : { ok: false, reason: "tip_mismatch" };
}
