// PR-B (#4379) AC13 — POST /api/dashboard/today/[id]/cancel
//
// Operator clicked "Stop" on a Today card. UPDATEs
// `action_sends.cancellation_requested_at = now()` for the row owned by
// the message identified by the dynamic [id] param.
//
// Auth model:
//   1. Origin / CSRF gate at the route boundary.
//   2. Supabase tenant client auth.getUser() — cookie-scoped.
//   3. `messages` SELECT with `user_id = caller.id` join to confirm the
//      caller owns this message (and therefore owns its action_sends
//      row through the FK). This is the load-bearing tenant gate per
//      `cq-pg-security-definer-search-path-pin-pg-temp` advisory — the
//      `messages` table has owner-SELECT RLS so a tenant-scoped read
//      that returns the row IS proof the caller owns it.
//   4. Service-role UPDATE on `action_sends.cancellation_requested_at`
//      — `action_sends` UPDATE has no permissive RLS policy, so the
//      tenant client can't write directly; the service-role bypass is
//      bounded by the tenant-side ownership check above.
//
// Idempotency: a second cancel click on the same row is a no-op (the
// UPDATE writes the same `now()` over the existing timestamp; the
// Inngest function's cancel-check reads any non-NULL value and short-
// circuits regardless). The response is always 200 for an owned row.
//
// Per cq-nextjs-route-files-http-only-exports: only HTTP exports +
// dynamic.

import { NextResponse } from "next/server";

import { createClient } from "@/lib/supabase/server";
import { getServiceClient } from "@/lib/supabase/service";
import { validateOrigin, rejectCsrf } from "@/lib/auth/validate-origin";
import { reportSilentFallback } from "@/server/observability";

export const dynamic = "force-dynamic";

export async function POST(
  req: Request,
  { params }: { params: Promise<{ id: string }> },
) {
  const { valid, origin } = validateOrigin(req);
  if (!valid) return rejectCsrf("api/dashboard/today/[id]/cancel", origin);

  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) {
    return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  }

  const { id: messageId } = await params;

  // Tenant-side ownership check via `messages` (owner-SELECT RLS). A
  // null `data` means either the row does not exist OR the caller does
  // not own it — both collapse to 403 here.
  const { data: msgRow, error: msgErr } = await supabase
    .from("messages")
    .select("id")
    .eq("id", messageId)
    .eq("user_id", user.id)
    .maybeSingle();
  if (msgErr) {
    reportSilentFallback(msgErr, {
      feature: "dashboard-cancel",
      op: "messages-owner-check",
      message: "messages select failed during cancel",
      extra: { userId: user.id, messageId },
    });
    return NextResponse.json({ error: "internal_error" }, { status: 500 });
  }
  if (!msgRow) {
    return NextResponse.json({ error: "forbidden" }, { status: 403 });
  }

  // Service-role UPDATE on `action_sends.cancellation_requested_at`.
  // The WORM trigger (mig 064) admits this column by default (BEFORE
  // UPDATE OF lists only the pre-064 immutable columns). The UPDATE is
  // scoped by `message_id` so a stray writer can't hit a sibling row.
  const service = getServiceClient();
  const { error: updErr } = await service
    .from("action_sends")
    .update({ cancellation_requested_at: new Date().toISOString() })
    .eq("message_id", messageId);
  if (updErr) {
    reportSilentFallback(updErr, {
      feature: "dashboard-cancel",
      op: "action-sends-cancel-write",
      message: "action_sends cancel UPDATE failed",
      extra: { userId: user.id, messageId },
    });
    return NextResponse.json({ error: "internal_error" }, { status: 500 });
  }

  return NextResponse.json({ ok: true });
}
