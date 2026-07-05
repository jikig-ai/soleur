import { NextResponse } from "next/server";
import type { User } from "@supabase/supabase-js";
import { createClient } from "@/lib/supabase/server";
import { reportSilentFallback } from "@/server/observability";
import { withUserRateLimit } from "@/server/with-user-rate-limit";
import { fetchInboxSources } from "@/server/inbox-sources";
import { mergeAndRank } from "@/lib/inbox-severity";

/**
 * GET /api/inbox — the unified, severity-ranked attention inbox
 * (feat-severity-ranked-inbox #6007). Merges two sources into ONE ordered list:
 *   - inbox_item (native operational notifications; native severity)
 *   - email_triage_items (severity computed at the merge layer from
 *     statutory_class — "pin all statutory" per the operator decision)
 *
 * Auth: `withUserRateLimit` (401s unauthenticated at the wrapper) + a
 * USER-CONTEXT Supabase client. NEVER `createServiceClient` here — the service
 * role silently bypasses the workspace-Owner SELECT RLS on BOTH tables (the
 * ADR-066 404-and-bypass trap). Reads are gated SOLELY by RLS; no
 * `.eq("user_id", …)` re-narrowing (it would hide the shared inbox from
 * co-Owners). A source-grep gate (test) asserts no createServiceClient under
 * app/api/inbox/**.
 *
 * Ordering (mergeAndRank, load-bearing): non-archived statutory pinned first
 * (uncapped) → severity rank → recency DESC. The client renders in this order
 * and never re-sorts; the visible NEEDS YOU cap is applied client-side
 * (statutory pins are exempt).
 *
 * Responses: 200 { items } · 401 (wrapper) · 429 (wrapper) · 500 on query error
 * (mirrored to Sentry; no PII in the report).
 */

export const dynamic = "force-dynamic";

async function getHandler(req: Request, user: User) {
  const url = new URL(req.url);
  const archived = url.searchParams.get("status") === "archived";

  const supabase = await createClient();

  try {
    const { inboxRows, emailRows } = await fetchInboxSources(supabase, {
      archived,
    });
    return NextResponse.json({ items: mergeAndRank(inboxRows, emailRows) });
  } catch (error) {
    // No PII: never log sender/subject/title — only the pseudonymous id.
    reportSilentFallback(error, {
      feature: "inbox",
      op: "list",
      message: "unified inbox list query failed",
      extra: { userId: user.id },
    });
    return NextResponse.json({ error: "Internal error" }, { status: 500 });
  }
}

export const GET = withUserRateLimit(getHandler, {
  perMinute: 60,
  feature: "inbox.list",
});
