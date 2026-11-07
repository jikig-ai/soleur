// Index of the founder's legal texts (#12011 PR-C, wireframe 17 style): one plain line per registry key with its state in
// plain words, each linking to its card. Server component with the same auth gate as the card page.
//
// The `approval-queue` flag is read first (effectively global: `workspaceId: null`). With it off the page lists only the
// keys the founder already has a recorded row for, and is not-found when there is none: an unreleased key is never listed.

import { notFound, redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { reportLegalOp } from "@/server/approval/ops";
import { isApprovalQueueEnabled } from "@/server/approval/flag";
import { loadLegalTexts } from "@/server/legal-acceptance/canonical";
import { NavLink } from "@/components/ui/nav-link";
import { deriveLegalCardState } from "@/lib/approval-card-state";
import { LEGAL_COPY, legalTextLabel } from "@/lib/legal-acceptance-copy";
import { LEGAL_ROW_COLUMNS, parseLegalRows } from "@/lib/legal-acceptance-wire";

export const dynamic = "force-dynamic";

export default async function LegalAcceptanceIndexPage() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) redirect(`/login?redirectTo=${encodeURIComponent("/dashboard/approvals/legal")}`);

  // Flag first: it decides what this page may show at all.
  const flagOn = await isApprovalQueueEnabled({ userId: user.id, workspaceId: null });

  let entries;
  try {
    entries = [...loadLegalTexts().values()].sort((a, b) => a.key.localeCompare(b.key));
  } catch (err) {
    reportLegalOp("pageReadFailed", err, { userId: user.id, extra: { read: "legal_text" } });
    throw new Error("legal text read failed");
  }

  const { data, error } = await supabase.from("legal_acceptance").select(LEGAL_ROW_COLUMNS);
  const rows = error ? null : parseLegalRows(data);
  if (error || rows === null) {
    reportLegalOp("pageReadFailed", error ?? null, { userId: user.id, extra: { read: "legal_acceptance_index" } });
    throw new Error("legal acceptance read failed");
  }

  // Flag off: only the founder's own recorded keys; nothing recorded means there is nothing to show.
  const visible = flagOn ? entries : entries.filter((e) => rows.some((r) => r.key === e.key));
  if (!flagOn && visible.length === 0) notFound();

  const now = new Date();
  const items = visible.map((e) => ({
    key: e.key,
    version: e.version,
    state: deriveLegalCardState({
      cardHash: e.textHash,
      currentHash: e.textHash,
      validUntil: e.validUntil,
      rows: rows.filter((r) => r.key === e.key).map((r) => ({ textHash: r.text_hash, choice: r.choice })),
      now,
    }),
  }));

  return (
    <main className="mx-auto max-w-2xl px-4 py-6 md:px-6 md:py-10">
      <h1 className="mb-4 text-xl font-medium text-soleur-text-primary">{LEGAL_COPY.index.title}</h1>
      {items.length === 0 ? (
        <p className="text-sm text-soleur-text-secondary">{LEGAL_COPY.index.empty}</p>
      ) : (
        <ul className="space-y-2">
          {items.map((i) => (
            <li key={i.key}>
              <NavLink
                href={`/dashboard/approvals/legal/${i.key}`}
                className="flex flex-wrap items-baseline justify-between gap-2 rounded-xl border border-soleur-border-default bg-soleur-bg-surface-1 p-4 hover:bg-soleur-bg-surface-2"
              >
                <span className="text-sm font-medium text-soleur-text-primary">
                  {legalTextLabel(i.key)}, version {i.version}
                </span>
                <span className="text-sm text-soleur-text-secondary">
                  {i.state === "pending" && !flagOn ? LEGAL_COPY.index.notAvailable : LEGAL_COPY.index.state[i.state]}
                </span>
              </NavLink>
            </li>
          ))}
        </ul>
      )}
    </main>
  );
}
