// Host-stable infra identity for the worktree write-lease (epic #5274 Phase 2,
// ADR-068 §2). The lease's host_id MUST be stable across container
// recreate-deploys (docker stop + docker run) on the SAME Hetzner host, so a
// redeploy re-acquires its own lease immediately via migration-116's acquire
// OR-carve-out (host_id = excluded.host_id) — never the 120s lockout. It is
// sourced from the Hetzner server id injected at deploy into SOLEUR_HOST_ID
// (ci-deploy.sh), NEVER the per-container hostname (a fresh random id every
// `docker run` — the forbidden per-container value, Kieran P1-2), and NEVER an
// `auth.uid()`. host_id is PURE INFRA IDENTITY: the DSAR exclusion that keeps the
// worktree_write_lease table out of Art.17 erasure is load-bearing on host_id
// never being a user id (handoff notes 1 & 4).

// auth.uid() values are UUIDs (8-4-4-4-12 hex). A host id is a Hetzner integer
// server id or a 32-hex machine-id — NEVER UUID-shaped. A UUID here means the
// value was wrongly sourced from a user id.
const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/**
 * Resolve the host-stable infra id for lease acquire/touch/release. Reads
 * `SOLEUR_HOST_ID` (the Hetzner server id injected at deploy).
 *
 * FAIL-LOUD in production when unset: silently falling back to the container
 * hostname would give every `docker run` a fresh id, so a recreate-deploy would
 * never hit the same-host carve-out and would self-lock out of its own worktree
 * for up to 120s (the exact "commit silently failing to persist" User-Brand
 * failure). In non-prod (dev/test) returns a stable sentinel so local runs don't
 * need the env — still NEVER a per-container value.
 */
export function resolveHostId(): string {
  const id = process.env.SOLEUR_HOST_ID?.trim();
  if (id) return id;
  if (process.env.NODE_ENV === "production") {
    throw new Error(
      "SOLEUR_HOST_ID is unset in production — the worktree write-lease requires " +
        "a host-stable infra id (the Hetzner server id injected at deploy). " +
        "Refusing to fall back to a per-container hostname: that would self-lock " +
        "each recreate-deploy out of its own worktree for up to 120s.",
    );
  }
  return "dev-local"; // stable non-prod sentinel; never a per-container value
}

/**
 * Guard the cross-tenant boundary at the lease call site: a host_id must NEVER
 * be a user id. Throws if `hostId` equals `userId`, or if `hostId` is UUID-shaped
 * (host ids are integer/hex, never UUIDs — a UUID means it was wrongly sourced
 * from `auth.uid()`). The DSAR exclusion (the lease table is operational state,
 * not personal data) depends on this invariant.
 */
export function assertHostIdNotUserId(hostId: string, userId: string): void {
  if (hostId === userId) {
    throw new Error(
      "host_id equals a user id — host_id must be pure infra identity, never an " +
        "auth.uid() (the lease-table DSAR exclusion is load-bearing on this).",
    );
  }
  if (UUID_RE.test(hostId)) {
    throw new Error(
      `host_id is UUID-shaped ('${hostId}') — host ids are Hetzner integer / ` +
        "machine-id hex, never a UUID; a UUID here means it was sourced from a user id.",
    );
  }
}
