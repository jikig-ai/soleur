// feat-operator-inbox-delegation Phase 5b — email-triage detail page.
//
// Server component mirroring audit/page.tsx: cookie-scoped `createClient`
// (NEVER the service client — the service role bypasses the owner-SELECT
// RLS on email_triage_items), redirect("/login") when unauthenticated,
// belt-and-suspenders `.eq("user_id", user.id)` on top of RLS, and
// force-dynamic (stable deep-link target for the push ping).
//
// INVARIANT — plain-text rendering only. sender/subject/summary/message_id
// are ATTACKER-CONTROLLED (arbitrary inbound email): every one passes
// `sanitizeDisplayString` and renders as plain text nodes — no markdown
// renderer, no dangerouslySetInnerHTML, no anchors built from item content.
// The catalog citation is deliberately plain text (the catalog is a repo
// doc, not a served route).

import { notFound, redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { reportSilentFallback } from "@/server/observability";
import { sanitizeDisplayString } from "@/lib/sanitize-display";
import { triagePillClass, triagePillLabel } from "@/lib/email-triage-display";
import {
  STATUTORY_RULES,
  formatDueDate,
} from "@/lib/email-triage/statutory-rules";

export const dynamic = "force-dynamic";

interface EmailTriageDetailRow {
  id: string;
  message_id: string | null;
  sender: string;
  subject: string;
  summary: string | null;
  mail_class: string | null;
  statutory_class: string | null;
  rule_id: string | null;
  status: string;
  received_at: string;
}

export default async function EmailTriageDetailPage({
  params,
}: {
  params: Promise<{ emailId: string }>;
}) {
  const { emailId } = await params;

  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) redirect("/login");

  // mig 111: workspace-shared reads. RLS (is_email_triage_workspace_owner)
  // is the gate — any Owner of the row's workspace may read. We do NOT add an
  // `.eq("user_id", ...)` filter: that would re-narrow below RLS to the single
  // stamping owner and 404 every co-Owner (the exact bug this fixes).
  // Capture `error` so a real query failure (RLS misconfig, malformed uuid, DB
  // timeout) is mirrored to Sentry instead of collapsing into an indistinct 404.
  const { data, error } = await supabase
    .from("email_triage_items")
    .select(
      "id, message_id, sender, subject, summary, mail_class, statutory_class, rule_id, status, received_at",
    )
    .eq("id", emailId)
    .maybeSingle();

  if (error) {
    // No PII: extra carries ONLY emailId — never sender/subject/summary
    // (attacker-controlled inbound content) and never a foreign user_id.
    reportSilentFallback(error, {
      feature: "email-triage",
      op: "inbox-detail-lookup-error",
      extra: { emailId },
    });
    notFound();
  }
  if (!data) notFound();
  const item = data as unknown as EmailTriageDetailRow;

  const sender = sanitizeDisplayString(item.sender);
  const subject = sanitizeDisplayString(item.subject);
  const summary = item.summary ? sanitizeDisplayString(item.summary) : null;
  const messageId = item.message_id
    ? sanitizeDisplayString(item.message_id)
    : null;

  const isStatutory = item.statutory_class !== null;
  const rule = item.rule_id
    ? STATUTORY_RULES.find((r) => r.ruleId === item.rule_id) ?? null
    : null;

  const pillLabel = triagePillLabel(item);
  const pillClass = triagePillClass(item);

  const receivedDisplay = new Date(item.received_at).toUTCString();

  return (
    <main className="mx-auto max-w-3xl px-6 py-8">
      <div className="rounded-lg border border-soleur-border-default bg-soleur-bg-surface-1 p-6">
        <div className="mb-4 flex items-center justify-between gap-2">
          <span
            className={`inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-medium ${pillClass}`}
          >
            {pillLabel}
          </span>
          <span className="text-xs text-soleur-text-muted">
            Received {receivedDisplay}
          </span>
        </div>

        <h1 className="mb-1 text-xl font-semibold text-soleur-text-primary">
          {subject}
        </h1>
        <p className="mb-6 text-sm text-soleur-text-secondary">{sender}</p>

        {isStatutory && (
          <section
            aria-label="Statutory deadline"
            className="mb-6 rounded-lg border border-red-500/30 bg-red-500/[0.06] p-4"
          >
            <p className="mb-1 text-xs font-medium tracking-widest text-red-500">
              STATUTORY — {item.statutory_class?.toUpperCase()}
            </p>
            {rule ? (
              <>
                <p className="text-sm font-medium text-soleur-text-primary">
                  {formatDueDate(item.received_at, rule.dueRule)}
                </p>
                <p className="mt-1 text-xs text-soleur-text-muted">
                  Matched rule: {rule.ruleId}
                </p>
                <p className="mt-2 text-sm text-soleur-text-secondary">
                  {rule.catalogExcerpt}
                </p>
                {/* Plain text by design — the catalog is a repo doc, not a
                    served route; no hyperlink. */}
                <p className="mt-2 text-xs text-soleur-text-muted">
                  Catalog: knowledge-base/legal/{rule.catalogAnchor}
                </p>
              </>
            ) : (
              <p className="text-sm text-soleur-text-secondary">
                Statutory item — matched rule not found in the registry.
                Verify against the original, normally retained in the Proton
                ops@ mailbox.
              </p>
            )}
          </section>
        )}

        {summary && (
          <section aria-label="Agent summary" className="mb-6">
            <p className="mb-2 text-xs font-medium tracking-widest text-soleur-accent-gold-fg">
              AGENT SUMMARY
            </p>
            <p className="text-sm text-soleur-text-primary">{summary}</p>
          </section>
        )}

        <section aria-label="Message headers" className="mb-6">
          <p className="mb-2 text-xs font-medium tracking-widest text-soleur-accent-gold-fg">
            MESSAGE HEADERS
          </p>
          <dl className="rounded-lg border border-soleur-border-default bg-soleur-bg-surface-2/50 p-4 text-sm">
            <div className="flex gap-4 py-1">
              <dt className="w-24 shrink-0 text-soleur-text-muted">From</dt>
              <dd className="break-all text-soleur-text-secondary">{sender}</dd>
            </div>
            <div className="flex gap-4 py-1">
              <dt className="w-24 shrink-0 text-soleur-text-muted">Subject</dt>
              <dd className="break-all text-soleur-text-secondary">{subject}</dd>
            </div>
            <div className="flex gap-4 py-1">
              <dt className="w-24 shrink-0 text-soleur-text-muted">Received</dt>
              <dd className="text-soleur-text-secondary">{receivedDisplay}</dd>
            </div>
            {messageId && (
              <div className="flex gap-4 py-1">
                <dt className="w-24 shrink-0 text-soleur-text-muted">
                  Message-ID
                </dt>
                <dd className="break-all text-soleur-text-secondary">
                  {messageId}
                </dd>
              </div>
            )}
          </dl>
        </section>

        <p className="rounded-lg border border-soleur-border-default bg-soleur-bg-surface-2/50 p-4 text-xs text-soleur-text-secondary">
          The email body was discarded at ingestion — only this summary is
          stored. The original message is normally retained in the Proton
          ops@ mailbox.
        </p>
      </div>
    </main>
  );
}
