// In-process, per-workspace-id "being reaped" registry (#8211). `deleteWorkspace` runs its
// `rm -rf` ASYNCHRONOUSLY (up to a minute per child), so a request that re-provisions the same
// `<root>/<id>` in that window would have its NEW tree deleted by the still-running rm. Every
// path that creates a tree for an id asserts against this registry; a second delete for the
// same id joins the first instead of racing its move-aside.
//
// Process-local by design: the trees are host-local, and so is the rm.
import { WorkspaceReapInProgressError } from "./workspace-reap-error";

const inFlight = new Map<string, Promise<void>>();
// Abandoned-child holds: a reap child that outlived its hard stop (stuck in uninterruptible I/O,
// ignoring SIGKILL) may still be running its rm. The id stays blocked until that child's callback
// actually fires, so the reap's own `finally` cannot reopen the race while the rm is alive.
const liveChildren = new Map<string, number>();

/** A child that never exits cannot wedge an id forever: the hold is dropped after this. */
export const REAP_CHILD_HOLD_CEILING_MS = 10 * 60_000;

const key = (id: string) => id.toLowerCase();

/** True from the moment a reap for `id` is registered until it settles AND no abandoned child is alive. */
export function isWorkspaceBeingReaped(id: string): boolean {
  const k = key(id);
  return inFlight.has(k) || (liveChildren.get(k) ?? 0) > 0;
}

/** Throws {@link WorkspaceReapInProgressError} while `id` is being reaped. */
export function assertWorkspaceNotBeingReaped(id: string): void {
  if (isWorkspaceBeingReaped(id)) throw new WorkspaceReapInProgressError();
}

/**
 * Register a live reap child for `id`; call the returned function when the child's callback fires
 * (idempotent). After {@link REAP_CHILD_HOLD_CEILING_MS} the hold is dropped anyway and
 * `onCeiling` runs once (the caller logs a hashed breadcrumb). Counts, so overlapping reaps of one
 * id do not release each other's holds.
 */
export function beginReapChild(id: string, onCeiling?: () => void): () => void {
  const k = key(id);
  liveChildren.set(k, (liveChildren.get(k) ?? 0) + 1);
  let done = false;
  const release = () => {
    if (done) return;
    done = true;
    clearTimeout(timer);
    const n = (liveChildren.get(k) ?? 1) - 1;
    if (n <= 0) liveChildren.delete(k);
    else liveChildren.set(k, n);
  };
  const timer = setTimeout(() => {
    if (done) return;
    release();
    onCeiling?.();
  }, REAP_CHILD_HOLD_CEILING_MS);
  timer.unref?.();
  return release;
}

/**
 * Run `reap` as THE reap for `id`. A concurrent caller for the same id gets the SAME promise
 * (one reap, one outcome). The entry is released in `finally`, so a failure or a timeout never
 * leaves the id locked out of re-provisioning.
 */
export function runExclusiveReap(id: string, reap: () => Promise<void>): Promise<void> {
  const k = key(id);
  const running = inFlight.get(k);
  if (running) return running;
  const p = reap().finally(() => {
    if (inFlight.get(k) === p) inFlight.delete(k);
  });
  inFlight.set(k, p);
  return p;
}

/** Test-only: forget every registration. */
export function __resetReapGuardForTests(): void {
  inFlight.clear();
  liveChildren.clear();
}
