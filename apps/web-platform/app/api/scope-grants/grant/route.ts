// PR-G (#3947) — POST /api/scope-grants/grant
// Founder-callable. Inlines the grant_action_class RPC call per Code
// Simplicity review (no separate wrapper module). Sentry breadcrumb on
// success/failure per TR9.
//
// Per cq-nextjs-route-files-http-only-exports: this file exports only
// HTTP verbs + dynamic config. No helper functions.

import { NextResponse } from "next/server";
import * as Sentry from "@sentry/nextjs";
import { createClient } from "@/lib/supabase/server";
import {
  isKnownActionClass,
  type ActionClassTier,
} from "@/server/scope-grants/action-class-map";
import { reportSilentFallback } from "@/server/observability";

export const dynamic = "force-dynamic";

const VALID_TIERS: ReadonlySet<ActionClassTier> = new Set([
  "auto",
  "draft_one_click",
  "approve_every_time",
]);

interface GrantBody {
  action_class?: unknown;
  tier?: unknown;
}

export async function POST(req: Request) {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) {
    return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  }

  let body: GrantBody;
  try {
    body = (await req.json()) as GrantBody;
  } catch {
    return NextResponse.json({ error: "invalid_json" }, { status: 400 });
  }

  const actionClass = body.action_class;
  const tier = body.tier;
  if (typeof actionClass !== "string" || !isKnownActionClass(actionClass)) {
    return NextResponse.json(
      { error: "invalid_action_class" },
      { status: 400 },
    );
  }
  if (typeof tier !== "string" || !VALID_TIERS.has(tier as ActionClassTier)) {
    return NextResponse.json({ error: "invalid_tier" }, { status: 400 });
  }

  Sentry.addBreadcrumb({
    category: "scope.grant",
    message: "scope.grant.requested",
    level: "info",
    data: { action_class: actionClass, tier },
  });

  const { data, error } = await supabase.rpc("grant_action_class", {
    p_action_class: actionClass,
    p_tier: tier,
  });

  if (error) {
    reportSilentFallback(error, {
      feature: "scope-grants",
      op: "grant_action_class",
      message: "grant_action_class RPC failed",
      extra: { userId: user.id, action_class: actionClass, tier },
    });
    return NextResponse.json({ error: "rpc_failed" }, { status: 500 });
  }

  Sentry.addBreadcrumb({
    category: "scope.grant",
    message: "scope.grant.created",
    level: "info",
    data: { action_class: actionClass, tier, grant_id: data },
  });

  return NextResponse.json({ id: data, action_class: actionClass, tier });
}
