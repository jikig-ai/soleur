// PR-B (#4379) AC15 — GET /api/dashboard/today/[id]/cost
//
// Returns cumulative spend for the per-spawn loop scoped to a single
// `action_sends` row. The Today card polls or subscribes to the row
// and hits this endpoint after each progress UPDATE to refresh the
// "Cost: $X.XX (N turns)" badge.
//
// Query: `audit_byok_use` rows joined on
//   agent_role = "agent.spawn.requested:<actionClass>"
//   founder_id = caller user id
//   created_at ∈ (action_sends.created_at, action_sends.acknowledged_at OR now()]
//
// `audit_byok_use` has no native `action_send_id` FK (Non-Goal #15);
// the time-window join + `agent_role` predicate is the linkage. Pre-
// compute `agent_role` in TS rather than concatenating server-side to
// keep the index on (founder_id, agent_role, created_at) usable.
//
// Auth model: tenant-side messages owner-check (same as cancel/undo);
// service-role read of `audit_byok_use` because the table has no
// permissive owner-SELECT policy at the tenant client (the existing
// dashboard audit page uses service-role for the same reason).
//
// Per cq-nextjs-route-files-http-only-exports: only HTTP exports +
// dynamic.

import { NextResponse } from "next/server";

import { createClient } from "@/lib/supabase/server";
import { getServiceClient } from "@/lib/supabase/service";
import { validateOrigin, rejectCsrf } from "@/lib/auth/validate-origin";
import { reportSilentFallback } from "@/server/observability";

export const dynamic = "force-dynamic";

interface ActionSendRow {
  id: string;
  message_id: string;
  user_id: string;
  action_class: string;
  created_at: string;
  acknowledged_at: string | null;
}

export async function GET(
  req: Request,
  { params }: { params: Promise<{ id: string }> },
) {
  const { valid, origin } = validateOrigin(req);
  if (!valid) return rejectCsrf("api/dashboard/today/[id]/cost", origin);

  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) {
    return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  }

  const { id: messageId } = await params;

  const { data: msgRow, error: msgErr } = await supabase
    .from("messages")
    .select("id")
    .eq("id", messageId)
    .eq("user_id", user.id)
    .maybeSingle();
  if (msgErr) {
    reportSilentFallback(msgErr, {
      feature: "dashboard-cost",
      op: "messages-owner-check",
      message: "messages select failed during cost lookup",
      extra: { userId: user.id, messageId },
    });
    return NextResponse.json({ error: "internal_error" }, { status: 500 });
  }
  if (!msgRow) {
    return NextResponse.json({ error: "forbidden" }, { status: 403 });
  }

  const service = getServiceClient();
  // Service-role read on `action_sends` because the WORM-row tenant-RLS
  // SELECT does not extend to all columns we need (action_class +
  // created_at + acknowledged_at). The tenant-side messages check above
  // already proved ownership; this read is bounded to one row by id.
  const { data: rawSend, error: sendErr } = await service
    .from("action_sends")
    .select("id,message_id,user_id,action_class,created_at,acknowledged_at")
    .eq("message_id", messageId)
    .maybeSingle();
  if (sendErr || !rawSend) {
    if (sendErr) {
      reportSilentFallback(sendErr, {
        feature: "dashboard-cost",
        op: "action-sends-read",
        message: "action_sends select failed during cost lookup",
        extra: { userId: user.id, messageId },
      });
    }
    return NextResponse.json({ cumulativeCents: 0, turnCount: 0 });
  }
  const send = rawSend as ActionSendRow;
  if (send.user_id !== user.id) {
    // Defense in depth — should be unreachable given the messages owner-
    // check, but a misconfigured RLS migration could let it through.
    return NextResponse.json({ error: "forbidden" }, { status: 403 });
  }

  const agentRole = `agent.spawn.requested:${send.action_class}`;
  const upper = send.acknowledged_at ?? new Date().toISOString();

  const { data: auditRows, error: auditErr } = await service
    .from("audit_byok_use")
    .select("unit_cost_cents")
    .eq("agent_role", agentRole)
    .eq("founder_id", user.id)
    .gt("created_at", send.created_at)
    .lte("created_at", upper);
  if (auditErr) {
    reportSilentFallback(auditErr, {
      feature: "dashboard-cost",
      op: "audit-byok-use-sum",
      message: "audit_byok_use sum failed",
      extra: { userId: user.id, messageId, agentRole },
    });
    return NextResponse.json({ error: "internal_error" }, { status: 500 });
  }

  const rows = (auditRows ?? []) as { unit_cost_cents: number | null }[];
  const cumulativeCents = rows.reduce(
    (sum, r) => sum + (r.unit_cost_cents ?? 0),
    0,
  );
  return NextResponse.json({
    cumulativeCents,
    turnCount: rows.length,
  });
}
