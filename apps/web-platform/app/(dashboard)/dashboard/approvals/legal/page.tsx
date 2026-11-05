// Index of the founder's legal texts (#12011 PR-C, wireframe 17 style): one plain line per registry key with its state in
// plain words, each linking to its card. Server component with the same auth gate as the card page.

import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { reportApprovalOp } from "@/server/approval/ops";
import { isApprovalQueueEnabled } from "@/server/approval/flag";
import { loadLegalTexts } from "@/server/legal-acceptance/canonical";
import { NavLink } from "@/components/ui/nav-link";
import { deriveLegalCardState } from "@/lib/approval-card-state";
import { LEGAL_COPY, legalTextLabel } from "@/lib/legal-acceptance-copy";
import { isLegalChoice } from "@/lib/legal-acceptance-wire";

export const dynamic = "force-dynamic";

export default async function LegalAcceptanceIndexPage() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) redirect(`/login?redirectTo=${encodeURIComponent("/dashboard/approvals/legal")}`);

  let entries;
  try {
    entries = [...loadLegalTexts().values()].sort((a, b) => a.key.localeCompare(b.key));
  } catch (err) {
    reportApprovalOp("landingReadFailed", err, { userId: user.id, extra: { read: "legal_text" } });
    throw new Error("legal text read failed");
  }

  const { data, error } = await supabase.from("legal_acceptance").select("key, text_hash, choice");
  const raw = error ? null : data;
  const rows = Array.isArray(raw)
    ? (raw as Record<string, unknown>[]).every((r) => r && typeof r.key === "string" && typeof r.text_hash === "string" && isLegalChoice(r.choice))
      ? (raw as { key: string; text_hash: string; choice: "accept" | "decline" | "request_changes" }[])
      : null
    : null;
  if (error || rows === null) {
    reportApprovalOp("landingReadFailed", error ?? null, { userId: user.id, extra: { read: "legal_acceptance_index" } });
    throw new Error("legal acceptance read failed");
  }

  const now = new Date();
  const items = entries.map((e) => ({
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
  const anyPending = items.some((i) => i.state === "pending");
  const flagEnabled = anyPending ? await isApprovalQueueEnabled({ userId: user.id, workspaceId: null }) : true;

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
                  {i.state === "pending" && !flagEnabled ? LEGAL_COPY.index.notAvailable : LEGAL_COPY.index.state[i.state]}
                </span>
              </NavLink>
            </li>
          ))}
        </ul>
      )}
    </main>
  );
}
