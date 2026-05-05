"use client";

import { LeaderAvatar } from "@/components/leader-avatar";
import { CC_ROUTER_LEADER_ID } from "@/lib/cc-router-id";
import { DOMAIN_LEADERS } from "@/server/domain-leaders";
import type { DomainLeaderId } from "@/server/domain-leaders";

// Resolves to "Soleur Concierge" via DOMAIN_LEADERS[cc_router].title — NEVER
// the bare `name: "Concierge"`. `getDisplayName('cc_router')` returns the
// bare name and would re-introduce the duplicated-header regression #3225
// fixed in `message-bubble.tsx`.
const CONCIERGE_TITLE =
  DOMAIN_LEADERS.find((l) => l.id === CC_ROUTER_LEADER_ID)?.title ??
  "Soleur Concierge";

interface RoutedLeadersStripProps {
  routeSource: "auto" | "mention";
  routedLeaders: DomainLeaderId[];
  getDisplayName: (id: DomainLeaderId) => string;
  isFull: boolean;
}

export function RoutedLeadersStrip({
  routeSource,
  routedLeaders,
  getDisplayName,
  isFull,
}: RoutedLeadersStripProps) {
  const domainOnly = routedLeaders.filter((id) => id !== CC_ROUTER_LEADER_ID);
  const names = domainOnly.map(getDisplayName);
  const isAuto = routeSource === "auto";
  const visibleJoin = isAuto ? names.join(", ") : `@${names.join(", @")}`;
  const verb = isAuto ? "Auto-routed to" : "Directed to";

  return (
    <div
      data-testid="routed-leaders-strip"
      className={`border-b border-neutral-800/50 px-4 py-2 ${isFull ? "md:px-6" : ""}`}
    >
      <span
        className="inline-flex items-center gap-1.5 rounded-full bg-neutral-800/50 px-3 py-1 text-xs text-neutral-400"
        aria-label={`${CONCIERGE_TITLE} ${verb} ${visibleJoin}`}
      >
        <LeaderAvatar leaderId={CC_ROUTER_LEADER_ID} size="sm" />
        <span>{CONCIERGE_TITLE}</span>
        <span className="text-neutral-600">·</span>
        {verb} {visibleJoin}
      </span>
    </div>
  );
}
