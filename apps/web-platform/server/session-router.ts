// session-router.ts — co-located, stateless user-sticky session router (epic
// #5274 Phase 3 Sub-PR 3.B, ADR-068 D0 amendment 2026-07-01).
//
// Under user-sticky routing each USER of a workspace owns a per-user worktree
// write-lease (`resolveWorktreeId(userId)`); the host holding that lease is the
// host that serves that user's sessions. This module is the placement DECISION:
// given an inbound WS for (workspaceId, userId), it reads the live lease holder
// and returns local-serve / proxy-to-owner / owner-unresolved. It carries NO
// state and forwards NO control ops — a conversation's abort/gate/grace resolve
// LOCALLY on the owning host precisely because every frame for it routes there by
// this same sticky decision.
//
// PLACEMENT HOOK POINT (ADR-068 amendment 2026-07-01, CTO ruling — b2): the
// decision is taken at FIRST-MESSAGE AUTH (the earliest point `userId` exists
// under our first-message-auth model), before `auth_ok` and before any session
// bootstrap — NOT at the raw TCP `upgrade` event (where no token/userId exists).
// A peer-owned session is then TRANSPARENTLY PROXIED to the owner over one-way
// TLS with NO client-visible reconnect. The preserved fly-replay invariant is
// "never upgrade-then-REDIRECT" (no client reconnect/blip) — not "decide before
// the TCP upgrade", which is impossible under first-message auth and unnecessary
// (a transparent socket relay preserves stream continuity). Gated on
// isGitDataStoreEnabled() at the call site → entirely inert (no per-connection DB
// read) until the 3.D cutover.
//
// The proxy transport is one-way TLS over the private net (proxy-tls.ts); the
// owning host re-verifies membership before serving a proxied session (AP-2).

import { reportSilentFallback } from "./observability";
import { readWorktreeLeaseHolder, resolveWorktreeId } from "./worktree-write-lease";

/** Minimal structural supabase shape for the membership re-verify (mirrors
 *  workspace-resolver's SupabaseLike). */
interface SupabaseLike {
  from: (table: string) => unknown;
}

/**
 * Where an inbound session is served:
 *   - `local` — this host owns the user's lease (or the session is cold and this
 *     host will acquire it on write, becoming owner);
 *   - `proxy` — a PEER host owns it; dial `ownerAddress` over one-way TLS;
 *   - `owner-unresolved` — a peer owns it but its address is not in the roster
 *     (misconfig / a host not yet enrolled) — fail-loud, do not guess.
 */
export type SessionRouteDecision =
  | { decision: "local"; reason: "owner" | "cold" }
  | { decision: "proxy"; ownerHostId: string; ownerAddress: string }
  | { decision: "owner-unresolved"; ownerHostId: string };

/**
 * Parse the host roster `SOLEUR_HOST_ROSTER` — a JSON object mapping a stable
 * `host_id` (the lease's placement authority, = SOLEUR_HOST_ID) to that host's
 * private-net address the proxy dials. Empty/unset/invalid → `{}` (single-host:
 * a peer is never resolvable, so a stray remote holder yields `owner-unresolved`
 * rather than a wrong dial). Fail-safe: never throws.
 */
export function loadHostRoster(): Record<string, string> {
  const raw = process.env.SOLEUR_HOST_ROSTER?.trim();
  if (!raw) return {};
  try {
    const parsed = JSON.parse(raw) as unknown;
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) return {};
    const out: Record<string, string> = {};
    for (const [k, v] of Object.entries(parsed as Record<string, unknown>)) {
      if (typeof v === "string" && v.length > 0) out[k] = v;
    }
    return out;
  } catch {
    return {};
  }
}

/** Resolve an owning `host_id` to its private-net address, or `null` when the
 *  host is not in the roster. */
export function resolveHostAddress(hostId: string): string | null {
  return loadHostRoster()[hostId] ?? null;
}

/**
 * Decide where the session for `(workspaceId, userId)` is served, from the LIVE
 * per-user worktree lease holder. Read-only (no acquire) so the router never
 * steals the lease. Deterministic per `(workspaceId, userId)` given a stable
 * holder → sticky, so control ops resolve on the owning host without forwarding.
 */
export async function resolveSessionRoute(params: {
  workspaceId: string;
  userId: string;
  myHostId: string;
}): Promise<SessionRouteDecision> {
  const { workspaceId, userId, myHostId } = params;
  const worktreeId = resolveWorktreeId(userId);
  const holder = await readWorktreeLeaseHolder(workspaceId, worktreeId);

  // Cold: no live owner → serve here; the write path acquires the lease and this
  // host becomes the owner (fence-safe: acquireWorktreeLease is fail-closed if a
  // peer actually holds it live).
  if (!holder) return { decision: "local", reason: "cold" };

  // We own it → serve locally.
  if (holder.hostId === myHostId) return { decision: "local", reason: "owner" };

  // A peer owns it → proxy to its private address if the roster resolves it.
  const ownerAddress = resolveHostAddress(holder.hostId);
  if (!ownerAddress) {
    reportSilentFallback(
      new Error(
        `session-router: owning host '${holder.hostId}' is not in SOLEUR_HOST_ROSTER — ` +
          `cannot proxy the session (owner-unresolved)`,
      ),
      {
        feature: "control_plane_route",
        op: "resolveSessionRoute.owner-unresolved",
        extra: { workspaceId, ownerHostId: holder.hostId, myHostId },
      },
    );
    return { decision: "owner-unresolved", ownerHostId: holder.hostId };
  }
  return { decision: "proxy", ownerHostId: holder.hostId, ownerAddress };
}

/**
 * AP-2 (CLO): the OWNING host re-verifies that `userId` is a member of
 * `workspaceId` before serving a session PROXIED from a peer host. The proxy
 * carries user identity across the private net, so the owner must not trust it
 * blind — a compromised/buggy peer or a stale route could present a cross-tenant
 * `(userId, workspaceId)` pair. Fail-CLOSED: any DB error → deny.
 *
 * Solo shortcut: per the N2 invariant a user is always a member of their own solo
 * workspace (`workspace_id === userId`), so no query is issued (mirrors the
 * resolveActiveWorkspace solo shortcut). Service-role read at the call site
 * (authoritative membership, bypasses RLS); the `.eq("user_id", userId)` self-
 * scopes the probe regardless.
 */
export async function verifyProxiedSessionMembership(
  userId: string,
  workspaceId: string,
  supabase: SupabaseLike,
): Promise<boolean> {
  if (workspaceId === userId) return true; // N2 solo — always a member of own ws

  type ChainShape = {
    select: (cols: string) => ChainShape;
    eq: (col: string, val: string) => ChainShape;
    maybeSingle: () => ChainShape;
  } & PromiseLike<{ data: { user_id: string } | null; error: unknown }>;

  const chain = supabase.from("workspace_members") as ChainShape;
  const { data, error } = await (chain
    .select("user_id")
    .eq("workspace_id", workspaceId)
    .eq("user_id", userId)
    .maybeSingle() as PromiseLike<{ data: { user_id: string } | null; error: unknown }>);

  if (error) {
    reportSilentFallback(error, {
      feature: "control_plane_route",
      op: "verifyProxiedSessionMembership",
      extra: { userId, workspaceId },
    });
    return false; // fail-closed — never serve a session we cannot authorize
  }
  return data != null;
}
