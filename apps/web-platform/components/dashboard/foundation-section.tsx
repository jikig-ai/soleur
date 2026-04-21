"use client";

import type { DomainLeaderId } from "@/server/domain-leaders";
import {
  FoundationCards,
  type FoundationCard,
} from "@/components/dashboard/foundation-cards";

interface FoundationSectionProps {
  cards: FoundationCard[];
  getIconPath: (id: DomainLeaderId) => string | null;
  onIncompleteClick: (promptText: string) => void;
  className?: string;
}

/**
 * Section wrapper around FoundationCards — renders the FOUNDATIONS heading,
 * the descriptive copy, and the cards grid. Previously duplicated in two
 * branches of the dashboard page; consolidated so the header/body stay in
 * sync.
 */
export function FoundationSection({
  cards,
  getIconPath,
  onIncompleteClick,
  className = "mb-6",
}: FoundationSectionProps) {
  return (
    <div className={className}>
      <p className="mb-2 text-xs font-medium tracking-widest text-amber-500">
        FOUNDATIONS
      </p>
      <p className="mb-4 text-sm text-neutral-400">
        Complete these to brief your department leaders.
      </p>
      <FoundationCards
        cards={cards}
        getIconPath={getIconPath}
        onIncompleteClick={onIncompleteClick}
      />
    </div>
  );
}
