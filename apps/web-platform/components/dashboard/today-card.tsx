// PR-F (#3244, #3940) Phase 5 — single Today card.
//
// Renders one draft message from /api/dashboard/today. PR-F ships the
// read surface; Send / Edit / Discard wiring is stubbed (handlers noop)
// until PR-G (#3947) lands the action-class flow. The buttons exist so
// the affordance is visible and the placement is locked.

interface TodayCardProps {
  id: string;
  source: string;          // "stripe" | "manual" | …
  owningDomain: string;    // "cfo" | …
  draftPreview: string;
  urgency: string;         // "low" | "medium" | "high"
}

export function TodayCard({
  id,
  source,
  owningDomain,
  draftPreview,
  urgency,
}: TodayCardProps) {
  return (
    <article
      data-message-id={id}
      data-urgency={urgency}
      className="mb-3 rounded-lg border border-soleur-border-default bg-soleur-bg-surface-1 p-4"
    >
      <header className="mb-2 flex items-center justify-between gap-2 text-xs uppercase tracking-wide text-soleur-text-secondary">
        <span>
          {owningDomain} • {source}
        </span>
        <span data-urgency-label={urgency}>{urgency}</span>
      </header>
      <p className="mb-3 whitespace-pre-line text-sm text-soleur-text-primary">
        {draftPreview}
      </p>
      <div className="flex flex-wrap gap-2">
        <button
          type="button"
          className="min-h-[44px] rounded-md bg-amber-600 px-3 py-2 text-sm font-medium text-soleur-text-primary"
          aria-label="Send draft"
        >
          Send
        </button>
        <button
          type="button"
          className="min-h-[44px] rounded-md border border-soleur-border-default bg-soleur-bg-surface-2 px-3 py-2 text-sm font-medium text-soleur-text-secondary"
          aria-label="Edit draft"
        >
          Edit
        </button>
        <button
          type="button"
          className="min-h-[44px] rounded-md border border-soleur-border-default bg-soleur-bg-surface-2 px-3 py-2 text-sm font-medium text-soleur-text-secondary"
          aria-label="Discard draft"
        >
          Discard
        </button>
      </div>
    </article>
  );
}
