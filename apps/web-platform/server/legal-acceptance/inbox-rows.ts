/**
 * The founder's legal-text rows for the Inbox (CPO ruling P3, CTO ruling T7, 2026-11-08; Ref #12197).
 *
 * One row per DECLARED legal text, derived at request time from the registry and the founder's own decisions; nothing is stored.
 * Called by GET /api/inbox for the ACTIVE view only.
 *
 *   - Gate first: `isLegalSurfaceEnabled` (the flag AND the configured founder). A non-founder or flag-off user returns `[]`
 *     BEFORE any legal_acceptance read.
 *   - The read goes through the REQUEST's user-context client. Migration 184 grants `authenticated` a founder-only SELECT
 *     (RLS), and the service key has no grant on the table, so a service client is both forbidden here
 *     (`test/inbox-no-service-client.test.ts`) and useless. The grant is table-wide, so "never read the note" is an app-level
 *     rule: the select names `key, text_hash, choice` and nothing else (never `requested_edit`, `created_at` or `reauth_at`;
 *     `LEGAL_ROW_COLUMNS` includes the note and must not be reused). `.eq("founder_id", …)` and `.in("key", …)` are defence in
 *     depth on top of RLS.
 *   - Only `pending` is `action_required` (and outstanding). Every other state, `expired` included, is `info`.
 *   - Never throws. A failed gate, a failed or malformed read, or an unreadable registry omits the legal rows and reports
 *     `pageReadFailed` (`read: legal_acceptance_inbox`); the other inbox items are unaffected. Recorded, not paged (#12195).
 *
 * The payload carries `{key, label, version, validUntil, state}` and the derived severity: no text hash, no note, no
 * timestamp, no account id.
 */

import { deriveLegalCardState } from "@/lib/approval-card-state";
import type { LegalInboxRowData } from "@/lib/inbox-severity";
import { LEGAL_TEXT_KIND, legalDisplayLabel, legalTextKind, type LegalTextKind } from "@/lib/legal-acceptance-copy";
import { isLegalChoice, type LegalChoiceWire } from "@/lib/legal-acceptance-wire";
import { reportLegalOp } from "@/server/approval/ops";
import { loadLegalTexts, type LegalTextEntry } from "@/server/legal-acceptance/canonical";
import { isLegalSurfaceEnabled } from "@/server/legal-acceptance/surface";

/** The columns read from `legal_acceptance`. Deliberately NOT `LEGAL_ROW_COLUMNS` (which includes the Request-changes note). */
export const LEGAL_INBOX_COLUMNS = "key, text_hash, choice";

/** The `extra.read` label on a `pageReadFailed` report from this read. */
export const LEGAL_INBOX_READ_LABEL = "legal_acceptance_inbox";

/** The slice of the user-context Supabase client this module uses. */
interface LegalInboxClient {
  from(table: "legal_acceptance"): {
    select(columns: string): {
      eq(column: string, value: string): {
        in(column: string, values: string[]): PromiseLike<{ data: unknown; error: unknown }>;
      };
    };
  };
}

export interface LegalInboxOptions {
  now?: Date;
  /** Test seam: the registry. */
  texts?: () => Map<string, LegalTextEntry>;
  /** Test seam: the declared kinds. */
  declared?: Readonly<Record<string, LegalTextKind>>;
}

interface StoredDecision {
  key: string;
  textHash: string;
  choice: LegalChoiceWire;
}

/** Strict parse of the three-column select: one malformed row makes the whole read `null` (a loud failure, never a partial list). */
function parseDecisions(data: unknown): StoredDecision[] | null {
  if (!Array.isArray(data)) return null;
  const out: StoredDecision[] = [];
  for (const r of data as Record<string, unknown>[]) {
    if (!r || typeof r.key !== "string" || typeof r.text_hash !== "string" || !isLegalChoice(r.choice)) return null;
    out.push({ key: r.key, textHash: r.text_hash, choice: r.choice });
  }
  return out;
}

export async function loadLegalInboxRows(
  supabase: unknown,
  userId: string,
  opts: LegalInboxOptions = {},
): Promise<LegalInboxRowData[]> {
  try {
    if (!(await isLegalSurfaceEnabled(userId))) return [];

    const declared = opts.declared ?? LEGAL_TEXT_KIND;
    const entries = [...(opts.texts ?? loadLegalTexts)().values()].sort((a, b) => a.key.localeCompare(b.key));
    const declaredEntries = entries.flatMap((e) => {
      const kind = legalTextKind(e.key, declared);
      return kind === null ? [] : [{ entry: e, kind }];
    });
    if (declaredEntries.length === 0) return [];

    const { data, error } = await (supabase as LegalInboxClient)
      .from("legal_acceptance")
      .select(LEGAL_INBOX_COLUMNS)
      .eq("founder_id", userId)
      .in(
        "key",
        declaredEntries.map((d) => d.entry.key),
      );
    if (error) throw error;
    const decisions = parseDecisions(data);
    if (decisions === null) throw new Error("legal acceptance inbox read returned an unrecognised shape");

    const now = opts.now ?? new Date();
    return declaredEntries.map(({ entry, kind }) => {
      const state = deriveLegalCardState({
        cardHash: entry.textHash,
        currentHash: entry.textHash,
        validUntil: entry.validUntil,
        rows: decisions.filter((d) => d.key === entry.key).map((d) => ({ textHash: d.textHash, choice: d.choice })),
        now,
      });
      // cardHash === currentHash, so `replaced` cannot occur; a text that changed with no answer yet is `pending` again.
      if (state === "replaced") throw new Error("unreachable legal card state");
      const pending = state === "pending";
      return {
        key: entry.key,
        label: legalDisplayLabel(kind, entry.key, entry.body),
        version: entry.version,
        validUntil: entry.validUntil,
        state,
        severity: pending ? ("action_required" as const) : ("info" as const),
        outstanding: pending,
      };
    });
  } catch (err) {
    // The other inbox items still return; the founder sees no legal row and no hint (Sentry is the signal, and the card page
    // stays reachable by URL).
    reportLegalOp("pageReadFailed", err, { userId, extra: { read: LEGAL_INBOX_READ_LABEL } });
    return [];
  }
}
