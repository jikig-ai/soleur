// PR-F (#3244, #3940) Phase 5 — server-side data loader for the
// dashboard Today section.
//
// Returns the caller's draft messages filtered to:
//   tier   = "external_brand_critical"
//   status = "draft"
//
// Uses createClient() (cookie-scoped, RLS-enforced) so a malformed query
// CANNOT leak cross-founder rows. Belt-and-suspenders: an explicit
// .eq("user_id", user.id) filter alongside the table-level RLS so the
// query short-circuits at PostgREST even if RLS were ever loosened.
//
// Per cq-nextjs-route-files-http-only-exports — only HTTP method handlers
// are exported. RV8 — the row-shape mapping is inlined as a local
// (non-exported) function in this file rather than a sibling module.

import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import logger from "@/server/logger";
import { reportSilentFallback } from "@/server/observability";

interface TodayRow {
  id: string;
  source: string;
  owning_domain: string;
  draft_preview: string;
  urgency: string;
}

interface TodayItem {
  id: string;
  source: string;
  owningDomain: string;
  draftPreview: string;
  urgency: string;
}

function toItem(row: TodayRow): TodayItem {
  return {
    id: row.id,
    source: row.source,
    owningDomain: row.owning_domain,
    draftPreview: row.draft_preview,
    urgency: row.urgency,
  };
}

export async function GET(_req: Request) {
  const supabase = await createClient();
  const { data: auth, error: authErr } = await supabase.auth.getUser();
  if (authErr || !auth?.user) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }
  const userId = auth.user.id;

  const { data, error } = await supabase
    .from("messages")
    .select("id, source, owning_domain, draft_preview, urgency")
    .eq("user_id", userId)
    .eq("tier", "external_brand_critical")
    .eq("status", "draft")
    .order("created_at", { ascending: false });

  if (error) {
    reportSilentFallback(error, {
      feature: "dashboard-today",
      op: "select-drafts",
      message: "Failed to load Today drafts",
      extra: { userId },
    });
    logger.error({ err: error, userId }, "dashboard-today: select failed");
    return NextResponse.json({ error: "Internal error" }, { status: 500 });
  }

  const items = (data ?? []).map((r: TodayRow) => toItem(r));
  return NextResponse.json({ items });
}
