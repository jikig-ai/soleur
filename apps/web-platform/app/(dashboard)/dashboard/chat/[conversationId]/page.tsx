"use client";

import { useEffect, useState } from "react";
import { useParams, useSearchParams } from "next/navigation";
import { ChatSurface } from "@/components/chat/chat-surface";
import type { ConversationContext } from "@/lib/types";

/**
 * Full-route chat page. Owns the optional `?context=<path>` query param
 * that requests KB content be fetched and passed as `initialContext`.
 * The KB sidebar path ignores this URL param (it passes `initialContext`
 * directly); only this full-route caller reads it — so the fetch belongs
 * here, not inside `ChatSurface`.
 */
export default function ChatPage() {
  const params = useParams<{ conversationId: string }>();
  const searchParams = useSearchParams();
  const contextParam = searchParams.get("context");

  const [initialContext, setInitialContext] = useState<ConversationContext | undefined>(
    undefined,
  );
  const [contextLoading, setContextLoading] = useState<boolean>(!!contextParam);

  useEffect(() => {
    if (!contextParam) return;
    let cancelled = false;
    (async () => {
      try {
        const res = await fetch(`/api/kb/content/${contextParam}`);
        if (res.ok && !cancelled) {
          const data = await res.json();
          setInitialContext({
            path: contextParam,
            type: "kb-viewer",
            content: data.content,
          });
        }
      } catch (err) {
        // Non-fatal: chat still loads, just without the KB context.
        console.error("KB context fetch failed:", err);
      } finally {
        if (!cancelled) setContextLoading(false);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [contextParam]);

  // Render the chat shell immediately (no blank screen — audit M1) but pass
  // `contextPending` so ChatSurface defers its WS session start until the KB
  // context resolves. This preserves the original invariant — the session
  // still starts once, with the resolved `initialContext` in the same
  // bootstrap call — without gating the whole mount on the fetch.
  return (
    <ChatSurface
      variant="full"
      conversationId={params.conversationId}
      initialContext={initialContext}
      contextPending={contextLoading}
    />
  );
}
