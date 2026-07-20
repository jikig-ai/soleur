"use client";

import { useEffect, useState } from "react";
import { useParams, useRouter, useSearchParams } from "next/navigation";
import { ChatSurface } from "@/components/chat/chat-surface";
import type { ConversationContext } from "@/lib/types";
import { createClient } from "@/lib/supabase/client";
import { isResumeableConversationId } from "@/lib/nav-resume";
import { useNavResume } from "@/hooks/use-nav-resume";

/**
 * Full-route chat page. Owns the optional `?context=<path>` query param
 * that requests KB content be fetched and passed as `initialContext`.
 * The KB sidebar path ignores this URL param (it passes `initialContext`
 * directly); only this full-route caller reads it — so the fetch belongs
 * here, not inside `ChatSurface`.
 *
 * #4826 AC10: if a resumeable conversation id is not found (deleted /
 * wrong workspace), clear the sticky chat key and soft-replace to `/new`
 * so bare `/dashboard/chat` does not keep reopening a dead thread.
 */
export default function ChatPage() {
  const params = useParams<{ conversationId: string }>();
  const searchParams = useSearchParams();
  const router = useRouter();
  const { clearChatId } = useNavResume();
  const contextParam = searchParams.get("context");
  const conversationId = params.conversationId;

  const [initialContext, setInitialContext] = useState<ConversationContext | undefined>(
    undefined,
  );
  const [contextLoading, setContextLoading] = useState<boolean>(!!contextParam);

  // Stale-resume fail-closed (AC10).
  useEffect(() => {
    if (!conversationId || conversationId === "new") return;
    if (!isResumeableConversationId(conversationId)) return;
    let cancelled = false;
    (async () => {
      try {
        const supabase = createClient();
        const { data, error } = await supabase
          .from("conversations")
          .select("id")
          .eq("id", conversationId)
          .maybeSingle();
        if (cancelled) return;
        if (error || !data) {
          clearChatId();
          router.replace("/dashboard/chat/new");
        }
      } catch {
        // Network/client init failure — leave the surface; do not clear.
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [conversationId, clearChatId, router]);

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
      conversationId={conversationId}
      initialContext={initialContext}
      contextPending={contextLoading}
    />
  );
}
