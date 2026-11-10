// Index of the founder's legal texts (#12011 PR-C, wireframe 17 style): one plain line per registry key with its state in
// plain words, each linking to its card. Server component with the same auth gate as the card page.
//
// The surface gate is read first: the configured founder id only (`LEGAL_ACCEPTANCE_FOUNDER_ID`; the `approval-queue` flag is
// not read, CTO ruling 2026-11-10); anyone else behaves as if the surface were off. A text with no declared card kind is left out
// (and reported on every render, after the gate). With the gate off the page lists only the
// keys the founder already has a recorded row for, and is not-found when there is none: an unreleased key is never listed.

import { notFound, redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { reportLegalOp } from "@/server/approval/ops";
import { isLegalSurfaceEnabled } from "@/server/legal-acceptance/surface";
import { loadLegalTexts } from "@/server/legal-acceptance/canonical";
import { NavLink } from "@/components/ui/nav-link";
import { deriveLegalCardState } from "@/lib/approval-card-state";
import { LEGAL_COPY, legalDisplayLabel, legalIndexState, legalKindCopy, legalTextKind } from "@/lib/legal-acceptance-copy";
import { LEGAL_ROW_COLUMNS, parseLegalRows } from "@/lib/legal-acceptance-wire";

export const dynamic = "force-dynamic";

export default async function LegalAcceptanceIndexPage() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) redirect(`/login?redirectTo=${encodeURIComponent("/dashboard/approvals/legal")}`);

  // The surface gate first (the founder id only): it decides what this page may show at all.
  const flagOn = await isLegalSurfaceEnabled(user.id);

  let entries;
  try {
    entries = [...loadLegalTexts().values()].sort((a, b) => a.key.localeCompare(b.key));
  } catch (err) {
    reportLegalOp("pageReadFailed", err, { userId: user.id, extra: { read: "legal_text" } });
    throw new Error("legal text read failed");
  }

  // A text with no declared card kind has no wording and no card: leave it out, and report each one on every render after the gate (not debounced: the surface is founder-only, so the volume is a few events).
  const declaredEntries = entries.flatMap((e) => {
    const kind = legalTextKind(e.key);
    const kc = legalKindCopy(e.key);
    return kind !== null && kc !== null ? [{ ...e, kind, kc }] : [];
  });
  if (flagOn) {
    for (const e of entries) if (legalKindCopy(e.key) === null) reportLegalOp("kindUndeclared", null, { userId: user.id, tags: { key: e.key } });
  }

  const { data, error } = await supabase.from("legal_acceptance").select(LEGAL_ROW_COLUMNS);
  const rows = error ? null : parseLegalRows(data);
  if (error || rows === null) {
    reportLegalOp("pageReadFailed", error ?? null, { userId: user.id, extra: { read: "legal_acceptance_index" } });
    throw new Error("legal acceptance read failed");
  }

  // Surface off: only the founder's own recorded keys; nothing recorded means there is nothing to show.
  const visible = flagOn ? declaredEntries : declaredEntries.filter((e) => rows.some((r) => r.key === e.key));
  if (!flagOn && visible.length === 0) notFound();

  const now = new Date();
  const items = visible.map((e) => ({
    key: e.key,
    label: legalDisplayLabel(e.kind, e.key, e.body),
    kc: e.kc,
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
                  {i.label}, version {i.version}
                </span>
                <span className="text-sm text-soleur-text-secondary">
                  {i.state === "pending" && !flagOn ? LEGAL_COPY.index.notAvailable : legalIndexState(i.kc, i.state)}
                </span>
              </NavLink>
            </li>
          ))}
        </ul>
      )}
    </main>
  );
}
