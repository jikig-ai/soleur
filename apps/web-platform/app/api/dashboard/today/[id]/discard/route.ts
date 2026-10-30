// PR-H (#4077) — POST /api/dashboard/today/[id]/discard
//
// Archives a draft message owned by the caller (status: draft → archived).
// No action_sends row is written — discard is a no-op outbound. It is refused once an
// approval row exists (409 draft_already_approved, same lookup as /edit): the approved
// send may still run, so archiving the card would show "discarded" while it goes out.
// Send resolves the terminal / no_artifact / expired replay arms; a revoked grant or template, clock_skew and
// draft_changed_since_approval stay a bounded, recoverable residual (Stripe drafts only, D21). The 409 is given
// only while the message is still a draft; an already-archived one answers the zero-row 403. A failed approval
// lookup fails closed (500). After a successful archive the approval is re-read once: a hit means a Send raced this
// Discard and is reported to Sentry (op discard-send-race) without changing the 200.
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
    // 409 only while the draft is still a draft. If it was already archived (another tab sent it), the honest answer is the
    // zero-row 403 the card already handles by refreshing; Send would answer not_a_draft.
    const { data: current, error: currentErr } = await supabase
      .from("messages")
      .select("status")
      .eq("id", messageId)
      .eq("user_id", userId)
      .maybeSingle();
    if (currentErr) {
      reportSilentFallback(currentErr, {
        feature: "dashboard-discard",
        op: "messages-status-lookup",
        message: "Failed to read the draft status after finding an approval",
        extra: { userId, messageId },
      });
      return NextResponse.json({ error: "internal_error" }, { status: 500 });
    }
    if (!current || current.status !== "draft") {
      return NextResponse.json({ error: "forbidden" }, { status: 403 });
    }
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

  // Detector for the one race this route cannot close (accepted residual, D21): a Send in another tab wrote its approval
  // between the lookup above and the archive. Report it so the "flip to a DB trigger on a repro" condition can be observed.
  const { data: raced, error: racedErr } = await supabase
    .from("action_sends")
    .select("id")
    .eq("message_id", messageId)
    .eq("user_id", userId)
    .maybeSingle();
  if (racedErr || raced) {
    reportSilentFallback(racedErr ?? new Error("approval appeared while the draft was being discarded"), {
      feature: "dashboard-discard",
      op: "discard-send-race",
      message: racedErr
        ? "Post-archive approval recheck failed"
        : "A draft was discarded while an approval row was written",
      extra: { userId, messageId },
    });
  }

  return NextResponse.json({ id: data.id, status: "archived" });
}
