// Shared two-source fetch for the unified inbox (feat-severity-ranked-inbox
// #6007). Consumed by BOTH GET /api/inbox and the inbox_list agent tool so the
// query shapes never drift (collapses the route↔email-triage-tools "keep in
// lockstep" duplication into one place). Returns RAW rows; ranking/severity is
// the pure lib/inbox-severity module's job.
//
// RLS is load-bearing: the caller passes a USER-CONTEXT / tenant-scoped client
// (never the service client) — reads are gated SOLELY by RLS
// (inbox_item_owner_select + is_email_triage_workspace_owner). No `.eq("user_id"
// …)` re-narrowing (it would hide the shared inbox from co-Owners).

import type { SupabaseClient } from "@supabase/supabase-js";
import type { EmailTriageItem } from "@/components/inbox/email-triage-row";
import type { InboxItemRowData } from "@/lib/inbox-severity";

// Cap on the non-pinned tail per source — the statutory-pinned email query is
// UNCAPPED (a cap must never hide a running statutory clock). Lockstep with
// LIST_LIMIT in app/api/inbox/emails/route.ts + email-triage-tools.ts.
export const LIST_LIMIT = 100;

const EMAIL_COLUMNS =
  "id, user_id, message_id, sender, subject, summary, mail_class, " +
  "statutory_class, rule_id, status, status_changed_at, acknowledged_at, " +
  "received_at, created_at";

const INBOX_COLUMNS =
  "id, severity, source, title, source_ref, status, created_at, read_at, " +
  "acted_at, archived_at";

export interface InboxSources {
  inboxRows: InboxItemRowData[];
  emailRows: EmailTriageItem[];
}

/**
 * Fetch both inbox sources on the given RLS-scoped client. `archived` selects
 * the Archived view (single capped query per source; archived rows are never
 * pinned). The default view mirrors the email route exactly: pinned
 * unacknowledged-independent statutory rows UNCAPPED + the capped rest, plus a
 * capped non-archived inbox_item tail.
 *
 * Throws on any query error so the caller can mirror + return its own error
 * shape (the route returns 500; the tool returns a tool error).
 */
export async function fetchInboxSources(
  client: SupabaseClient,
  opts: { archived: boolean },
): Promise<InboxSources> {
  if (opts.archived) {
    const emailQuery = client
      .from("email_triage_items")
      .select(EMAIL_COLUMNS)
      .or("mail_class.not.is.null,statutory_class.not.is.null")
      // NULL-safe probe exclusion (SQL 3VL) — lockstep with the email route.
      .or("mail_class.is.null,mail_class.neq.probe")
      .eq("status", "archived")
      .order("received_at", { ascending: false })
      .limit(LIST_LIMIT);

    const inboxQuery = client
      .from("inbox_item")
      .select(INBOX_COLUMNS)
      .eq("status", "archived")
      .order("created_at", { ascending: false })
      .limit(LIST_LIMIT);

    const [emailRes, inboxRes] = await Promise.all([emailQuery, inboxQuery]);
    if (emailRes.error) throw emailRes.error;
    if (inboxRes.error) throw inboxRes.error;
    return {
      emailRows: (emailRes.data ?? []) as unknown as EmailTriageItem[],
      inboxRows: (inboxRes.data ?? []) as unknown as InboxItemRowData[],
    };
  }

  // Default view — email: pinned statutory (UNCAPPED) + capped rest.
  const pinnedEmailQuery = client
    .from("email_triage_items")
    .select(EMAIL_COLUMNS)
    .not("statutory_class", "is", null)
    .eq("status", "new")
    .order("received_at", { ascending: false });

  const restEmailQuery = client
    .from("email_triage_items")
    .select(EMAIL_COLUMNS)
    .or("mail_class.not.is.null,statutory_class.not.is.null")
    // Exclude the pinned shape (NOT (statutory AND new), De Morgan) so a row
    // never appears twice.
    .or("statutory_class.is.null,status.neq.new")
    .or("mail_class.is.null,mail_class.neq.probe")
    .neq("status", "archived")
    .order("received_at", { ascending: false })
    .limit(LIST_LIMIT);

  const inboxQuery = client
    .from("inbox_item")
    .select(INBOX_COLUMNS)
    .neq("status", "archived")
    .order("created_at", { ascending: false })
    .limit(LIST_LIMIT);

  const [pinnedRes, restRes, inboxRes] = await Promise.all([
    pinnedEmailQuery,
    restEmailQuery,
    inboxQuery,
  ]);
  if (pinnedRes.error) throw pinnedRes.error;
  if (restRes.error) throw restRes.error;
  if (inboxRes.error) throw inboxRes.error;

  return {
    emailRows: [
      ...((pinnedRes.data ?? []) as unknown as EmailTriageItem[]),
      ...((restRes.data ?? []) as unknown as EmailTriageItem[]),
    ],
    inboxRows: (inboxRes.data ?? []) as unknown as InboxItemRowData[],
  };
}
