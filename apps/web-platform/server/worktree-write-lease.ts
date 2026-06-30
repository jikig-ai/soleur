import { createServiceClient } from "@/lib/supabase/service";
import { reportSilentFallback } from "./observability";

/**
 * Thin RPC client over the migration-116 worktree-write-lease functions
 * (`acquire_worktree_lease` / `touch_worktree_lease` / `release_worktree_lease`).
 * Epic #5274 Phase 2, ADR-068 §2. Mirrors concurrency.ts:77-186 for the
 * RPC-call shape (lazy service client, transient retry on acquire,
 * reportSilentFallback on error, never throws).
 *
 * `host_id` is passed in by the caller — a host-STABLE infra identity (the
 * Hetzner server id injected at cloud-init), NEVER the per-container hostname
 * and NEVER an auth.uid(). Resolving that stable source + wiring acquire/touch/
 * release into the write path (SIGTERM-release, ≤30s heartbeat, fail-loud on a
 * touch-0, and the `git push --push-option=lease-gen=<N>` fence wrapper) is
 * PR B; this module provides only the lease primitives.
 */

/** The lease a host currently holds: its infra `host_id` + the fencing
 *  generation token it presents to the git-data host's pre-receive CAS. */
export interface WorktreeLease {
  hostId: string;
  leaseGeneration: number;
}

// Lazy-init: this module may be imported transitively by route files that
// `next build` evaluates with SUPABASE_URL unset. Evaluating
// createServiceClient() at module-eval time would throw there. Mirror
// concurrency.ts:48-58.
type ServiceClient = ReturnType<typeof createServiceClient>;
let _supabase: ServiceClient | null = null;
const supabase = new Proxy({} as ServiceClient, {
  get(_target, prop) {
    _supabase ??= createServiceClient();
    const value = Reflect.get(_supabase, prop);
    return typeof value === "function" ? value.bind(_supabase) : value;
  },
});

/** Transient Postgres error SQLSTATEs that warrant a single retry:
 *  40P01 deadlock_detected, 55P03 lock_not_available. Mirror concurrency.ts:62. */
const TRANSIENT_SQLSTATES = new Set(["40P01", "55P03"]);

function isTransient(err: unknown): boolean {
  const code = (err as { code?: string } | null)?.code;
  return typeof code === "string" && TRANSIENT_SQLSTATES.has(code);
}

function delay(ms: number): Promise<void> {
  return new Promise<void>((r) => setTimeout(r, ms));
}

/**
 * Acquire (or refresh) the write lease for `(workspaceId, worktreeId)` as
 * `hostId`. Returns the held lease on success, or `null` when the lease is held
 * live by ANOTHER host (the caller LOST — it must not write).
 *
 * Fail-closed: a non-transient RPC error is mirrored to Sentry and ALSO maps to
 * `null` — the caller cannot prove it holds the lease, so it must treat the
 * acquire as lost and not write. Bounded jittered retry covers deadlock /
 * lock-timeout on the per-key advisory xact lock. Never throws.
 */
export async function acquireWorktreeLease(
  workspaceId: string,
  worktreeId: string,
  hostId: string,
): Promise<WorktreeLease | null> {
  for (let attempt = 0; attempt < 3; attempt++) {
    const { data, error } = await supabase.rpc("acquire_worktree_lease", {
      p_workspace_id: workspaceId,
      p_worktree_id: worktreeId,
      p_host_id: hostId,
    });
    // A clean response with a DEFINED payload: [] = a live lease held by another
    // host (legitimate loss — silent, no Sentry), one row = we hold it. Gate on
    // `data !== null` so an anomalous `{data: null, error: null}` PostgREST
    // response (e.g. an RPC timeout) is NOT mistaken for "lost" and silently
    // swallowed — it falls through to retry, then to the exhaustion mirror below
    // (mirror concurrency.ts:93-128; cq-silent-fallback-must-mirror-to-sentry).
    if (!error && data !== null) {
      const rows = data as { host_id: string; lease_generation: number }[];
      if (rows.length === 0) return null; // a live lease held by another host
      const row = rows[0]!;
      return { hostId: row.host_id, leaseGeneration: Number(row.lease_generation) };
    }
    if (isTransient(error) && attempt < 2) {
      await delay(80 + Math.random() * 40); // 80–120 ms jitter (mirror concurrency)
      continue;
    }
    if (error) {
      reportSilentFallback(error, {
        feature: "worktree_lease",
        op: "acquireWorktreeLease",
        extra: { workspaceId, worktreeId, hostId, attempt },
      });
      return null; // fail-closed: caller cannot prove it holds → must not write
    }
    // !error && data === null (anomalous): retry while attempts remain.
    if (attempt < 2) {
      await delay(80 + Math.random() * 40);
      continue;
    }
  }
  // Exhausted: 3 transient errors OR 3 anomalous {data:null,error:null} responses.
  // Mirror to Sentry so the fail-close is operator-visible — now REACHABLE via the
  // null-data fall-through above (concurrency.ts:116-128).
  reportSilentFallback(
    new Error("acquireWorktreeLease exhausted 3 retries without data or error"),
    {
      feature: "worktree_lease",
      op: "acquireWorktreeLease",
      extra: { workspaceId, worktreeId, hostId },
    },
  );
  return null;
}

/**
 * Heartbeat the held lease. Returns `true` while still held; `false` when the
 * lease was reclaimed (host_id changed, gen bumped, or row gone) — the caller
 * MUST treat `false` as "you no longer hold it", abort the in-flight write, and
 * fail loud (the Sentry `worktree_lease` slug wiring is PR B). The caller passes
 * the gen from its most-recent successful acquire. An RPC error maps to `false`
 * (treated as lost) and is mirrored to Sentry. Never throws.
 */
export async function touchWorktreeLease(
  workspaceId: string,
  worktreeId: string,
  hostId: string,
  leaseGeneration: number,
): Promise<boolean> {
  const { data, error } = await supabase.rpc("touch_worktree_lease", {
    p_workspace_id: workspaceId,
    p_worktree_id: worktreeId,
    p_host_id: hostId,
    p_lease_generation: leaseGeneration,
  });
  if (error) {
    reportSilentFallback(error, {
      feature: "worktree_lease",
      op: "touchWorktreeLease",
      extra: { workspaceId, worktreeId, hostId, leaseGeneration },
    });
    return false;
  }
  // RPC returns the updated integer row count (0 or 1).
  const updated = typeof data === "number" ? data : Number(data ?? 0);
  return updated > 0;
}

/**
 * Graceful release: delete the lease row only if `hostId` AND `leaseGeneration`
 * still match (a reclaimer's row is never stomped — a stale-gen release is a
 * server-side no-op). Best-effort teardown: errors are mirrored to Sentry but
 * not re-thrown. Never throws.
 */
export async function releaseWorktreeLease(
  workspaceId: string,
  worktreeId: string,
  hostId: string,
  leaseGeneration: number,
): Promise<void> {
  try {
    const { error } = await supabase.rpc("release_worktree_lease", {
      p_workspace_id: workspaceId,
      p_worktree_id: worktreeId,
      p_host_id: hostId,
      p_lease_generation: leaseGeneration,
    });
    if (error) {
      reportSilentFallback(error, {
        feature: "worktree_lease",
        op: "releaseWorktreeLease",
        extra: { workspaceId, worktreeId, hostId, leaseGeneration },
      });
    }
  } catch (err) {
    reportSilentFallback(err, {
      feature: "worktree_lease",
      op: "releaseWorktreeLease",
      extra: { workspaceId, worktreeId, hostId, leaseGeneration },
    });
  }
}

// --- Held-lease registry (SIGTERM drain) ------------------------------------
// Process-local record of the leases this host currently holds, so the SIGTERM
// handler can release them before exit (a graceful release lets a surviving host
// reclaim immediately rather than waiting out the 120s heartbeat expiry). Mirrors
// the module-level Map pattern in agent-session-registry.ts, collocated here so
// the lease concern owns its own lifecycle state.

/** A lease currently held by this host, keyed by `(workspaceId, worktreeId)`. */
export interface HeldWorktreeLease {
  workspaceId: string;
  worktreeId: string;
  hostId: string;
  leaseGeneration: number;
}

const heldLeases = new Map<string, HeldWorktreeLease>();

function heldKey(workspaceId: string, worktreeId: string): string {
  return `${workspaceId}:${worktreeId}`;
}

/** Record a held lease (call after a successful acquire). Idempotent per key. */
export function registerHeldLease(lease: HeldWorktreeLease): void {
  heldLeases.set(heldKey(lease.workspaceId, lease.worktreeId), lease);
}

/** Drop a held lease from the registry (call after release / on loss). */
export function unregisterHeldLease(
  workspaceId: string,
  worktreeId: string,
): void {
  heldLeases.delete(heldKey(workspaceId, worktreeId));
}

/**
 * Release every held lease — the SIGTERM drain step (server/index.ts, after the
 * cc-query drain, before server.close()). Best-effort + bounded: each release is
 * a never-throwing RPC, run concurrently via allSettled so one slow release can't
 * starve the 8s shutdown budget. Clears the registry up front so a release that
 * races a concurrent acquire doesn't resurrect a stale entry. A lease that fails
 * to release simply expires at 120s and a surviving host reclaims it.
 */
export async function releaseAllHeldLeases(): Promise<void> {
  const leases = [...heldLeases.values()];
  heldLeases.clear();
  await Promise.allSettled(
    leases.map((l) =>
      releaseWorktreeLease(
        l.workspaceId,
        l.worktreeId,
        l.hostId,
        l.leaseGeneration,
      ),
    ),
  );
}

/** Test-only registry accessors (the runtime never reads these). */
export const __test_only__ = {
  heldLeaseCount: (): number => heldLeases.size,
  clearHeldLeases: (): void => heldLeases.clear(),
};
