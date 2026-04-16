"use client";

import { Sheet } from "@/components/ui/sheet";
import { KbChatContent } from "@/components/chat/kb-chat-content";

export interface KbChatSidebarProps {
  open: boolean;
  onClose: () => void;
  contextPath: string;
}

/**
 * Mobile-only wrapper: renders KbChatContent inside a Sheet (bottom-sheet).
 * On desktop, the layout renders KbChatContent directly inside a Panel.
 */
export function KbChatSidebar({ open, onClose, contextPath }: KbChatSidebarProps) {
  const ariaLabel = `Conversation about ${contextPath.split("/").pop() ?? contextPath}`;

  return (
    <Sheet open={open} onClose={onClose} aria-label={ariaLabel}>
      <KbChatContent contextPath={contextPath} onClose={onClose} visible={open} />
    </Sheet>
  );
}
