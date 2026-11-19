// Host-stable infra identity for the worktree write-lease (epic #5274 Phase 2,
// ADR-068 §2, amended 2026-11-18 for #12910).
//
// The lease's host_id is the host's `var.web_hosts` key (`web-1`, `web-2`),
// injected at deploy as SOLEUR_HOST_KEY (ci-deploy.sh, derived from the Hetzner
// metadata hostname) and accepted ONLY when SOLEUR_HOST_ROSTER maps that key to
// this container's own SOLEUR_HOST_PRIVATE_IP (CTO ruling T1). That makes it the
// same string the session router looks up in the roster, and it is stable across
// recreate-deploys AND host replaces (the Hetzner instance id is not: it changes
// on every replace, which is how #12910 split the roster key from the lease id).
//
// Uniqueness: two live hosts cannot share a private IP, so a wrong hostname, a
// wrong roster or a mis-set env can only ever degrade to SOLEUR_HOST_ID (the
// `hetzner-<instance id>` telemetry id, today's behaviour), never to a key a
// peer also holds. Migration 116 hands a LIVE lease to a caller with the same
// host_id at the same generation, which is why the key is verified, not trusted.
// A replaced host re-acquires its predecessor's leases at the same generation;
// that is safe only because hcloud_server.web has no create_before_destroy
// (pinned by web-hosts-generic.test.sh C8), so the two never overlap.
//
// NEVER the per-container hostname (a fresh random id every `docker run`, Kieran
// P1-2), and NEVER an `auth.uid()`. host_id is PURE INFRA IDENTITY: the DSAR
// exclusion that keeps the worktree_write_lease table out of Art.17 erasure is
// load-bearing on host_id never being a user id (handoff notes 1 & 4).
//
// Imports only the env-only leaves host-roster.ts and host-private-ip.ts: no
// Sentry, no request-path dependency tree.

import { loadHostRoster } from "./host-roster";
import { readHostPrivateIp } from "./host-private-ip";

// auth.uid() values are UUIDs (8-4-4-4-12 hex). A host id is `hetzner-<n>`,
// `machine-<12 hex>` (ci-deploy.sh resolve_host_id) or a `var.web_hosts` key
// (`web-1`, at most 31 chars from a leading letter) — NEVER UUID-shaped. A UUID
// here means the value was wrongly sourced from a user id.
const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** The `var.web_hosts` key shape, byte-identical to the serve gate's
 *  `TOP_gated_host_malformed` regex (pinned by web-hosts-generic.test.sh C8).
 *  It also matches `hetzner-176328334`: only the roster check rejects an
 *  instance-id key, so never "simplify" the verification down to this regex. */
export const HOST_KEY_RE = /^[a-z][a-z0-9-]{0,30}$/;

export type HostIdentitySource =
  | "web-host-key"
  | "key-absent"
  | "key-malformed"
  | "key-unverified"
  | "dev-sentinel";

export interface HostIdentity {
  id: string;
  source: HostIdentitySource;
}

/**
 * Resolve this host's lease placement id and say where it came from. Pure:
 * reads only `env`. `source` is a closed enum safe to log (it never carries the
 * id or an address).
 *
 * `web-host-key` when SOLEUR_HOST_KEY is well-formed AND the roster maps it to
 * this container's private IP. Every other source falls back to SOLEUR_HOST_ID.
 * When that is empty too, production FAILS LOUD: silently falling back to the
 * container hostname would give every `docker run` a fresh id, so a
 * recreate-deploy would never hit the same-host carve-out and would self-lock
 * out of its own worktree for up to 240s. Non-prod returns a stable sentinel.
 */
export function describeHostIdentity(
  env: NodeJS.ProcessEnv = process.env,
): HostIdentity {
  const { key, source } = classifyHostKey(env);
  if (source === "web-host-key") return { id: key, source };
  const id = env.SOLEUR_HOST_ID?.trim();
  if (id) return { id, source };
  if (env.NODE_ENV === "production") {
    throw new Error(
      "SOLEUR_HOST_ID is unset in production — the worktree write-lease requires " +
        "a host-stable infra id (the Hetzner server id injected at deploy). " +
        "Refusing to fall back to a per-container hostname: that would self-lock " +
        "each recreate-deploy out of its own worktree for up to 240s.",
    );
  }
  return { id: "dev-local", source: "dev-sentinel" }; // never a per-container value
}

/** The key half of the rules: whether SOLEUR_HOST_KEY verifies. Never throws. */
function classifyHostKey(env: NodeJS.ProcessEnv): {
  key: string;
  source: Exclude<HostIdentitySource, "dev-sentinel">;
} {
  const key = env.SOLEUR_HOST_KEY?.trim() ?? "";
  if (!key) return { key, source: "key-absent" };
  if (!HOST_KEY_RE.test(key)) return { key, source: "key-malformed" };
  const ip = readHostPrivateIp(env.SOLEUR_HOST_PRIVATE_IP);
  if (ip === null || loadHostRoster(env)[key] !== ip) {
    return { key, source: "key-unverified" };
  }
  return { key, source: "web-host-key" };
}

/** What the boot line reports: the identity source, or `unresolved` when
 *  `resolveHostId()` will throw at lease time (production, no verified key and no
 *  SOLEUR_HOST_ID: the cloud-init first-boot container, until its first ci-deploy). */
export type HostIdentityBootSource = HostIdentitySource | "unresolved";

export interface HostIdentityBootReport {
  source: HostIdentityBootSource;
  /** Closed grammar, enums only, never the id or an address. */
  line: string;
  /** Send the production Sentry fallback event. */
  reportFallback: boolean;
}

/**
 * The boot-time identity report (#12910). Pure: reads only `env`.
 *
 * `reportFallback` is keyed on SOLEUR_PROXY_BIND === "0.0.0.0", a literal only the
 * ci-deploy.sh PROD `docker run` sets (the canary sets it empty, the cloud-init
 * first-boot run does not set it). It deliberately does NOT depend on the identity
 * inputs: a prod host whose private NIC was late at deploy gets an EMPTY
 * SOLEUR_HOST_PRIVATE_IP, falls back off its key, and must still report — that is
 * the #12910 incident shape, not the canary.
 */
export function hostIdentityBootReport(
  env: NodeJS.ProcessEnv = process.env,
): HostIdentityBootReport {
  let source: HostIdentityBootSource;
  let line: string;
  try {
    source = describeHostIdentity(env).source;
    line = `host_identity source=${source}`;
  } catch {
    source = "unresolved";
    line = `host_identity source=unresolved key=${classifyHostKey(env).source}`;
  }
  const reportFallback =
    env.NODE_ENV === "production" &&
    env.SOLEUR_PROXY_BIND?.trim() === "0.0.0.0" &&
    source !== "web-host-key";
  return { source, line, reportFallback };
}

/**
 * The host-stable infra id for lease acquire/touch/release and the router's
 * `myHostId`. See `describeHostIdentity` for the rules.
 */
export function resolveHostId(): string {
  return describeHostIdentity().id;
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
