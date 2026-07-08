"use client";

// Read-only pipeline column for the beta-CRM board (feat-beta-crm-ui #6172).
// Reskins components/workstream/issue-column.tsx: colored dot + label + count
// header, tinted background wash, inline read-only contact cards (no separate
// card file — simplicity review). Two variants:
//   - column: a full stage column (rendered for every funnel stage, EMPTY ONES
//     TOO — spatial recall, AC7).
//   - rail: the collapsed terminal "Closed Lost" branch (vertical label + count,
//     no cards — per the approved wireframe).

import { STAGE_ACCENT, STAGE_LABEL, COLUMN_TINT_ALPHA, type Stage } from "./stage-style";
import { formatAmount } from "./format";
import { relativeTime } from "@/lib/relative-time";

export type CrmContact = {
  id: string;
  company: string | null;
  name: string | null;
  role: string | null;
  stage: string;
  amount: number | null;
  currency: string | null;
  last_contact: string | null;
};

function ContactCard({
  contact,
  onOpen,
}: {
  contact: CrmContact;
  onOpen: (id: string) => void;
}) {
  const who = [contact.name, contact.role].filter(Boolean).join(" · ") || "—";
  return (
    <button
      type="button"
      onClick={() => onOpen(contact.id)}
      className="w-full rounded-lg border border-soleur-border-default/60 bg-soleur-bg-surface-1/50 p-3 text-left transition-colors hover:bg-soleur-bg-surface-2/40 focus:outline-none focus-visible:ring-1 focus-visible:ring-soleur-accent-gold-fg/60"
      aria-label={`Open ${contact.company ?? "contact"} detail`}
    >
      <p className="truncate text-sm font-medium text-soleur-text-primary">
        {contact.company ?? "Untitled contact"}
      </p>
      <p className="mt-0.5 truncate text-xs text-soleur-text-tertiary">{who}</p>
      <div className="mt-1.5 flex items-center justify-between gap-2">
        <span className="text-xs tabular-nums text-soleur-text-secondary">
          {formatAmount(contact.amount, contact.currency)}
        </span>
        {contact.last_contact ? (
          <span className="text-[11px] tabular-nums text-soleur-text-muted">
            {relativeTime(contact.last_contact)}
          </span>
        ) : null}
      </div>
    </button>
  );
}

export function PipelineColumn({
  stage,
  contacts,
  onOpen,
  rail = false,
}: {
  stage: Stage;
  contacts: CrmContact[];
  onOpen: (id: string) => void;
  rail?: boolean;
}) {
  const accent = STAGE_ACCENT[stage];
  const label = STAGE_LABEL[stage];

  if (rail) {
    // Collapsed terminal branch — vertical label + count, no cards.
    return (
      <section
        className="flex w-10 shrink-0 flex-col items-center rounded-xl border border-soleur-border-default/60 py-2"
        style={{ backgroundColor: `${accent}${COLUMN_TINT_ALPHA}` }}
        aria-label={`${label}: ${contacts.length}`}
      >
        <span className="mb-2 h-2 w-2 rounded-full" style={{ backgroundColor: accent }} aria-hidden />
        <span
          className="text-[11px] font-medium tabular-nums text-soleur-text-tertiary"
          aria-hidden
        >
          {contacts.length}
        </span>
        <h2
          className="mt-2 text-xs font-medium text-soleur-text-secondary"
          style={{ writingMode: "vertical-rl" }}
        >
          {label}
        </h2>
      </section>
    );
  }

  return (
    <section
      className="flex w-72 shrink-0 flex-col rounded-xl border border-soleur-border-default/60 p-2"
      style={{ backgroundColor: `${accent}${COLUMN_TINT_ALPHA}` }}
      aria-label={`${label} stage, ${contacts.length} ${contacts.length === 1 ? "contact" : "contacts"}`}
    >
      <header className="flex items-center gap-2 px-1 py-2">
        <span className="h-2 w-2 rounded-full" style={{ backgroundColor: accent }} aria-hidden />
        <h2 className="text-sm font-medium text-soleur-text-primary">{label}</h2>
        <span className="ml-auto rounded-md bg-soleur-bg-surface-2 px-1.5 py-0.5 text-[11px] font-medium tabular-nums text-soleur-text-tertiary">
          {contacts.length}
        </span>
      </header>
      <div className="flex flex-col gap-2 px-1 pb-1">
        {contacts.map((c) => (
          <ContactCard key={c.id} contact={c} onOpen={onOpen} />
        ))}
      </div>
    </section>
  );
}
