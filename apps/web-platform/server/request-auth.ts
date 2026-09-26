import * as Sentry from "@sentry/nextjs";
import { createClient } from "@/lib/supabase/server";

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
  const {
    data: { user },
  } = await supabase.auth.getUser();
  return user?.id ?? null;
}
