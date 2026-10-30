// PR-H (#4077) — POST /api/dashboard/today/[id]/discard
//
// Archives a draft message owned by the caller (status: draft → archived).
// No action_sends row is written — discard is a no-op outbound. It is refused once an
// approval row exists (409 draft_already_approved, same lookup as /edit): the approved
// send may still run, so archiving the card would show "discarded" while it goes out.
// Send resolves that state (it replays the approval and archives). A failed approval
// lookup fails closed (500).
//
// Per cq-nextjs-route-files-http-only-exports: only HTTP exports + dynamic.

import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { validateOrigin, rejectCsrf } from "@/lib/auth/validate-origin";
import { reportSilentFallback } from "@/server/observability";
import { verifiedUserId } from "@/server/request-auth";

export const dynamic = "force-dynamic";

export async function POST(
  req: Request,
  { params }: { params: Promise<{ id: string }> },
) {
  const { valid, origin } = validateOrigin(req);
  if (!valid) return rejectCsrf("api/dashboard/today/[id]/discard", origin);

  const supabase = await createClient();
  const userId = await verifiedUserId(req);
  if (!userId) {
    return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  }

  const { id: messageId } = await params;

  const { data: approval, error: approvalErr } = await supabase
    .from("action_sends")
    .select("id")
    .eq("message_id", messageId)
    .eq("user_id", userId)
    .maybeSingle();
  if (approvalErr) {
    reportSilentFallback(approvalErr, {
      feature: "dashboard-discard",
      op: "action-sends-lookup",
      message: "Failed to check for an existing approval before discard",
      extra: { userId, messageId },
    });
    return NextResponse.json({ error: "internal_error" }, { status: 500 });
  }
  if (approval) {
    return NextResponse.json(
      { error: "draft_already_approved", message_id: messageId },
      { status: 409 },
    );
  }

  // Belt-and-suspenders alongside RLS.
  const { data, error } = await supabase
    .from("messages")
    .update({ status: "archived" })
    .eq("id", messageId)
    .eq("user_id", userId)
    .eq("status", "draft")
    .select("id")
    .maybeSingle();

  if (error) {
    reportSilentFallback(error, {
      feature: "dashboard-discard",
      op: "messages-archive",
      message: "Failed to archive draft",
      extra: { userId, messageId },
    });
    return NextResponse.json({ error: "internal_error" }, { status: 500 });
  }
  if (!data) {
    return NextResponse.json({ error: "forbidden" }, { status: 403 });
  }

  return NextResponse.json({ id: data.id, status: "archived" });
}
