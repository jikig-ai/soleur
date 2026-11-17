// #12824 — the filesystem calls behind the cron plugin-root resolver and the per-spawn HOME, in one
// module so a handler test replaces them with a single `vi.mock` (CTO T8). Kept deliberately thin:
// every decision lives in `_cron-claude-eval-substrate.ts`; these functions only touch the disk.
import { accessSync, constants, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync } from "node:fs";
import { join } from "node:path";

/** True when `p` exists (file or directory). */
export function pathExists(p: string): boolean {
  return existsSync(p);
}

/** The text of `p`, or null when it cannot be read. */
export function readTextOrNull(p: string): string | null {
  try {
    return readFileSync(p, "utf-8");
  } catch {
    return null;
  }
}

/**
 * `W_OK` probe. Returns `{ writable: true }` when the process could write `p`; otherwise the errno
 * code the probe threw (`EROFS` on a `:ro` bind, `EACCES` on a root-owned tree, anything else is
 * not proof of read-only and the resolver treats it as a failure).
 */
export function probeWritable(p: string): { writable: boolean; code: string | null } {
  try {
    accessSync(p, constants.W_OK);
    return { writable: true, code: null };
  } catch (err) {
    return { writable: false, code: (err as NodeJS.ErrnoException).code ?? null };
  }
}

/**
 * Create a fresh per-spawn HOME under `parent` (mkdtemp, so mode 0700 and a unique name) with a
 * `tmp/` child at mode 0700 for TMPDIR. Returns the HOME path. Synchronous on purpose: a
 * `loadPlugin: false` spawn reaches `child_process.spawn` in the same tick as the call (the
 * #7122 exit-ordering tests depend on it), and two small mkdirs cost nothing.
 */
export function createSpawnHome(parent: string, prefix: string): string {
  const home = mkdtempSync(join(parent, prefix));
  try {
    mkdirSync(join(home, "tmp"), { mode: 0o700 });
  } catch (err) {
    rmSync(home, { recursive: true, force: true }); // never orphan a half-made HOME (ENOSPC)
    throw err;
  }
  return home;
}

/**
 * Remove a per-spawn HOME and everything under it. Synchronous: it runs in the spawn's `finally`
 * after the child has exited, and an async rm would let the run settle on libuv I/O timing (the
 * HOME holds the CLI's session state, a few MB at most).
 */
export function removeSpawnHome(home: string): void {
  rmSync(home, { recursive: true, force: true });
}

/** Injected wait for the resolver's single `.seed-complete` retry (tests pass a no-op). */
export function sleep(ms: number): Promise<void> {
  return new Promise((done) => setTimeout(done, ms));
}
