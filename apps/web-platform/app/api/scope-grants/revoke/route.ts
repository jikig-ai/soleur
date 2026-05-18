// PR-G (#3947) — POST /api/scope-grants/revoke
// Founder-callable. Inlines the revoke_action_class RPC call. Sentry
// breadcrumb per TR9. Returns count of rows revoked (0 = idempotent
// no-op; > 0 = revoked).

import { NextResponse } from "next/server";
import * as Sentry from "@sentry/nextjs";
import { createClient } from "@/lib/supabase/server";
import { isKnownActionClass } from "@/server/scope-grants/action-class-map";
import { reportSilentFallback } from "@/server/observability";

export const dynamic = "force-dynamic";

interface RevokeBody {
  action_class?: unknown;
  reason?: unknown;
}

export async function POST(req: Request) {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) {
    return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  }

  let body: RevokeBody;
  try {
    body = (await req.json()) as RevokeBody;
  } catch {
    return NextResponse.json({ error: "invalid_json" }, { status: 400 });
  }

  const actionClass = body.action_class;
  const reason = body.reason;
  if (typeof actionClass !== "string" || !isKnownActionClass(actionClass)) {
    return NextResponse.json(
      { error: "invalid_action_class" },
      { status: 400 },
    );
  }
  if (typeof reason !== "string" || reason.length < 1 || reason.length > 256) {
    return NextResponse.json({ error: "invalid_reason" }, { status: 400 });
  }

  Sentry.addBreadcrumb({
    category: "scope.grant",
    message: "scope.grant.revoke_requested",
    level: "info",
    data: { action_class: actionClass, reason },
  });

  const { data, error } = await supabase.rpc("revoke_action_class", {
    p_action_class: actionClass,
    p_reason: reason,
  });

  if (error) {
    reportSilentFallback(error, {
      feature: "scope-grants",
      op: "revoke_action_class",
      message: "revoke_action_class RPC failed",
      extra: { userId: user.id, action_class: actionClass, reason },
    });
    return NextResponse.json({ error: "rpc_failed" }, { status: 500 });
  }

  Sentry.addBreadcrumb({
    category: "scope.grant",
    message: "scope.grant.revoked",
    level: "info",
    data: { action_class: actionClass, rows_revoked: data },
  });

  return NextResponse.json({ rows_revoked: data ?? 0 });
}
