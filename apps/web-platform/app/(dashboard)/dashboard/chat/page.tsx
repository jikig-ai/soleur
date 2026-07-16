"use client";

/**
 * Bare `/dashboard/chat` entry — client resume (#4826).
 *
 * Previously a server `redirect("/dashboard/chat/new")` stub so bare chat
 * never 404'd. Server redirects cannot read sessionStorage, so resume of
 * the last conversation must happen here on the client.
 *
 * Rules:
 * - Wait for workspaceId (or treat as no-resume if still null after settle).
 * - Never redirect away from `/dashboard/chat/new` (that is a different route).
 * - Never restore `"new"` as an id (sanitize helpers reject it).
 * - Stale/missing id → land on `/new` and clear the sticky key.
 */

import { useEffect, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { useNavResume } from "@/hooks/use-nav-resume";

export default function ChatIndexPage() {
  const router = useRouter();
  const { workspaceId, readChatId, clearChatId } = useNavResume();
  const [status, setStatus] = useState<"waiting" | "opening">("waiting");
  const replacedRef = useRef(false);

  useEffect(() => {
    if (replacedRef.current) return;

    // Wait until active-repo has resolved at least once. When workspaceId is
    // still null we show the opening shell; a short settle window avoids
    // writing under the wrong workspace, then we fall through to /new.
    if (workspaceId == null) {
      const t = window.setTimeout(() => {
        if (replacedRef.current) return;
        replacedRef.current = true;
        setStatus("opening");
        router.replace("/dashboard/chat/new");
      }, 1500);
      return () => window.clearTimeout(t);
    }

    const id = readChatId();
    replacedRef.current = true;
    setStatus("opening");
    if (id) {
      // Optimistic resume; conversation surface handles missing rows.
      // Soft-fail: if the route 404s, a sibling clear path runs on not-found.
      router.replace(`/dashboard/chat/${id}`);
    } else {
      clearChatId();
      router.replace("/dashboard/chat/new");
    }
  }, [workspaceId, readChatId, clearChatId, router]);

  return (
    <div
      data-testid="chat-index-resume"
      className="flex h-full min-h-[40vh] items-center justify-center px-6 text-sm text-soleur-text-muted"
      role="status"
      aria-live="polite"
    >
      {status === "waiting" ? "Opening conversation…" : "Opening conversation…"}
    </div>
  );
}
