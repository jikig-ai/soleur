import * as Sentry from "@sentry/nextjs";
import { createClient } from "@/lib/supabase/server";
import { decodeJwtPayloadUnsafe } from "@/lib/supabase/tenant";
import { reportSilentFallback } from "@/server/observability";
import type { SupabaseClient } from "@supabase/supabase-js";

/**
 * verifiedUserId — the middleware-verified caller identity.
 *
 * `x-soleur-auth-user-id` is minted by `apps/web-platform/middleware.ts`
 * inside the post-`getUser()` block (immediately after auth resolves, before
 * the revocation/T&C joins — every gate-failure path returns a terminal
 * redirect/403 that never forwards request headers, so a minted value only
 * reaches a handler when all gates pass). It is unconditionally deleted from
 * inbound headers before ANY response — including the /health and
 * PUBLIC_PATHS early returns — so no exit can forward a client-forged value.
 * A handler therefore only ever sees the header on a request that traversed
 * middleware — it is a trust signal, never an authorization boundary (RLS +
 * the middleware gates remain that).
 *
 * Deliberate single-control note (PR #9034 review): this function trusts
 * the header VERBATIM — no local JWT `sub` cross-check the way
 * `sessionJwtEmailForVerifiedUser` adds for the email leg. The boundary is
 * (a) the inbound strip + mint ordering above, and (b) the
 * middleware-matcher-coverage census, which walks every app/** /route.ts
 * structurally against the matcher. A matcher regression is the one
 * forgery class that would reach here — flagged as residual rather than
 * adding a getSession decode per request.
 *
 * Fail-closed fallback: an absent/empty header NEVER trusts anything — the
 * fallback re-verifies via `auth.getUser()` (direct unit-test invocation,
 * dev paths, any future matcher gap). Absent header ⇒ re-verify, never
 * trust. Returns the verified user id, or null when unauthenticated.
 */
/**
 * The narrowed identity surface a `withUserRateLimit` handler receives — only
 * the verified caller id. Handlers that need more of the Supabase `User` object
 * should declare the fields they read; none of the 12 current consumers read
 * past `user.id` (verified by consumer sweep 2026-09-25).
 */
export type VerifiedUser = { id: string };

export async function verifiedUserId(req: Request): Promise<string | null> {
  const headerUserId = req.headers.get("x-soleur-auth-user-id");
  if (headerUserId) {
    return headerUserId;
  }
  // Plan §Observability: a migrated handler seeing no verified header means
  // the request did not traverse middleware — dev mode, direct test
  // invocation, or a matcher gap. Breadcrumb-tier (not an event) so the
  // matcher/header-propagation regression is diagnosable without SSH.
  Sentry.addBreadcrumb({
    category: "middleware",
    message: "middleware.auth_header.absent",
    level: "warning",
    data: { op: "middleware.auth_header.absent" },
  });
  const supabase = await createClient();
  const data = await boundedAuthGetUser(supabase);
  // `data` is tolerated as null (a GoTrue error response yields
  // `{data: null, error}`): fail CLOSED to null, never destructure-throw.
  return data?.user?.id ?? null;
}

// Bounded remote re-verify (#8978 review): every `auth.getUser()` fallback
// leg is a remote GoTrue call — the same 20–38 s cold-stall class the
// middleware bound kills. GoTrue exposes no `.abortSignal()`, so the bound
// is a `Promise.race` identical in shape to the middleware one; a timeout
// resolves `null` so callers land on their existing fail-closed arms
// (verifiedUserId → null, resolveIdentity → ANON_IDENTITY). Read lazily so
// a test can pin a short bound via env stub.
const authGetUserTimeoutMs = () =>
  Math.max(Number(process.env.SOLEUR_AUTH_GETUSER_TIMEOUT_MS) || 10_000, 1);

// Structural minimum — the helper only calls `.auth.getUser()`, so the
// service-resolver `AuthClient` shapes (narrower than SupabaseClient, e.g.
// `error: unknown`) are accepted without a cast or signature changes.
export type BoundedAuthUser = { id: string; email?: string | null };

export async function boundedAuthGetUser<U extends BoundedAuthUser>(supabase: {
  auth: {
    getUser: () => Promise<{ data: { user: U | null }; error: unknown }>;
  };
}): Promise<{ user: U | null } | null> {
  let timer: ReturnType<typeof setTimeout> | undefined;
  const result = await Promise.race([
    // A REJECTING getUser is also a remote leg failing — collapse it to the
    // same null arm as the timeout so route handlers 401 rather than 500.
    supabase.auth
      .getUser()
      .then((r) => r.data)
      .catch(() => null),
    new Promise<null>((resolve) => {
      timer = setTimeout(() => resolve(null), authGetUserTimeoutMs());
    }),
  ]);
  clearTimeout(timer);
  if (result === null) {
    // Distinct from "getUser returned null": a bounded-wait timeout or a
    // rejecting leg means the AUTH SERVER stalled — mirror it so an
    // upstream stall pattern is visible without SSH (same class as the
    // middleware's mw_auth.timeout op).
    Sentry.addBreadcrumb({
      category: "middleware",
      message: "auth.getuser.bounded_timeout",
      level: "warning",
      data: { op: "auth.getuser.bounded_timeout" },
    });
  }
  return result;
}

// Same bound for getSession(): on an EXPIRED token `__loadSession()`
// performs a remote `/auth/v1/token` refresh inside the call — "local"
// only on the warm path. Returns the session `data` shape or null on
// timeout/reject so callers land on their existing fail-closed arms.
export async function boundedAuthGetSession<S = unknown>(supabase: {
  auth: {
    getSession: () => Promise<{ data: { session: S | null }; error: unknown }>;
  };
}): Promise<{ session: S | null } | null> {
  let timer: ReturnType<typeof setTimeout> | undefined;
  const result = await Promise.race([
    supabase.auth
      .getSession()
      .then((r) => r.data)
      .catch(() => null),
    new Promise<null>((resolve) => {
      timer = setTimeout(() => resolve(null), authGetUserTimeoutMs());
    }),
  ]);
  clearTimeout(timer);
  if (result === null) {
    Sentry.addBreadcrumb({
      category: "middleware",
      message: "auth.getsession.bounded_timeout",
      level: "warning",
      data: { op: "auth.getsession.bounded_timeout" },
    });
  }
  return result;
}

/**
 * sessionJwtEmailForVerifiedUser — read the caller's email from the LOCAL
 * session JWT (cookie decode via `getSession()` — no auth-server RTT on the
 * warm path; an expired token triggers a bounded remote refresh inside the
 * call), but ONLY when the token's own `sub` claim agrees with the
 * already-verified user id the caller holds.
 *
 * The sub cross-check is the load-bearing part (PR #8984 review): a
 * header-minted id and a session cookie can diverge across rotation races,
 * and without the agreement check an `invitee_email`-keyed service-role
 * query (pending-invites) could serve another account's rows. An absent
 * session, malformed token, mismatched sub, or missing/empty email claim
 * all return null — callers re-verify remotely, never trust the claim.
 */
export async function sessionJwtEmailForVerifiedUser(
  supabase: SupabaseClient,
  userId: string,
): Promise<string | null> {
  // getSession() can throw (storage lock timeout, corrupt cookie chunk) —
  // any throw or gap returns null so the caller re-verifies remotely rather
  // than crashing the render/handler (PR #8984 review). On an EXPIRED token
  // it also performs a remote `/auth/v1/token` refresh inside the call —
  // "local" only on the warm path — so it carries the same bound as every
  // other auth-server leg (cq-silent-fallback mirrors the timeout arm).
  let accessToken: string | undefined;
  let sessionTimer: ReturnType<typeof setTimeout> | undefined;
  try {
    const sessionData = await Promise.race([
      supabase.auth
        .getSession()
        .then((r) => r.data)
        .catch(() => null),
      new Promise<null>((resolve) => {
        sessionTimer = setTimeout(
          () => resolve(null),
          authGetUserTimeoutMs(),
        );
      }),
    ]);
    clearTimeout(sessionTimer);
    accessToken = sessionData?.session?.access_token;
    if (sessionData === null) {
      reportSilentFallback(null, {
        feature: "request-auth",
        op: "session-jwt-email.session_timeout",
        message: "getSession() remote-refresh leg exceeded the bound in email fast path",
      });
    }
  } catch {
    return null;
  }
  if (!accessToken) return null;
  try {
    const payload = decodeJwtPayloadUnsafe(accessToken);
    if (
      payload.sub === userId &&
      typeof payload.email === "string" &&
      payload.email !== ""
    ) {
      return payload.email;
    }
  } catch {
    // Malformed session JWT — mirrored (cq-silent-fallback): cookie
    // corruption is worth seeing, and the caller still re-verifies remotely.
    reportSilentFallback(null, {
      feature: "request-auth",
      op: "session-jwt-email.malformed-token",
      message: "session JWT undecodable in email fast path",
    });
  }
  return null;
}
