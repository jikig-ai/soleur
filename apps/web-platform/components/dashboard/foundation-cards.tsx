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
 * Grid of foundation status cards (Vision, Brand, Validation, Legal).
 *
 * Each card renders as either:
 * - `<a href>` (completed) — links to the KB path for viewing.
 * - `<button>` (incomplete) — invokes `onIncompleteClick` with the suggested prompt.
 *
 * The outer section wrapper (FOUNDATIONS header, description copy, container
 * classes) is owned by the caller — this component renders only the inner grid.
 */
export function FoundationCards({
  cards,
  getIconPath,
  onIncompleteClick,
}: FoundationCardsProps): ReactElement {
  return (
    <div className="grid grid-cols-2 gap-3 md:grid-cols-4">
      {cards.map((card) =>
        card.done ? (
          <a
            key={card.id}
            href={`/dashboard/kb/${card.kbPath}`}
            className="flex flex-col gap-2 rounded-xl border border-neutral-800/50 bg-neutral-900/30 p-4 text-left transition-colors hover:border-neutral-700"
          >
            <span className="text-lg text-green-500" aria-label="Complete">
              <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round">
                <path d="M20 6 9 17l-5-5" />
              </svg>
            </span>
            <span className="text-sm font-medium text-neutral-400">
              {card.title}
            </span>
            <span className="text-xs text-neutral-600">
              View in Knowledge Base
            </span>
          </a>
        ) : (
          <button
            key={card.id}
            type="button"
            onClick={() => onIncompleteClick(card.promptText)}
            className="flex flex-col gap-2 rounded-xl border border-neutral-800 bg-neutral-900/50 p-4 text-left transition-colors hover:border-neutral-600"
          >
            <LeaderAvatar
              leaderId={card.leaderId}
              size="sm"
              customIconPath={getIconPath(card.leaderId)}
            />
            <span className="text-sm font-medium text-white">
              {card.title}
            </span>
            <span className="text-xs text-neutral-500">
              {card.promptText}
            </span>
          </button>
        ),
      )}
    </div>
  );
}
