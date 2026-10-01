// Per-process scratch root for a directly-run test runner (ADR-250 producer side, #9117).
//
// PROPERTY. A runner started DIRECTLY (`bun test <file>`, `vitest run <file>`) leaves no new entry in
// its TMPDIR base after a normal exit or SIGINT/SIGTERM, and a SIGKILLed runner leaves only an entry
// the reapers can attribute. `scripts/test-all.sh` already binds a `soleur-run.<pid>.*` root for the
// gate; this module gives the documented inner loop (one suite, run by hand or by an agent) the same
// guarantee, using the SAME marker format as `soleur_scratch_mark_owned` in
// `scripts/lib/scratch-root.sh` -- `pid=`, `schema=1`, `ns=` -- so `tc_marker_owner_pid` in
// `plugins/soleur/scripts/lib/tmp-classify.sh` is the one parser of all three writers (shell, this
// file, `tests/conftest.py`). `tests/scripts/test-scratch-residue.sh` pins that.
//
// WHY IN LINE AND NOT AN IMPORT SIDE EFFECT. `ensureIncidentSandbox()` allocates a `soleur-inc-*`
// directory under `os.tmpdir()`. If the root does not exist yet, that directory lands in the shared
// base and escapes cleanup. Callers therefore invoke `ensureScratchSession()` as a statement
// immediately BEFORE `ensureIncidentSandbox()`; `.claude/hooks/incident-sandbox-coverage.test.sh`
// asserts the order for every chokepoint.
//
// NESTING. When `SOLEUR_SCRATCH_SESSION_ROOT` is set and VALID (exists, a real directory, same uid,
// carries a marker from the same uid and the same pid namespace whose owner pid is alive and > 1) the parent's
// root governs: it is adopted, nothing is registered, and it is never deleted by this process. An
// invalid value (stale dir, no marker, dead owner, foreign namespace) is NOT adopted: a fresh root is
// created instead and the stale directory is left untouched.
//
// REMOVAL happens only for a root THIS call created: on `exit` (and, under `bun test`, which never
// emits it, a preload-level `afterAll`) and, for SIGINT/SIGTERM, before the
// signal is re-raised so the process keeps its 128+n status. When another listener already owns the
// signal (a runner's graceful shutdown) we do not re-raise; the `exit` handler removes the root once
// that runner finishes. SIGKILL cannot be handled, which is exactly why the marker is written at
// creation. `SOLEUR_KEEP_SCRATCH=1` skips removal so a failing fixture can be inspected.
//
// BASE. A TMPDIR that points INSIDE a standard scratch base (systemd PrivateTmp and similar yield
// `/tmp/<sub>`) is normalised up to that base, exactly as `soleur_scratch_session_begin` does: Reaper 3
// enumerates `-maxdepth 1 -name 'soleur-run.*'` under each base, so a root at depth 2 is invisible to it
// and leaks silently. The standard bases are `TMPFS_GUARD_SCRATCH_BASES` (default `/tmp /var/tmp`), the
// list Reaper 3 itself reads; setting it to a path that matches no TMPDIR is also how the canary keeps
// its private base from being normalised into the real /tmp.
//
// No shell trap is involved (ADR-129 concerns shell EXIT traps; process exit handlers compose).

import { mkdirSync, lstatSync, readFileSync, readlinkSync, renameSync, rmSync, writeFileSync } from "node:fs";
import { randomBytes } from "node:crypto";
import { createRequire } from "node:module";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";

const MARKER = ".soleur-owned";

let ownedRoot: string | null = null;

function pidNamespace(): string {
  try {
    return readlinkSync("/proc/self/ns/pid");
  } catch {
    return "pid:[unknown]";
  }
}

function sameUid(uid: number): boolean {
  return typeof process.getuid !== "function" || uid === process.getuid();
}

/** The bases Reaper 3 scans at depth 1 (`TMPFS_GUARD_SCRATCH_BASES`, default `/tmp /var/tmp`). */
function standardBases(): string[] {
  const raw = process.env.TMPFS_GUARD_SCRATCH_BASES ?? "/tmp /var/tmp";
  return raw
    .split(/\s+/)
    .filter((b) => b.startsWith("/"))
    .map((b) => b.replace(/\/+$/, ""))
    .filter((b) => b !== "");
}

/** `/tmp/<sub>/...` -> `/tmp` (and likewise for each standard base); anything else is returned as is. */
export function normalizeScratchBase(base: string): string {
  let b = base.length > 1 ? base.replace(/\/+$/, "") : base;
  const bases = standardBases();
  for (;;) {
    const inside = bases.some((s) => b.startsWith(`${s}/`));
    if (!inside) return b;
    b = b.slice(0, b.lastIndexOf("/"));
  }
}

/** True when `root` is a root a live same-uid, same-namespace process declared it owns. */
export function isAdoptableScratchRoot(root: string): boolean {
  try {
    if (!root.startsWith("/")) return false;
    const st = lstatSync(root);
    if (!st.isDirectory() || st.isSymbolicLink() || !sameUid(st.uid)) return false;
    const mp = join(root, MARKER);
    const ms = lstatSync(mp);
    if (!ms.isFile() || ms.isSymbolicLink() || !sameUid(ms.uid)) return false;
    const body = readFileSync(mp, "utf8");
    const ns = /^ns=(pid:\[[0-9]+\])$/m.exec(body)?.[1];
    const pid = /^pid=([0-9]+)$/m.exec(body)?.[1];
    const myNs = pidNamespace();
    if (!ns || !pid || myNs === "pid:[unknown]" || ns !== myNs) return false;
    // pid 0 would make `kill(0, 0)` signal OUR OWN process group (always "alive"), and pid 1 is init:
    // neither can be the owner of a scratch root (`tc_owner_alive` calls both dead).
    if (Number(pid) <= 1) return false;
    try {
      process.kill(Number(pid), 0);
    } catch (e) {
      // ESRCH: owner is dead. EPERM: a live pid we may not signal is another uid's, which cannot be
      // the owner of a same-uid marker (tc_owner_alive makes the same call).
      return false;
    }
    return true;
  } catch {
    return false;
  }
}

/** Write `<dir>/.soleur-owned` atomically (tmp + rename) in the format `tc_marker_owner_pid` parses. */
export function writeScratchMarker(dir: string, pid: number = process.pid): void {
  const tmp = join(dir, `${MARKER}.${randomBytes(4).toString("hex")}`);
  // "wx": exclusive create, so a planted file or symlink at the tmp name is an error, not a write target.
  writeFileSync(tmp, `pid=${pid}\nschema=1\nns=${pidNamespace()}\n`, { mode: 0o600, flag: "wx" });
  try {
    renameSync(tmp, join(dir, MARKER));
  } catch (e) {
    rmSync(tmp, { force: true });
    throw e;
  }
}

function createRoot(base: string): string {
  for (let attempt = 0; attempt < 8; attempt++) {
    // 6 random bytes -> exactly 8 base64url characters: the `soleur-run.<pid>.XXXXXXXX` schema.
    const root = join(base, `soleur-run.${process.pid}.${randomBytes(6).toString("base64url")}`);
    try {
      mkdirSync(root, { mode: 0o700 });
    } catch (e) {
      if ((e as NodeJS.ErrnoException).code === "EEXIST") continue;
      throw e;
    }
    try {
      writeScratchMarker(root);
    } catch (e) {
      rmSync(root, { recursive: true, force: true });
      throw e;
    }
    return root;
  }
  throw new Error(`scratch-session: could not allocate a root under ${base}`);
}

function installRemoval(root: string): void {
  const remove = (): void => {
    if (process.env.SOLEUR_KEEP_SCRATCH === "1") return;
    try {
      rmSync(root, { recursive: true, force: true });
    } catch {
      // A concurrent reaper removing the same tree is the expected race, not an error.
    }
  };
  process.on("exit", remove);
  // `bun test` ends the process without emitting `exit` or `beforeExit` (measured), so the handler
  // above never runs for the runner this module exists for. A preload-level `afterAll` is the
  // runner's own end-of-run hook and fires exactly once, after the last file. Bun-only; vitest runs
  // on node, where `exit` fires, and `bun run` has no test lifecycle (hence the guard).
  if (typeof (globalThis as { Bun?: unknown }).Bun !== "undefined") {
    try {
      const { afterAll } = createRequire(import.meta.url)("bun:test") as { afterAll: (fn: () => void) => void };
      afterAll(remove);
    } catch {
      // Not under the test runner: the `exit` handler above is the removal path.
    }
  }
  for (const sig of ["SIGINT", "SIGTERM"] as const) {
    const handler = (): void => {
      process.removeListener(sig, handler);
      // Another listener (a runner's graceful shutdown) still owns this signal: leave removal to the
      // `exit` handler so we do not pull TMPDIR out from under workers mid-shutdown.
      if (process.listenerCount(sig) > 0) return;
      remove();
      process.kill(process.pid, sig);
    };
    process.on(sig, handler);
  }
}

/**
 * Bind this process to a scratch root and point TMPDIR at it. Idempotent. Returns the root in force.
 *
 * Call it as a statement immediately before `ensureIncidentSandbox()`.
 */
export function ensureScratchSession(): string {
  if (ownedRoot !== null) return ownedRoot;

  const inherited = process.env.SOLEUR_SCRATCH_SESSION_ROOT;
  let base = tmpdir();
  if (inherited !== undefined && inherited !== "") {
    if (isAdoptableScratchRoot(inherited)) {
      // Parent governs. Pin TMPDIR to it so every descendant allocation lands inside the root that
      // its owner will remove; a caller that exported only the root var would otherwise leak.
      process.env.TMPDIR = inherited;
      return inherited;
    }
    // Invalid: never adopt it. If TMPDIR points AT the invalid root, allocate beside it, not inside.
    if (base.replace(/\/+$/, "") === inherited.replace(/\/+$/, "")) base = dirname(inherited);
  }

  const root = createRoot(normalizeScratchBase(base));
  ownedRoot = root;
  process.env.TMPDIR = root;
  process.env.SOLEUR_SCRATCH_SESSION_ROOT = root;
  // Children that write markers by default (`soleur_scratch_mark_owned`) key them to the owner pid.
  process.env.SOLEUR_SCRATCH_OWNER_PID = String(process.pid);
  installRemoval(root);
  return root;
}
