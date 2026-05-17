// PR-F (#3244, #3940) Phase 5 — single Today card.
//
// Renders one draft message from /api/dashboard/today. PR-F ships the
// read surface; Send / Edit / Discard wiring is stubbed until PR-G
// (#3947) lands the action-class flow. The buttons exist so the
// affordance + placement are locked.
//
// Review P2-2 (user-impact-reviewer + code-quality + pattern-recognition):
// the buttons render `disabled` + aria-disabled="true" with a
// "Wires in PR-G (#3947)" title so a founder cannot silently no-op-click
// "Send" on a payment-failed customer-reply draft. Without this guard,
// the affordance is a single-user trust incident the moment
// SOLEUR_FR5_ENABLED flips.

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
          disabled
          aria-disabled="true"
          data-action="send"
          title="Wires in PR-G (#3947)"
          className="min-h-[44px] cursor-not-allowed rounded-md bg-amber-600/40 px-3 py-2 text-sm font-medium text-soleur-text-primary"
          aria-label="Send draft (wired in PR-G)"
        >
          Send
        </button>
        <button
          type="button"
          disabled
          aria-disabled="true"
          data-action="edit"
          title="Wires in PR-G (#3947)"
          className="min-h-[44px] cursor-not-allowed rounded-md border border-soleur-border-default bg-soleur-bg-surface-2 px-3 py-2 text-sm font-medium text-soleur-text-secondary opacity-60"
          aria-label="Edit draft (wired in PR-G)"
        >
          Edit
        </button>
        <button
          type="button"
          disabled
          aria-disabled="true"
          data-action="discard"
          title="Wires in PR-G (#3947)"
          className="min-h-[44px] cursor-not-allowed rounded-md border border-soleur-border-default bg-soleur-bg-surface-2 px-3 py-2 text-sm font-medium text-soleur-text-secondary opacity-60"
          aria-label="Discard draft (wired in PR-G)"
        >
          Discard
        </button>
      </div>
    </article>
  );
}
