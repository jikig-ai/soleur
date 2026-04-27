// In-process serialization + atomic-write helper for
// `patchWorkspacePermissions` (#2918). Two cold-Query constructions on
// the same workspace path can interleave their read-modify-write of
// `<workspace>/.claude/settings.json`; the lost-update race drops one
// caller's filtered allowlist. Lock is keyed on the canonicalized
// workspace path (`path.resolve`).
//
// Multi-process coordination is OUT OF SCOPE — single Next.js worker
// per container at current scale. See plan §Risks.
//
// Atomic-write durability sequence: open → write → fdatasync → close →
// rename. `fdatasync` flushes data without metadata; the subsequent
// `rename(2)` POSIX-atomically swaps the dir entry. Skipping the sync
// risks: machine crash between rename and journal flush leaves a
// zero-byte file at `<path>` (the new dir entry, but no data blocks
// committed). See `withWorkspacePermissionLock` consumers in
// `agent-runner.ts patchWorkspacePermissions`.

import {
  closeSync,
  fdatasyncSync,
  openSync,
  renameSync,
  unlinkSync,
  writeSync,
} from "fs";
import path from "path";
import { randomUUID } from "crypto";

import { createChildLogger } from "./logger";

const log = createChildLogger("workspace-permission-lock");

// Defense-in-depth: warn if the in-flight lock map ever grows beyond
// reasonable scale. Each entry is keyed on a canonicalized workspace
// path; a normal busy server has ~O(active sessions). A 10k+ map size
// suggests a leak (lock never released) or a misuse pattern that
// invalidates the GC clause below.
const LOCK_SIZE_WARN_THRESHOLD = 10_000;

// Map keyed on canonicalized workspace path. Value is the tail of the
// chain; new callers chain off it. Garbage-collected when the tail
// resolves AND no later caller has appended.
const _locks = new Map<string, Promise<void>>();

/**
 * Serialize `fn` calls keyed on `workspacePath`. Same canonicalized
 * path → strict FIFO ordering. Different paths → concurrent.
 *
 * Lock is freed on `fn` resolve OR throw — caller's throw is
 * propagated unchanged.
 */
export async function withWorkspacePermissionLock<T>(
  workspacePath: string,
  fn: () => Promise<T> | T,
): Promise<T> {
  if (_locks.size > LOCK_SIZE_WARN_THRESHOLD) {
    log.warn(
      { size: _locks.size, op: "workspace-permission-lock" },
      "_locks map size unexpectedly large — investigate possible release leak",
    );
  }
  const key = path.resolve(workspacePath);
  const previous = _locks.get(key) ?? Promise.resolve();

  // Build the new tail. We MUST set _locks.set BEFORE awaiting `previous`
  // so a concurrent caller arriving in the same microtask sees our entry
  // and chains off it (not off the older `previous`).
  let release!: () => void;
  const next = new Promise<void>((r) => {
    release = r;
  });
  const tail = previous.then(() => next);
  _locks.set(key, tail);

  try {
    await previous;
    return await fn();
  } finally {
    release();
    // GC: only delete if we're still the registered tail (a later
    // caller may have already appended their own promise).
    if (_locks.get(key) === tail) {
      _locks.delete(key);
    }
  }
}

/**
 * Atomically write JSON to `targetPath`. Sequence:
 *   1. JSON.stringify (throws BEFORE any filesystem mutation — caller
 *      sees no partial state)
 *   2. open `<targetPath>.<pid>.<rand>.tmp`
 *   3. write JSON
 *   4. fdatasync (durability — see module header)
 *   5. close
 *   6. rename to targetPath (POSIX atomic; replaces existing file)
 * On any throw at steps 2-6, best-effort `unlinkSync` of the tmp file.
 * Cleanup never masks the original error.
 */
export function atomicWriteJson(targetPath: string, obj: unknown): void {
  // Step 1: encode BEFORE opening — cyclic objects throw here, leaving
  // the filesystem untouched.
  const json = JSON.stringify(obj, null, 2) + "\n";

  // Step 2: open tmp. PID + random suffix avoids same-process collisions
  // (defense-in-depth — the mutex above already serializes) and any
  // stale `.tmp` from a crashed prior run.
  const tmpPath = `${targetPath}.${process.pid}.${randomUUID().slice(0, 8)}.tmp`;
  let fd: number | null = null;
  try {
    fd = openSync(tmpPath, "w");
    writeSync(fd, json);
    // Step 4: fdatasync flushes data only (not inode metadata) — the
    // following rename creates the metadata entry atomically.
    fdatasyncSync(fd);
    closeSync(fd);
    fd = null;
    // Step 6: POSIX-atomic rename. After this returns, readers see the
    // new content; before it, they see the prior content (or ENOENT).
    renameSync(tmpPath, targetPath);
  } catch (err) {
    if (fd !== null) {
      try {
        closeSync(fd);
      } catch {
        // best-effort
      }
    }
    try {
      unlinkSync(tmpPath);
    } catch {
      // tmp may not exist (open failed) or already renamed — ignore.
    }
    throw err;
  }
}
