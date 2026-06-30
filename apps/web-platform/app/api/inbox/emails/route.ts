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
 * service role silently bypasses the workspace-owner-SELECT RLS on
 * `email_triage_items`. mig 111: reads are gated SOLELY by RLS
 * (is_email_triage_workspace_owner — any Owner of the row's workspace). We do
 * NOT add an `.eq("user_id", ...)` filter: it would re-narrow below RLS to the
 * single stamping owner and hide the shared inbox from co-Owners.
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
 * Bounded result (L1): every query carries `.limit(LIST_LIMIT)` EXCEPT the
 * pinned statutory query — the default view is two queries merged
 * pinned-first:
 *   (1) pinned: unacknowledged statutory rows (statutory_class NOT NULL AND
 *       status = 'new'), UNCAPPED — bounded in practice by acknowledgment,
 *       and a cap must NEVER be able to hide a running statutory clock;
 *   (2) rest: everything else in the default view, `.limit(LIST_LIMIT)`,
 *       with the pinned shape excluded via the De-Morgan
 *       `.or("statutory_class.is.null,status.neq.new")` so rows never
 *       appear twice.
 * Both queries order received_at DESC; the merge concatenates pinned-first,
 * preserving the ordering contract (unacknowledged statutory first, then
 * received_at DESC). The archived view is a single capped query (archived
 * rows are never pinned: pinning requires status = 'new').
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

// Cap on the non-pinned result set — without it the default view grows
// monotonically with inbox history. Mirrored in email-triage-tools.ts.
const LIST_LIMIT = 100;

async function getHandler(req: Request, user: User) {
  const url = new URL(req.url);
  const includeProbes = url.searchParams.get("include_probes") === "1";
  const archivedView = url.searchParams.get("status") === "archived";

  const supabase = await createClient();

  const queryError = (error: unknown) => {
    // No PII: never log sender/subject/summary — only the pseudonymous ids.
    reportSilentFallback(error, {
      feature: "inbox-emails",
      op: "list",
      message: "email_triage_items list query failed",
      extra: { userId: user.id },
    });
    return NextResponse.json({ error: "Internal error" }, { status: 500 });
  };

  if (archivedView) {
    let query = supabase
      .from("email_triage_items")
      .select(LIST_COLUMNS)
      .or("mail_class.not.is.null,statutory_class.not.is.null");
    if (!includeProbes) {
      query = query.or("mail_class.is.null,mail_class.neq.probe");
    }
    const { data, error } = await query
      .eq("status", "archived")
      .order("received_at", { ascending: false })
      .limit(LIST_LIMIT);
    if (error) return queryError(error);
    return NextResponse.json({ items: data ?? [] });
  }

  // Default view — query (1): pinned unacknowledged statutory rows.
  // statutory_class NOT NULL already implies finalized; status = 'new'
  // already excludes archived; probe rows are never statutory. UNCAPPED on
  // purpose — see header.
  const pinnedQuery = supabase
    .from("email_triage_items")
    .select(LIST_COLUMNS)
    .not("statutory_class", "is", null)
    .eq("status", "new")
    .order("received_at", { ascending: false });

  // Default view — query (2): the rest, capped.
  let restQuery = supabase
    .from("email_triage_items")
    .select(LIST_COLUMNS)
    .or("mail_class.not.is.null,statutory_class.not.is.null")
    // Exclude the pinned shape (NOT (statutory AND new), De Morgan) so the
    // merge never duplicates a row.
    .or("statutory_class.is.null,status.neq.new");
  if (!includeProbes) {
    restQuery = restQuery.or("mail_class.is.null,mail_class.neq.probe");
  }
  const boundedRestQuery = restQuery
    .neq("status", "archived")
    .order("received_at", { ascending: false })
    .limit(LIST_LIMIT);

  const [pinnedRes, restRes] = await Promise.all([pinnedQuery, boundedRestQuery]);
  if (pinnedRes.error) return queryError(pinnedRes.error);
  if (restRes.error) return queryError(restRes.error);

  return NextResponse.json({
    items: [...(pinnedRes.data ?? []), ...(restRes.data ?? [])],
  });
}

export const GET = withUserRateLimit(getHandler, {
  perMinute: 60,
  feature: "inbox.emails",
});
