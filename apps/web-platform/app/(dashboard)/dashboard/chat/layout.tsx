import type { ReactNode } from "react";
import { ConversationsRail } from "@/components/chat/conversations-rail";

export default function ChatLayout({ children }: { children: ReactNode }) {
  return (
    <div className="flex h-full min-h-0 flex-1">
      <aside
        data-testid="conversations-rail"
        className="hidden md:block md:w-72 md:shrink-0 md:border-r md:border-soleur-border-default md:bg-soleur-bg-base"
      >
        <ConversationsRail />
      </aside>
      <main className="min-w-0 flex-1">{children}</main>
    </div>
  );
}
