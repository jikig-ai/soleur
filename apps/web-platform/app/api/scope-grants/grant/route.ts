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
import { validateOrigin, rejectCsrf } from "@/lib/auth/validate-origin";
import {
  isKnownActionClass,
  type ActionClassTier,
} from "@/server/scope-grants/action-class-map";
import { reportSilentFallback } from "@/server/observability";
import { emitWorkspaceActionContext } from "@/server/workspace-action-audit";

export const dynamic = "force-dynamic";

// PR-H (#4077): admits the 4th tier value alongside the original 3.
// grant_action_class RPC in mig 051 also accepts auto_with_digest.
const VALID_TIERS: ReadonlySet<ActionClassTier> = new Set([
  "auto",
  "draft_one_click",
  "approve_every_time",
  "auto_with_digest",
]);

interface GrantBody {
  action_class?: unknown;
  tier?: unknown;
}

export async function POST(req: Request) {
  const { valid, origin } = validateOrigin(req);
  if (!valid) return rejectCsrf("api/scope-grants/grant", origin);

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

  // AC11: record the workspace this grant actually landed in at commit time
  // (wrong-workspace detector). grant_action_class (migration 063) scopes the
  // grant UNCONDITIONALLY to the founder's SOLO workspace (workspace_id =
  // auth.uid()); multi-workspace scope-grants are deferred to #4342. So the
  // audited tenant is the solo workspace = user.id — NOT the session's active
  // workspace (resolveCurrentWorkspaceId would diverge after a workspace
  // switch and make the detector log a tenant the grant never touched).
  emitWorkspaceActionContext({
    action: "scope-grant",
    userId: user.id,
    workspaceId: user.id,
  });

  return NextResponse.json({ id: data, action_class: actionClass, tier });
}
