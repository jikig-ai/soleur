// The words on a founder legal-text row in the Inbox (CPO ruling P3, 2026-11-08; Ref #12197).
//
// Row copy comes ONLY from existing deck strings (`LEGAL_COPY` and the text kind's own wording in `lib/legal-acceptance-copy.ts`):
// this module composes them and writes no sentence of its own, so the row needs no new CLO pin. Pure and client-safe.

import { LEGAL_COPY, legalKindCopy, legalTextLabel } from "@/lib/legal-acceptance-copy";
import type { LegalInboxState } from "@/lib/inbox-severity";

export interface LegalInboxWords {
  title: string;
  badge: string;
  /** "<label>, version <version>": the deck's own meta line, which also names the version a replaced text now needs answered. */
  meta: string;
  /** "Open until <date>, end of day UTC" for a pending text that has a `valid_until`; otherwise null (no chip). */
  openUntil: string | null;
}

/**
 * Title and badge per state, from the deck. A key whose kind is not declared (it should never reach the client: the server only
 * derives declared texts) falls back to the plain label as title and the shared pending badge, never a guessed wording.
 */
export function legalInboxWords(row: {
  key: string;
  label: string;
  version: string;
  validUntil: string | null;
  state: LegalInboxState;
}): LegalInboxWords {
  const kc = legalKindCopy(row.key);
  const label = row.label || legalTextLabel(row.key);
  const meta = LEGAL_COPY.textMeta(label, row.version);
  const openUntil = row.state === "pending" && row.validUntil ? LEGAL_COPY.pending.openUntil(row.validUntil) : null;
  if (kc === null) return { title: label, badge: LEGAL_COPY.pending.badge, meta, openUntil };
  switch (row.state) {
    case "pending":
      return { title: kc.pendingTitle(label), badge: LEGAL_COPY.pending.badge, meta, openUntil };
    case "accepted":
      return { title: kc.acceptedTitle(label), badge: kc.acceptedBadge, meta, openUntil };
    case "declined":
      return { title: kc.declinedTitle(label), badge: LEGAL_COPY.declined.badge, meta, openUntil };
    case "changes_requested":
      return { title: LEGAL_COPY.changesRequested.title, badge: LEGAL_COPY.changesRequested.badge, meta, openUntil };
    case "expired":
      return { title: LEGAL_COPY.expired.title, badge: LEGAL_COPY.expired.badge, meta, openUntil };
    default: {
      const _exhaustive: never = row.state;
      return _exhaustive;
    }
  }
}
