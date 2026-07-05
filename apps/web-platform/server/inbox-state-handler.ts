/**
 * Handler for POST /api/inbox/[id]/state — the inbox_item lifecycle transition
 * (read | acted | archived). Thin route file (cq-nextjs-route-files-http-only-
 * exports) delegates here.
 *
 * Auth: caller wraps this in `withUserRateLimit` + the user-context Supabase
 * client (NEVER the service client). The `set_inbox_item_state` SECURITY DEFINER
 * RPC enforces authorization (recipient of a targeted row, or an Owner of a
 * broadcast row's workspace; missing + foreign rows collapse to 42501 — no
 * existence oracle), the archive-guard (an un-acted action_required item cannot
 * be archived), and set-once acted_at IN the DB; everything here is
 * defense-in-depth.
 *
 * `withUserRateLimit`'s wrapper does not thread Next's dynamic params, so [id]
 * is parsed from the path: /api/inbox/<id>/state → segments.at(-2).
 *
 * Responses:
 *   200 { ok: true }   transition applied
 *   400                malformed id / invalid action
 *   401 / 429          wrapper
 *   404                not found / not authorized (RPC 42501)
 *   409                archive-guard / invalid transition (RPC P0001)
 *   500                anything else (Sentry-mirrored; no PII)
 */

import { NextResponse } from "next/server";
import type { User } from "@supabase/supabase-js";
import { createClient } from "@/lib/supabase/server";
import { reportSilentFallback } from "@/server/observability";

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

const ACTIONS = ["read", "acted", "archived"] as const;
type InboxAction = (typeof ACTIONS)[number];

function isAction(v: unknown): v is InboxAction {
  return typeof v === "string" && (ACTIONS as readonly string[]).includes(v);
}

export async function inboxStateHandler(req: Request, user: User) {
  // Path shape: /api/inbox/<id>/state
  const segments = new URL(req.url).pathname.split("/").filter(Boolean);
  const id = segments.at(-2) ?? "";
  if (!UUID_PATTERN.test(id)) {
    return NextResponse.json({ error: "Invalid id" }, { status: 400 });
  }

  const body = (await req.json().catch(() => null)) as { action?: unknown } | null;
  if (!isAction(body?.action)) {
    return NextResponse.json({ error: "Invalid action" }, { status: 400 });
  }
  const action = body.action;

  const supabase = await createClient();
  const { error } = await supabase.rpc("set_inbox_item_state", {
    p_id: id,
    p_action: action,
  });

  if (error) {
    // 42501 = auth pin (missing + foreign rows collapse — 404, no oracle).
    if (error.code === "42501") {
      return NextResponse.json({ error: "Not found" }, { status: 404 });
    }
    // P0001 = archive-guard / invalid-action rejection.
    if (error.code === "P0001") {
      return NextResponse.json(
        { error: "Invalid transition" },
        { status: 409 },
      );
    }
    // No PII: ids only.
    reportSilentFallback(error, {
      feature: "inbox",
      op: "set-state",
      message: "set_inbox_item_state RPC failed",
      extra: { userId: user.id, inboxItemId: id, action },
    });
    return NextResponse.json({ error: "Internal error" }, { status: 500 });
  }

  return NextResponse.json({ ok: true });
}
