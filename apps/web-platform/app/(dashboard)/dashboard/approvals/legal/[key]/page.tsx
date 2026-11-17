// Founder legal-acceptance card page (#12011 PR-C, ADR-319, wireframes 10 to 16). Server component: cookie-session auth
// gate, the text from the server-only registry, the founder's own rows through the user-context client (RLS
// `founder_id = auth.uid()`), then plain props to the client card.
//
//   - Signed out: bounced to sign-in with `redirectTo`. The registry is not consulted before authentication.
//   - A malformed key and an unknown key end in the SAME notFound().
//   - The card gets the registry text body and its hash from here; nothing is hashed in the browser and the browser never
//     sends text back. The row for the CURRENT hash gives the state; rows for older hashes render as "replaced" cards.
//   - The surface gate is read first: the configured founder id only (`LEGAL_ACCEPTANCE_FOUNDER_ID`; the `approval-queue` flag is
//     not read, CTO ruling 2026-11-10; anyone else behaves as if the surface were off). With it off the founder's own
//     recorded rows still render, but a pending or expired current card never does, so neither the registry text nor an
//     unreleased key is shown: with no recorded row for the key the page is the same not-found as an unknown key.
//   - A failed read is reported and throws a generic error: never a silent empty page.

import { notFound, redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { reportLegalOp } from "@/server/approval/ops";
import { isLegalSurfaceEnabled } from "@/server/legal-acceptance/surface";
import { KEY_RE, LegalTextError, getLegalText } from "@/server/legal-acceptance/canonical";
import { LegalAcceptanceCard, type LegalRowFacts } from "@/components/approvals/legal-acceptance-card";
import { NavLink } from "@/components/ui/nav-link";
import { deriveLegalCardState } from "@/lib/approval-card-state";
import { LEGAL_COPY, legalDisplayLabel, legalKindCopy, legalTextKind } from "@/lib/legal-acceptance-copy";
import { LEGAL_ROW_COLUMNS, parseLegalRows, type LegalStoredRow } from "@/lib/legal-acceptance-wire";

export const dynamic = "force-dynamic";

const facts = (r: LegalStoredRow): LegalRowFacts => ({
  choice: r.choice,
  version: r.version,
  decidedAt: r.created_at,
  reauthAt: r.reauth_at,
  requestedEdit: r.requested_edit,
});

export default async function LegalAcceptancePage({ params }: { params: Promise<{ key: string }> }) {
  const { key } = await params;
  if (!KEY_RE.test(key)) notFound();

  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) redirect(`/login?redirectTo=${encodeURIComponent(`/dashboard/approvals/legal/${key}`)}`);

  // The surface gate first (the founder id only): it decides what this page may show at all.
  const surfaceOn = await isLegalSurfaceEnabled(user.id);

  let entry;
  try {
    entry = getLegalText(key);
  } catch (err) {
    // An unknown key is the same not-found as a malformed one. Anything else is a broken registry: loud, not empty.
    if (err instanceof LegalTextError && (err.code === "unknown_key" || err.code === "bad_key")) notFound();
    reportLegalOp("pageReadFailed", err, { userId: user.id, extra: { read: "legal_text" } });
    throw new Error("legal text read failed");
  }

  // A registered text with no declared card kind has no wording and no card: a 404, mirrored to Sentry on every render once the
  // surface gate has passed (a user who may not see the surface generates no event). Before the database read.
  const kc = legalKindCopy(key);
  const kind = legalTextKind(key);
  if (kc === null || kind === null) {
    if (surfaceOn) reportLegalOp("kindUndeclared", null, { userId: user.id, tags: { key } });
    notFound();
  }
  const label = legalDisplayLabel(kind, key, entry.body);

  const { data, error } = await supabase
    .from("legal_acceptance")
    .select(LEGAL_ROW_COLUMNS)
    .eq("key", key)
    .order("created_at", { ascending: false });
  const rows = error ? null : parseLegalRows(data);
  if (error || rows === null) {
    // Static message, ids only: the error text can echo row content.
    reportLegalOp("pageReadFailed", error ?? null, { userId: user.id, extra: { read: "legal_acceptance" } });
    throw new Error("legal acceptance read failed");
  }

  const currentRow = rows.find((r) => r.text_hash === entry.textHash);
  // Surface off: only a recorded answer for the CURRENT text may render it; anything else (pending, expired) stays hidden.
  const showCurrent = surfaceOn || currentRow !== undefined;
  const older = rows.filter((r) => r.text_hash !== entry.textHash);
  if (!showCurrent && older.length === 0) notFound();

  const state = deriveLegalCardState({
    cardHash: entry.textHash,
    currentHash: entry.textHash,
    validUntil: entry.validUntil,
    rows: rows.map((r) => ({ textHash: r.text_hash, choice: r.choice })),
    now: new Date(),
  });

  return (
    <main className="mx-auto max-w-2xl px-4 py-6 md:px-6 md:py-10">
      <header className="mb-4 flex items-baseline justify-between gap-3">
        <h1 className="text-xl font-medium text-soleur-text-primary">{LEGAL_COPY.page.title}</h1>
        <NavLink href="/dashboard/approvals/legal" className="text-sm text-soleur-accent-gold-fg underline">
          {LEGAL_COPY.page.allTexts}
        </NavLink>
      </header>
      <div className="space-y-4">
        {showCurrent && (
          <div id="current-version">
            <LegalAcceptanceCard
              keyName={key}
              label={label}
              version={entry.version}
              body={entry.body}
              textHash={entry.textHash}
              validUntil={entry.validUntil}
              state={state}
              row={currentRow ? facts(currentRow) : null}
              surfaceEnabled={surfaceOn}
              email={user.email ?? null}
              currentVersion={entry.version}
            />
          </div>
        )}
        {older.map((r) => (
          <LegalAcceptanceCard
            key={r.text_hash}
            keyName={key}
            label={label}
            version={r.version}
            body=""
            textHash={r.text_hash}
            validUntil={null}
            state="replaced"
            row={facts(r)}
            surfaceEnabled={surfaceOn}
            email={null}
            currentVersion={entry.version}
            currentVisible={showCurrent}
          />
        ))}
      </div>
    </main>
  );
}
