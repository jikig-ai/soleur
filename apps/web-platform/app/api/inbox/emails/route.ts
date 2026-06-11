import { NextResponse } from "next/server";
import type { User } from "@supabase/supabase-js";
import { createClient } from "@/lib/supabase/server";
import { reportSilentFallback } from "@/server/observability";
import { withUserRateLimit } from "@/server/with-user-rate-limit";

/**
 * GET /api/inbox/emails — operator email-triage inbox list.
 *
 * Auth: `withUserRateLimit` (401s unauthenticated callers at the wrapper) +
 * user-context Supabase client. NEVER `createServiceClient` here — the
 * service role silently bypasses the owner-SELECT RLS on
 * `email_triage_items`. The explicit `.eq("user_id", ...)` below is
 * belt-and-suspenders on top of RLS, not a substitute for it.
 *
 * Filters (mirrored exactly by the `email_triage_list` agent tool in
 * `server/email-triage-tools.ts` — keep both in lockstep):
 *   - Unfinalized stubs excluded: between claim-insert and finalize a row
 *     has NULL mail_class AND NULL statutory_class (and a NULL summary) and
 *     must not render. `.or("mail_class.not.is.null,statutory_class.not.is.null")`.
 *   - Probe rows (`mail_class = 'probe'`) excluded unless
 *     `?include_probes=1` (STRICT `=== "1"`). The exclusion is the NULL-safe
 *     `.or("mail_class.is.null,mail_class.neq.probe")` — a plain
 *     `.neq("mail_class", "probe")` would also drop `mail_class IS NULL`
 *     statutory fast-path rows (SQL three-valued logic).
 *   - Archived excluded unless `?status=archived` (strict equality; any
 *     other value = default view).
 *
 * Ordering contract (server-side; component correctness must not be the
 * only enforcement): unacknowledged statutory rows first
 * (statutory_class NOT NULL AND status = 'new'), then received_at DESC.
 * PostgREST cannot order on that computed flag, so the DB orders by
 * received_at DESC and the pin is applied here via a stable partition —
 * the simplest correct shape (rows are small by construction: no body
 * column exists).
 *
 * Responses:
 *   200 + JSON { items: [...] } (full rows)
 *   401 unauthenticated (wrapper)
 *   429 over per-user budget (wrapper)
 *   500 on query error (mirrored to Sentry; no PII in the report)
 */

export const dynamic = "force-dynamic";

const LIST_COLUMNS =
  "id, user_id, message_id, sender, subject, summary, mail_class, " +
  "statutory_class, rule_id, status, status_changed_at, acknowledged_at, " +
  "received_at, created_at";

interface TriageListRow {
  statutory_class: string | null;
  status: string;
}

// Stable partition: pinned group keeps its received_at DESC order, as does
// the rest. Duplicated (deliberately, ~6 lines) in email-triage-tools.ts —
// a shared server module would pull the agent-SDK import into this route.
function statutoryPinnedFirst<T extends TriageListRow>(rows: T[]): T[] {
  const isPinned = (r: T) => r.statutory_class !== null && r.status === "new";
  return [...rows.filter(isPinned), ...rows.filter((r) => !isPinned(r))];
}

async function getHandler(req: Request, user: User) {
  const url = new URL(req.url);
  const includeProbes = url.searchParams.get("include_probes") === "1";
  const archivedView = url.searchParams.get("status") === "archived";

  const supabase = await createClient();
  let query = supabase
    .from("email_triage_items")
    .select(LIST_COLUMNS)
    .eq("user_id", user.id)
    .or("mail_class.not.is.null,statutory_class.not.is.null");

  if (!includeProbes) {
    query = query.or("mail_class.is.null,mail_class.neq.probe");
  }

  query = archivedView
    ? query.eq("status", "archived")
    : query.neq("status", "archived");

  const { data, error } = await query.order("received_at", {
    ascending: false,
  });

  if (error) {
    // No PII: never log sender/subject/summary — only the pseudonymous ids.
    reportSilentFallback(error, {
      feature: "inbox-emails",
      op: "list",
      message: "email_triage_items list query failed",
      extra: { userId: user.id },
    });
    return NextResponse.json({ error: "Internal error" }, { status: 500 });
  }

  return NextResponse.json({
    items: statutoryPinnedFirst((data ?? []) as unknown as TriageListRow[]),
  });
}

export const GET = withUserRateLimit(getHandler, {
  perMinute: 60,
  feature: "inbox.emails",
});
