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
    if (!error) {
      const rows = (data ?? []) as { host_id: string; lease_generation: number }[];
      if (rows.length === 0) return null; // a live lease held by another host
      const row = rows[0]!;
      return { hostId: row.host_id, leaseGeneration: Number(row.lease_generation) };
    }
    if (isTransient(error) && attempt < 2) {
      await delay(80 + Math.random() * 40); // 80–120 ms jitter (mirror concurrency)
      continue;
    }
    reportSilentFallback(error, {
      feature: "worktree_lease",
      op: "acquireWorktreeLease",
      extra: { workspaceId, worktreeId, hostId, attempt },
    });
    return null; // fail-closed: caller cannot prove it holds → must not write
  }
  // 3 transient retries exhausted — fail-closed with operator visibility.
  reportSilentFallback(
    new Error("acquireWorktreeLease exhausted 3 retries"),
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
