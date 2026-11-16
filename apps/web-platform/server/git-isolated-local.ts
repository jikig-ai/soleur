/**
 * Token-free local git in a server-created isolated GIT_DIR (#12600, CTO rulings P, R6, R20).
 *
 * `runIsolatedGitLocal` runs one `git` child with `cwd` = the isolated directory, the shared `HARDENED_GIT_ARGS`, and the
 * allowlisted isolated environment from `buildIsolatedGitEnv` (no `extra`, so no askpass, no token, no identity key). It
 * is the runner for every decision and build the KB sync makes: hash checks, tree and commit builds, the pack it hands to
 * the workspace, and the `rev-parse` commit check of the approved cc push. None of these needs a credential, so none of
 * them mints one; and none of them reads the agent-writable workspace `.git` except its object store, as the alternate the
 * creator validated.
 *
 * `child_process` is imported lazily (inside the call) so sibling suites that mock `child_process` with a factory lacking
 * `execFile` still load every importer; a missing export then fails only on use, as a result here, never at import.
 *
 * The runner never rejects: a spawn failure, a timeout, a kill or the stdout cap is a result with `code: -1` (and `timedOut`), so a caller
 * holding an isolated directory always reaches its `finally`. Exit codes are surfaced as git gave them (1 vs 128 matters
 * to `rev-parse --verify --quiet` and to `cat-file -e`).
 */

import { createHash } from "node:crypto";

import { HEX40 } from "./approval/workspace-head";
import type { IsolatedPushDir } from "./git-hardened-env";
import { HARDENED_GIT_ARGS, buildIsolatedGitEnv } from "./git-hardened-env";

/** Default upper bound of one local child. A stalled child costs at most this long. */
export const ISOLATED_LOCAL_TIMEOUT_MS = 30_000;
/**
 * Default stdout cap: the hand-over pack holds only the two or three objects the server built (CTO ruling D10), so it is
 * small whatever the size of the KB change set; anything bigger fails closed (code -1).
 */
export const ISOLATED_LOCAL_MAX_BUFFER = 64 * 1024 * 1024;

export interface IsolatedGitResult {
  /** git's exit status; -1 when the child could not run, was killed, or exceeded the output cap. */
  readonly code: number;
  readonly stdout: Buffer;
  readonly stderr: string;
  readonly timedOut: boolean;
}

export interface IsolatedGitLocalOptions {
  /** Bytes written to the child's stdin (then closed). */
  readonly input?: Buffer | string;
  readonly timeoutMs?: number;
  /** stdout cap in bytes (default `ISOLATED_LOCAL_MAX_BUFFER`); the injectable seam of the scaled D10 row. */
  readonly maxBufferBytes?: number;
}

export async function runIsolatedGitLocal(
  isolated: IsolatedPushDir,
  args: readonly string[],
  opts: IsolatedGitLocalOptions = {},
): Promise<IsolatedGitResult> {
  const fail = (timedOut = false): IsolatedGitResult => ({ code: -1, stdout: Buffer.alloc(0), stderr: "", timedOut });
  try {
    // Throws (before anything runs) on a handle that is not a creator-made isolated directory.
    const env = buildIsolatedGitEnv(isolated);
    const { execFile } = await import("node:child_process");
    return await new Promise<IsolatedGitResult>((resolve) => {
      try {
        const child = execFile(
          "git",
          [...HARDENED_GIT_ARGS, ...args],
          {
            cwd: isolated.gitDir,
            env,
            timeout: opts.timeoutMs ?? ISOLATED_LOCAL_TIMEOUT_MS,
            encoding: "buffer",
            maxBuffer: opts.maxBufferBytes ?? ISOLATED_LOCAL_MAX_BUFFER,
          },
          (err, stdout, stderr) => {
            const out = Buffer.isBuffer(stdout) ? stdout : Buffer.from(String(stdout ?? ""));
            const errText = Buffer.isBuffer(stderr) ? stderr.toString("utf8") : String(stderr ?? "");
            if (!err) return resolve({ code: 0, stdout: out, stderr: errText, timedOut: false });
            const e = err as { code?: unknown; killed?: boolean; signal?: string | null };
            if (e.killed === true || e.signal === "SIGTERM") return resolve({ ...fail(true), stderr: errText });
            resolve({ code: typeof e.code === "number" ? e.code : -1, stdout: out, stderr: errText, timedOut: false });
          },
        );
        const stdin = (child as { stdin?: NodeJS.WritableStream | null } | undefined)?.stdin;
        if (stdin) {
          // A child that exits before reading its input (a refused argv) must not crash the process with EPIPE.
          stdin.on("error", () => {});
          if (opts.input !== undefined) stdin.end(opts.input);
          else stdin.end();
        }
      } catch {
        resolve(fail());
      }
    });
  } catch {
    return fail();
  }
}

export type GitObjectType = "commit" | "tree" | "blob";

/**
 * Tri-state result of `verifyObject` (CTO ruling D13): `verified` with the bytes whose id was recomputed; `unverified` when
 * git read nothing usable (the object is absent, of another type, or corrupt) or the bytes do not hash to the id (a forged
 * object); `failed` when the local child itself could not run (spawn failure, timeout, kill, output cap), which the caller
 * reports as `local_git_failed` and never as a hash mismatch.
 */
export type VerifiedObject =
  | { readonly kind: "verified"; readonly bytes: Buffer }
  | { readonly kind: "unverified" }
  | { readonly kind: "failed" };

/** Git's object id of `bytes` as a `type` object: `sha1("<type> <len>\0" + bytes)`. */
export function gitObjectId(type: GitObjectType, bytes: Buffer): string {
  return createHash("sha1").update(`${type} ${bytes.length}\0`, "latin1").update(bytes).digest("hex");
}

/**
 * Read one object's bytes with `cat-file <type> <id>` and recompute its id IN-PROCESS (measured `probe8.sh`: `cat-file`
 * itself does not refuse a forged loose or packed object; one child per object, CTO ruling D13). Returns the VERIFIED bytes,
 * so the caller parses exactly the bytes whose id was checked (no second read of a file the agent can swap).
 */
export async function verifyObject(
  isolated: IsolatedPushDir,
  type: GitObjectType,
  id: string,
): Promise<VerifiedObject> {
  if (!HEX40.test(id)) return { kind: "unverified" };
  const read = await runIsolatedGitLocal(isolated, ["cat-file", type, id]);
  if (read.code === -1) return { kind: "failed" };
  if (read.code !== 0) return { kind: "unverified" };
  return gitObjectId(type, read.stdout) === id ? { kind: "verified", bytes: read.stdout } : { kind: "unverified" };
}
