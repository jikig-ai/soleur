"use client";

import type { ReactElement } from "react";
import type { DomainLeaderId } from "@/server/domain-leaders";
import { LeaderAvatar } from "@/components/leader-avatar";

export interface FoundationCard {
  id: string;
  title: string;
  leaderId: DomainLeaderId;
  kbPath: string;
  promptText: string;
  done: boolean;
}

interface FoundationCardsProps {
  cards: FoundationCard[];
  getIconPath: (id: DomainLeaderId) => string | null;
  onIncompleteClick: (promptText: string) => void;
}

/**
 * Foundation and operational task cards with progressive surfacing.
 *
 * Completed cards render as compact chips above the active grid.
 * Incomplete cards render in the grid as clickable buttons.
 *
 * The outer section wrapper (FOUNDATIONS header, description copy, container
 * classes) is owned by the caller — this component renders only the inner
 * chips row and grid.
 */
export function FoundationCards({
  cards,
  getIconPath,
  onIncompleteClick,
}: FoundationCardsProps): ReactElement {
  const completed = cards.filter((c) => c.done);
  const active = cards.filter((c) => !c.done);

  return (
    <>
      {/* Completed chips */}
      {completed.length > 0 && (
        <div data-testid="completed-chips" className="mb-3 flex flex-wrap gap-2">
          {completed.map((card) => (
            <a
              key={card.id}
              href={`/dashboard/kb/${card.kbPath}`}
              className="inline-flex items-center gap-1.5 rounded-lg border border-soleur-border-default/50 bg-soleur-bg-surface-1/30 px-3 py-1.5 text-sm text-soleur-text-secondary transition-colors hover:border-soleur-border-default hover:text-soleur-text-secondary"
            >
              <svg className="h-3.5 w-3.5 text-green-500" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
                <path d="M20 6 9 17l-5-5" />
              </svg>
              {card.title}
            </a>
          ))}
        </div>
      )}

      {/* Active card grid */}
      {active.length > 0 && (
        <div data-testid="active-grid" className="grid grid-cols-2 gap-3 md:grid-cols-4">
          {active.map((card) => (
            <button
              key={card.id}
              type="button"
              onClick={() => onIncompleteClick(card.promptText)}
              className="flex flex-col gap-2 rounded-xl border border-soleur-border-default bg-soleur-bg-surface-1/50 p-4 text-left transition-colors hover:border-soleur-border-default"
            >
              <LeaderAvatar
                leaderId={card.leaderId}
                size="sm"
                customIconPath={getIconPath(card.leaderId)}
              />
              <span className="text-sm font-medium text-soleur-text-primary">
                {card.title}
              </span>
              <span className="text-xs text-soleur-text-muted">
                {card.promptText}
              </span>
            </button>
          ))}
        </div>
      )}
    </>
  );
}
