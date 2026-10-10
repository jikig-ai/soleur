/**
 * #9776 / ADR-284 — the protected-branch set for the hosted must-ask lane. The lane's only I/O.
 *
 * Union of:
 *   (a) the GitHub API `default_branch`, read with the server-held installation token (the agent cannot tamper
 *       with it: `authoritative = true`);
 *   (b) the local `<workspace>/.git/refs/remotes/origin/HEAD` (agent-writable, so it may only ADD a name);
 *   (c) the constants `main` and `master`.
 *
 * Failure (no installation, no connected repo, API error, timeout, an unusable answer) yields
 * `authoritative: false` and a Sentry mirror (`default-branch-resolve`); the classifier then asks on every force,
 * delete or mirror push. The result is memoised per resolver instance (one resolver per session record): a
 * positive result for 10 minutes (a default-branch rename must not stay stale for a whole session), a negative
 * one for 30 s. Concurrent callers share one in-flight lookup. Nothing here runs per command.
 */
import { constants as fsConstants } from "node:fs";
import { lstat, open } from "node:fs/promises";
import { join } from "node:path";
import { reportSilentFallback } from "./observability";
import type { ProtectedBranches } from "./destroy-ask-classifier";

export const POSITIVE_TTL_MS = 10 * 60_000;
export const NEGATIVE_TTL_MS = 30_000;
export const RESOLVE_TIMEOUT_MS = 3_000;
const LOCAL_HEAD_MAX_BYTES = 512;
const CONSTANT_NAMES = ["main", "master"] as const;
const SAFE_BRANCH_RE = /^[A-Za-z0-9._/-]{1,255}$/;
const SAFE_SEGMENT_RE = /^[A-Za-z0-9._-]+$/;
const LOCAL_HEAD_RE = /^ref: refs\/remotes\/origin\/([A-Za-z0-9._/-]{1,255})\n?$/;

export interface ProtectedBranchInput {
  owner: string;
  repo: string;
  installationId: number | null;
  workspacePath: string;
}

export interface ProtectedBranchDeps {
  fetchDefaultBranch?: (installationId: number, owner: string, repo: string, signal: AbortSignal) => Promise<string>;
  now?: () => number;
  /** Seam for tests; defaults to the hardened local read. */
  readLocal?: (workspacePath: string) => Promise<string | null>;
}

function isSafeBranch(name: unknown): name is string {
  return typeof name === "string" && SAFE_BRANCH_RE.test(name) && !name.includes("..") && !name.startsWith("/");
}

async function defaultFetchDefaultBranch(
  installationId: number,
  owner: string,
  repo: string,
  signal: AbortSignal,
): Promise<string> {
  // Lazy: keeps the GitHub App / JWT import graph out of every `permission-callback` consumer's module load.
  const { githubApiGet } = await import("./github-api");
  const data = await githubApiGet<{ default_branch?: unknown }>(installationId, `/repos/${owner}/${repo}`, { signal });
  return data?.default_branch as string;
}

/**
 * Read the local origin/HEAD symref. Hardened: refuses symlinks, FIFOs and any non-regular file, caps the size
 * and accepts only `ref: refs/remotes/origin/<safe-charset>`. Returns null on anything else; never throws.
 */
export async function readLocalOriginHead(workspacePath: string): Promise<string | null> {
  try {
    const path = join(workspacePath, ".git", "refs", "remotes", "origin", "HEAD");
    const st = await lstat(path);
    if (!st.isFile() || st.isSymbolicLink() || st.size > LOCAL_HEAD_MAX_BYTES || st.size === 0) return null;
    const fh = await open(path, fsConstants.O_RDONLY | fsConstants.O_NOFOLLOW | fsConstants.O_NONBLOCK);
    try {
      const fst = await fh.stat();
      if (!fst.isFile() || fst.size > LOCAL_HEAD_MAX_BYTES) return null;
      const buf = Buffer.alloc(LOCAL_HEAD_MAX_BYTES + 1);
      const { bytesRead } = await fh.read(buf, 0, LOCAL_HEAD_MAX_BYTES + 1, 0);
      if (bytesRead > LOCAL_HEAD_MAX_BYTES) return null;
      const m = LOCAL_HEAD_RE.exec(buf.subarray(0, bytesRead).toString("utf8"));
      if (!m || !isSafeBranch(m[1])) return null;
      return m[1];
    } finally {
      await fh.close();
    }
  } catch {
    return null;
  }
}

export function createProtectedBranchResolver(
  input: ProtectedBranchInput,
  deps: ProtectedBranchDeps = {},
): () => Promise<ProtectedBranches> {
  const fetchDefaultBranch = deps.fetchDefaultBranch ?? defaultFetchDefaultBranch;
  const now = deps.now ?? Date.now;
  const readLocal = deps.readLocal ?? readLocalOriginHead;
  let cached: { value: ProtectedBranches; expiresAt: number } | null = null;
  let inflight: Promise<ProtectedBranches> | null = null;

  const resolveOnce = async (): Promise<ProtectedBranches> => {
    const names = new Set<string>(CONSTANT_NAMES);
    const local = await readLocal(input.workspacePath);
    if (local) names.add(local.toLowerCase());

    let authoritative = false;
    let reason: string | null = null;
    let failure: unknown = null;
    const { owner, repo, installationId } = input;
    if (installationId === null || !owner || !repo || !SAFE_SEGMENT_RE.test(owner) || !SAFE_SEGMENT_RE.test(repo)) {
      reason = "no-installation-or-repo";
    } else {
      const ac = new AbortController();
      let timer: ReturnType<typeof setTimeout> | undefined;
      const timeout = new Promise<never>((_res, rej) => {
        timer = setTimeout(() => {
          ac.abort();
          rej(new Error("default-branch lookup timed out"));
        }, RESOLVE_TIMEOUT_MS);
      });
      try {
        const name = await Promise.race([fetchDefaultBranch(installationId, owner, repo, ac.signal), timeout]);
        if (isSafeBranch(name)) {
          names.add(name.toLowerCase());
          authoritative = true;
        } else {
          reason = "unusable-answer";
        }
      } catch (err) {
        reason = "api-error";
        failure = err;
      } finally {
        if (timer) clearTimeout(timer);
      }
    }
    if (!authoritative) {
      // Never the branch name, the command or a path: only the failure class.
      reportSilentFallback(failure, {
        feature: "cc-permissions",
        op: "default-branch-resolve",
        message: `default branch unresolved (${reason}); every force, delete or mirror push will ask`,
        extra: { reason },
      });
    }
    return { names, authoritative };
  };

  return async () => {
    const t = now();
    if (cached && cached.expiresAt > t) return cached.value;
    if (!inflight) {
      inflight = resolveOnce()
        .then((value) => {
          cached = { value, expiresAt: now() + (value.authoritative ? POSITIVE_TTL_MS : NEGATIVE_TTL_MS) };
          return value;
        })
        .finally(() => {
          inflight = null;
        });
    }
    return inflight;
  };
}
