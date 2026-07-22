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
 * release into the write path (SIGTERM-release, ≤50s heartbeat, fail-loud on a
 * touch-0, and the `git push --push-option=lease-gen=<N>` fence wrapper) is
 * PR B; this module provides only the lease primitives.
 */

// worktree_id names a lease row (migration 116 PK `(workspace_id, worktree_id)`),
// a fence sidecar file on the git-data host (`fence/<worktree_id>.gen`), AND a
// git-data ref namespace (`refs/soleur/worktrees/<worktree_id>/…`). So it must be
// an opaque safe token at every boundary that builds a path or ref from it. The
// allowlist mirrors `assertSafeWorkspaceId` (git-data-replication.ts) and the
// host-side shell guard (git-data-pre-receive.sh:92-96) — CWE-22.
const WORKTREE_ID_RE = /^[A-Za-z0-9._-]+$/;

/**
 * Assert `worktreeId` is a safe opaque token before it keys a lease row, names a
 * fence sidecar, or builds a `refs/soleur/worktrees/<id>/…` refspec. Throws
 * (fail-loud) on any unsafe value — defense-in-depth at the app boundary,
 * symmetric to the host-side pre-receive validation. (Epic #5274 Phase 3 D0.)
 */
export function assertSafeWorktreeId(worktreeId: string): void {
  if (
    worktreeId === "" ||
    worktreeId === "." ||
    worktreeId === ".." ||
    worktreeId.includes("/") ||
    !WORKTREE_ID_RE.test(worktreeId)
  ) {
    throw new Error(
      `worktree-write-lease: refusing unsafe worktree_id '${worktreeId}' (must ` +
        `match ${WORKTREE_ID_RE} and not be a dot/slash path — CWE-22).`,
    );
  }
}

/**
 * Resolve the PER-USER worktree id for `userId` (ADR-068 D0 amendment, epic
 * #5274 Phase 3). Under user-sticky routing each user of a workspace gets their
 * OWN worktree → own write-lease → own fence generation stream → own git-data
 * ref namespace. Keying the worktree id off the user's own id gives two users of
 * one workspace two distinct leases (routable to two hosts, ADR-068 G1) while
 * two lineages of the SAME user (legacy agent-runner + cc-dispatcher) share one
 * lease via migration-116's same-host carve-out.
 *
 * `userId` is a UUID, so it satisfies {@link assertSafeWorktreeId} natively; the
 * assertion is still run (fail-loud) so a corrupted/non-UUID id never silently
 * builds a bad ref path. This REPLACES the hardcoded `"primary"` constant — a
 * lingering hardcoded worktree id would re-pin the whole workspace to one host.
 */
export function resolveWorktreeId(userId: string): string {
  assertSafeWorktreeId(userId);
  return userId;
}

/** The lease a host currently holds: its infra `host_id` + the fencing
 *  generation token it presents to the git-data host's pre-receive CAS. */
export interface WorktreeLease {
  hostId: string;
  leaseGeneration: number;
}

/** Liveness window for a read-only holder lookup (session routing). Mirrors the
 *  migration-116/133 lease expiry: a lease whose `heartbeat_at` is older than this
 *  is reclaimable (acquire bumps gen past 240s of silence) and is NOT a live owner —
 *  a `release` tombstones by ageing the heartbeat out, so an expired/tombstoned
 *  row reads as "no live holder" (cold → the placing host acquires).
 *  Raised 120s→240s (Disk-IO write reduction, 2026-07-18) IN LOCKSTEP with the
 *  SQL takeover predicate (migration 133, acquire_worktree_lease) and the 25s→50s
 *  WORKTREE_LEASE_HEARTBEAT_MS below — the TS window and the SQL predicate MUST
 *  move together or a live lease-holder is stolen after only 120s of silence. */
export const LEASE_LIVENESS_WINDOW_MS = 240_000;

/** The LIVE holder of a `(workspaceId, worktreeId)` lease, as read by the session
 *  router to place an inbound session. */
export interface WorktreeLeaseHolder {
  hostId: string;
  leaseGeneration: number;
  heartbeatAt: string;
}

/**
 * Read the CURRENT LIVE holder of the `(workspaceId, worktreeId)` lease, or
 * `null` when there is none — the row is absent (cold session) OR its heartbeat
 * is older than {@link LEASE_LIVENESS_WINDOW_MS} (a tombstoned/expired lease the
 * next acquire will reclaim). READ-ONLY: no acquire side effect, so the router
 * can decide local-serve vs proxy-to-owner without stealing the lease. Uses the
 * service client (the lease table is operational state; this bypasses RLS to read
 * any tenant's row for routing — never returns tenant CONTENT, only a host id +
 * gen).
 *
 * Fail-QUIET to `null` on a DB read error (mirrored to Sentry): the placing host
 * then treats the session as cold and acquires — and `acquireWorktreeLease` is
 * itself fail-CLOSED (returns null if another host truly holds it live), with the
 * git-data fence as the ultimate write guard. So a routing read-error degrades to
 * honest-reconnect affinity loss, never a cross-tenant write.
 */
export async function readWorktreeLeaseHolder(
  workspaceId: string,
  worktreeId: string,
): Promise<WorktreeLeaseHolder | null> {
  const { data, error } = await supabase
    .from("worktree_write_lease")
    .select("host_id, lease_generation, heartbeat_at")
    .eq("workspace_id", workspaceId)
    .eq("worktree_id", worktreeId)
    .maybeSingle();
  if (error) {
    reportSilentFallback(error, {
      feature: "worktree_lease",
      op: "readWorktreeLeaseHolder",
      extra: { workspaceId, worktreeId },
    });
    return null;
  }
  const row = data as
    | { host_id: string; lease_generation: number; heartbeat_at: string }
    | null;
  if (!row) return null;
  const heartbeatMs = Date.parse(row.heartbeat_at);
  if (Number.isNaN(heartbeatMs) || Date.now() - heartbeatMs > LEASE_LIVENESS_WINDOW_MS) {
    return null; // tombstoned / expired — no live owner (cold → local acquire)
  }
  return {
    hostId: row.host_id,
    leaseGeneration: Number(row.lease_generation),
    heartbeatAt: row.heartbeat_at,
  };
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
// reclaim immediately rather than waiting out the 240s heartbeat expiry). Mirrors
// the module-level Map pattern in agent-session-registry.ts, collocated here so
// the lease concern owns its own lifecycle state.

/** A lease currently held by this host. */
export interface HeldWorktreeLease {
  workspaceId: string;
  worktreeId: string;
  hostId: string;
  leaseGeneration: number;
}

// #5817 F3 — the registry is keyed PER-HANDLE (a monotonic token), NOT by
// `(workspaceId, worktreeId)`. Since Phase 3 (ADR-068 D0) `worktreeId` is PER-USER
// (`resolveWorktreeId(userId)`), so a single user's TWO lineages on ONE host
// (legacy agent-runner + cc-dispatcher, or two concurrent cc conversations for the
// same user) share the SAME `(workspaceId, worktreeId)` key and both acquire+hold a
// lease for it via migration-116's same-host carve-out (`where wl.host_id =
// excluded.host_id`, keep gen). (Two DIFFERENT users get distinct worktreeIds →
// distinct leases → routable to distinct hosts — the whole point of D0.)
// Under the old `(workspaceId, worktreeId)` key the second register OVERWROTE the
// first and the first `release()` then DELETED the shared entry out from under the
// still-live second handle — dropping the survivor from the SIGTERM drain. Keying
// per-handle makes coexisting same-workspace handles independent: each release
// removes only its own entry; the drain still covers every live handle.
export type HeldLeaseToken = number;

const heldLeases = new Map<HeldLeaseToken, HeldWorktreeLease>();
let heldLeaseSeq = 0;

/** Record a held lease (call after a successful acquire). Returns a unique token
 *  the caller passes to {@link unregisterHeldLease} so it removes ONLY its own
 *  entry — never a coexisting same-workspace handle's (F3). */
export function registerHeldLease(lease: HeldWorktreeLease): HeldLeaseToken {
  const token: HeldLeaseToken = ++heldLeaseSeq;
  heldLeases.set(token, lease);
  return token;
}

/** Drop a specific held lease from the registry by its token (call after release /
 *  on loss). No-op if already removed. */
export function unregisterHeldLease(token: HeldLeaseToken): void {
  heldLeases.delete(token);
}

/** #5817 F5 — per-release timeout for the SIGTERM drain. Without it, a single
 *  black-holed Postgres connection (release_worktree_lease never returns) could
 *  consume the whole graceful-shutdown budget before `Sentry.flush()` runs. Each
 *  release is raced against this bound; a timed-out lease simply expires at 240s
 *  and a surviving host reclaims it (the fence still guards a late write). */
export const WORKTREE_LEASE_RELEASE_TIMEOUT_MS = 2_000;

/**
 * Release every held lease — the SIGTERM drain step (server/index.ts, after the
 * cc-query drain, before server.close()). Best-effort + BOUNDED: each release is a
 * never-throwing RPC, run concurrently via allSettled AND raced against a
 * per-release timeout (F5) so one black-holed connection can't starve the 8s
 * shutdown budget. Clears the registry up front so a release that races a
 * concurrent acquire doesn't resurrect a stale entry.
 */
export async function releaseAllHeldLeases(): Promise<void> {
  const leases = [...heldLeases.values()];
  heldLeases.clear();
  await Promise.allSettled(
    leases.map((l) => {
      // Race the release against a timeout; the timer is unref'd so it never
      // itself holds the process open past exit.
      let timer: NodeJS.Timeout | undefined;
      const bounded = Promise.race([
        releaseWorktreeLease(
          l.workspaceId,
          l.worktreeId,
          l.hostId,
          l.leaseGeneration,
        ),
        new Promise<void>((resolve) => {
          timer = setTimeout(resolve, WORKTREE_LEASE_RELEASE_TIMEOUT_MS);
          timer.unref?.();
        }),
      ]);
      return bounded.finally(() => {
        if (timer) clearTimeout(timer);
      });
    }),
  );
}

// --- Session-lifetime lease handle (acquire + heartbeat + release) ----------

/** Heartbeat cadence — refresh well inside the 240s lease expiry (migration
 *  116/133). Mirrors the `touchSlot` ≤60s ping in ws-handler.ts. Raised 25s→50s
 *  (Disk-IO write reduction, 2026-07-18) in lockstep with LEASE_LIVENESS_WINDOW_MS
 *  240s so missed-beat tolerance (≈4.8 beats) is unchanged. */
export const WORKTREE_LEASE_HEARTBEAT_MS = 50_000;

/** Consecutive failed touches before declaring the lease lost. >1 so a single
 *  transient Postgres error (which `touchWorktreeLease` maps to `false`, same as
 *  a real reclaim) does not abort a valid session; 2 beats (~100s) stays well
 *  inside the 240s expiry. */
export const MAX_CONSECUTIVE_TOUCH_MISSES = 2;

/** A held lease's lifetime handle: the fencing generation to present on the
 *  git-data push, and an idempotent release that stops the heartbeat + frees
 *  the row. */
export interface WorktreeLeaseHandle {
  leaseGeneration: number;
  release(): Promise<void>;
}

/**
 * Acquire a write lease and hold it for the session lifetime: register it for
 * the SIGTERM drain and start a ≤50s heartbeat. Returns `null` when the lease is
 * held live by ANOTHER host — the caller LOST and MUST NOT write (fail-closed).
 *
 * On heartbeat loss the heartbeat stops, the registry entry is dropped, and
 * `onLost` fires exactly once — the caller aborts the in-flight write and fails
 * loud. `release()` is idempotent and is also suppressed once a loss is observed
 * (the row already belongs to the reclaimer; release_worktree_lease would no-op).
 *
 * Loss requires `MAX_CONSECUTIVE_TOUCH_MISSES` CONSECUTIVE failed touches, not
 * one: `touchWorktreeLease` maps a transient Postgres error to the same `false`
 * as a real reclaim, and a single DB blip should not abort an otherwise-valid
 * session. The 240s lease expiry affords ~4.8 missed 50s beats of slack, so two
 * consecutive misses (~100s) still declares a genuine reclaim well inside expiry
 * while tolerating one transient blip. A real reclaim returns `false` every
 * beat, so it still trips; the git-data fence is the ultimate guard against a
 * write by a host that has actually lost the row, so the slack cannot double-write.
 *
 * GATED: callers invoke this ONLY behind `isGitDataStoreEnabled()`. At
 * replicas=1 with the flag off the lease path is entirely inert (ADR-068
 * amendment) — the fence provably never rejects same-host pushes, so a live
 * lease would add a fail-closed Postgres dependency to every turn for zero
 * multi-host benefit (`hr-weigh-every-decision-against-target-user-impact`).
 */
export async function acquireAndHoldWorktreeLease(
  workspaceId: string,
  worktreeId: string,
  hostId: string,
  onLost: () => void,
): Promise<WorktreeLeaseHandle | null> {
  const lease = await acquireWorktreeLease(workspaceId, worktreeId, hostId);
  if (!lease) return null;
  const { leaseGeneration } = lease;
  const heldToken = registerHeldLease({ workspaceId, worktreeId, hostId, leaseGeneration });

  // Settled on the FIRST of {release, observed-loss}; both transitions are
  // idempotent and mutually exclusive thereafter.
  let settled = false;
  let consecutiveMisses = 0;
  const heartbeat = setInterval(() => {
    void touchWorktreeLease(
      workspaceId,
      worktreeId,
      hostId,
      leaseGeneration,
    ).then((held) => {
      if (settled) return;
      if (held) {
        consecutiveMisses = 0; // a single good beat clears a transient blip
        return;
      }
      if (++consecutiveMisses < MAX_CONSECUTIVE_TOUCH_MISSES) return;
      settled = true;
      clearInterval(heartbeat);
      unregisterHeldLease(heldToken);
      onLost();
    });
  }, WORKTREE_LEASE_HEARTBEAT_MS);
  // The heartbeat alone must never block process exit (mirror ws-handler:842).
  heartbeat.unref?.();

  return {
    leaseGeneration,
    release: async (): Promise<void> => {
      if (settled) return;
      settled = true;
      clearInterval(heartbeat);
      unregisterHeldLease(heldToken);
      await releaseWorktreeLease(workspaceId, worktreeId, hostId, leaseGeneration);
    },
  };
}

/** Test-only registry accessors (the runtime never reads these). */
export const __test_only__ = {
  heldLeaseCount: (): number => heldLeases.size,
  clearHeldLeases: (): void => heldLeases.clear(),
};
