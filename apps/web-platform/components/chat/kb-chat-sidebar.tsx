"use client";

import { useMediaQuery } from "@/hooks/use-media-query";
import { Sheet } from "@/components/ui/sheet";
import { KbChatContent } from "@/components/chat/kb-chat-content";
import { KbChatFullScreen } from "@/components/chat/kb-chat-fullscreen";

export interface KbChatSidebarProps {
  open: boolean;
  onClose: () => void;
  contextPath: string;
}

/**
 * The KB document conversation, hosted by breakpoint.
 *
 * `md`+ keeps `Sheet`, whose desktop branch is an INLINE push-column (not an
 * overlay) — that is the intended desktop topology and is untouched.
 *
 * #7222: below `md`, `Sheet` used to render a constant 60vh bottom sheet, so the
 * conversation and the document each got roughly half a phone screen and neither
 * was usable. That branch is replaced by the full-screen takeover. Note the fix
 * had to land HERE and in `c4-workspace.tsx` both: a Sheet-only change never
 * reaches the C4 page, which suppresses this side panel entirely and embeds its
 * own Concierge.
 */
export function KbChatSidebar({ open, onClose, contextPath }: KbChatSidebarProps) {
  const isDesktop = useMediaQuery("(min-width: 768px)");
  const ariaLabel = `Conversation about ${contextPath.split("/").pop() ?? contextPath}`;

  if (!isDesktop) {
    return (
      <KbChatFullScreen open={open} onClose={onClose} contextPath={contextPath}>
        <KbChatContent
          contextPath={contextPath}
          onClose={onClose}
          visible={open}
          mobileTakeover
        />
      </KbChatFullScreen>
    );
  }

  return (
    <Sheet open={open} onClose={onClose} aria-label={ariaLabel}>
      <KbChatContent contextPath={contextPath} onClose={onClose} visible={open} />
    </Sheet>
  );
}
