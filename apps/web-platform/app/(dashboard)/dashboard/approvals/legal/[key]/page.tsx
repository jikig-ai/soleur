// Founder legal-acceptance card page (#12011 PR-C, ADR-319, wireframes 10 to 16). Server component: cookie-session auth
// gate, the text from the server-only registry, the founder's own rows through the user-context client (RLS
// `founder_id = auth.uid()`), then plain props to the client card.
//
//   - Signed out: bounced to sign-in with `redirectTo`. The registry is not consulted before authentication.
//   - A malformed key and an unknown key end in the SAME notFound().
//   - The card gets the registry text body and its hash from here; nothing is hashed in the browser and the browser never
//     sends text back. The row for the CURRENT hash gives the state; rows for older hashes render as "replaced" cards.
//   - Renders existing rows REGARDLESS of the `approval-queue` flag. With the flag off a pending card is read-only: no
//     actions, a plain "not available yet" line.
//   - A failed read is reported and throws a generic error: never a silent empty page.

import { notFound, redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { reportApprovalOp } from "@/server/approval/ops";
import { isApprovalQueueEnabled } from "@/server/approval/flag";
import { KEY_RE, LegalTextError, getLegalText } from "@/server/legal-acceptance/canonical";
import { LegalAcceptanceCard, type LegalRowFacts } from "@/components/approvals/legal-acceptance-card";
import { NavLink } from "@/components/ui/nav-link";
import { deriveLegalCardState } from "@/lib/approval-card-state";
import { LEGAL_COPY } from "@/lib/legal-acceptance-copy";
import { isLegalChoice, type LegalChoiceWire } from "@/lib/legal-acceptance-wire";

export const dynamic = "force-dynamic";

const ROW_COLUMNS = "text_hash, version, choice, requested_edit, reauth_at, created_at";

interface StoredRow {
  text_hash: string;
  version: string;
  choice: LegalChoiceWire;
  requested_edit: string | null;
  reauth_at: string | null;
  created_at: string;
}

function parseRows(data: unknown): StoredRow[] | null {
  if (!Array.isArray(data)) return null;
  const out: StoredRow[] = [];
  for (const r of data as Record<string, unknown>[]) {
    if (
      !r ||
      typeof r.text_hash !== "string" ||
      typeof r.version !== "string" ||
      !isLegalChoice(r.choice) ||
      typeof r.created_at !== "string" ||
      (r.requested_edit !== null && typeof r.requested_edit !== "string") ||
      (r.reauth_at !== null && typeof r.reauth_at !== "string")
    ) {
      return null;
    }
    out.push({
      text_hash: r.text_hash,
      version: r.version,
      choice: r.choice,
      requested_edit: r.requested_edit as string | null,
      reauth_at: r.reauth_at as string | null,
      created_at: r.created_at,
    });
  }
  return out;
}

const facts = (r: StoredRow): LegalRowFacts => ({
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

  let entry;
  try {
    entry = getLegalText(key);
  } catch (err) {
    // An unknown key is the same not-found as a malformed one. Anything else is a broken registry: loud, not empty.
    if (err instanceof LegalTextError && (err.code === "unknown_key" || err.code === "bad_key")) notFound();
    reportApprovalOp("landingReadFailed", err, { userId: user.id, extra: { read: "legal_text" } });
    throw new Error("legal text read failed");
  }

  const { data, error } = await supabase
    .from("legal_acceptance")
    .select(ROW_COLUMNS)
    .eq("key", key)
    .order("created_at", { ascending: false });
  const rows = error ? null : parseRows(data);
  if (error || rows === null) {
    // Static message, ids only: the error text can echo row content.
    reportApprovalOp("landingReadFailed", error ?? null, { userId: user.id, extra: { read: "legal_acceptance" } });
    throw new Error("legal acceptance read failed");
  }

  const state = deriveLegalCardState({
    cardHash: entry.textHash,
    currentHash: entry.textHash,
    validUntil: entry.validUntil,
    rows: rows.map((r) => ({ textHash: r.text_hash, choice: r.choice })),
    now: new Date(),
  });
  const currentRow = rows.find((r) => r.text_hash === entry.textHash);
  // The flag only decides whether a pending card may take an answer; every other state is a record and always renders.
  const flagEnabled = state === "pending" ? await isApprovalQueueEnabled({ userId: user.id, workspaceId: null }) : true;
  const older = rows.filter((r) => r.text_hash !== entry.textHash);

  return (
    <main className="mx-auto max-w-2xl px-4 py-6 md:px-6 md:py-10">
      <header className="mb-4 flex items-baseline justify-between gap-3">
        <h1 className="text-xl font-medium text-soleur-text-primary">{LEGAL_COPY.page.title}</h1>
        <NavLink href="/dashboard/approvals/legal" className="text-sm text-soleur-accent-gold-fg underline">
          {LEGAL_COPY.page.allTexts}
        </NavLink>
      </header>
      <div className="space-y-4">
        <div id="current-version">
          <LegalAcceptanceCard
            keyName={key}
            version={entry.version}
            body={entry.body}
            textHash={entry.textHash}
            validUntil={entry.validUntil}
            state={state}
            row={currentRow ? facts(currentRow) : null}
            flagEnabled={flagEnabled}
            email={user.email ?? null}
            currentVersion={entry.version}
          />
        </div>
        {older.map((r) => (
          <LegalAcceptanceCard
            key={r.text_hash}
            keyName={key}
            version={r.version}
            body=""
            textHash={r.text_hash}
            validUntil={null}
            state="replaced"
            row={facts(r)}
            flagEnabled={flagEnabled}
            email={null}
            currentVersion={entry.version}
          />
        ))}
      </div>
    </main>
  );
}
