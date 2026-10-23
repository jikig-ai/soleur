// In-process, per-workspace-id "being reaped" registry (#8211). `deleteWorkspace` runs its
// `rm -rf` ASYNCHRONOUSLY (up to a minute per child), so a request that re-provisions the same
// `<root>/<id>` in that window would have its NEW tree deleted by the still-running rm. Every
// path that creates a tree for an id asserts against this registry; a second delete for the
// same id joins the first instead of racing its move-aside.
//
// Process-local by design: the trees are host-local, and so is the rm.
import { WorkspaceReapInProgressError } from "./workspace-reap-error";

const inFlight = new Map<string, Promise<void>>();

const key = (id: string) => id.toLowerCase();

/** True from the moment a reap for `id` is registered until it settles (success or failure). */
export function isWorkspaceBeingReaped(id: string): boolean {
  return inFlight.has(key(id));
}

/** Throws {@link WorkspaceReapInProgressError} while `id` is being reaped. */
export function assertWorkspaceNotBeingReaped(id: string): void {
  if (inFlight.has(key(id))) throw new WorkspaceReapInProgressError();
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
}
