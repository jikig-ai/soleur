"use client";

import { RailSlotPortal } from "@/components/dashboard/rail-slot";
import { ConversationsRail } from "@/components/chat/conversations-rail";

// Lifts the chat conversations rail into the single nav rail's secondary slot
// (ADR-047). ConversationsRail is self-contained (its own useConversations
// fetch), so no context needs to cross the portal — the wrapper exists only
// because chat/layout.tsx is a server component and createPortal is client-only.
// `data-testid="conversations-rail"` lives here so it resolves to exactly one
// node regardless of ConversationsRail's collapsed/expanded branch (AC4d).
export function ConversationsRailPortal() {
  return (
    <RailSlotPortal>
      <div data-testid="conversations-rail" className="h-full">
        <ConversationsRail />
      </div>
    </RailSlotPortal>
  );
}
