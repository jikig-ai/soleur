"use client";

/**
 * Nav-rail position resume (#4826) — client persist/restore API.
 *
 * Workspace-gated: no read/write when `useActiveRepo` has not yielded a
 * workspaceId (sticky href stays section root). All I/O goes through
 * `safeSession` (SSR-safe, swallows quota/SecurityError).
 *
 * Expanded seed is ONE-SHOT per KB segment mount — callers that seed
 * `expanded` from `readExpanded()` must latch with a ref so later user
 * collapses are not overwritten by re-reads (Rule 8 / plan Phase 2).
 *
 * Never persists `"new"` as a conversation id. Sanitize-on-read for paths.
 */

import { useCallback, useEffect, useState } from "react";
import { usePathname } from "next/navigation";
import { useActiveRepo } from "@/hooks/use-active-repo";
import { safeSession } from "@/lib/safe-session";
import {
  resumeKey,
  kbPathFromPathname,
  chatIdFromPathname,
  sanitizeKbRelativePath,
  kbEntryHrefFromStored,
  chatEntryIdFromStored,
  parseExpanded,
  serializeExpanded,
  parseScrollTop,
} from "@/lib/nav-resume";

const KB_ROOT = "/dashboard/kb";
const CHAT_ROOT = "/dashboard/chat";

export interface NavResumeApi {
  workspaceId: string | null;
  /** Sticky main-nav Knowledge Base href (root until workspace + stored path). */
  getKbEntryHref: () => string;
  /** Bare-chat entry href (sticky conversation when known). */
  getChatEntryHref: () => string;
  readExpanded: () => string[];
  writeExpanded: (paths: Iterable<string>) => void;
  readScrollTop: () => number | null;
  writeScrollTop: (n: number) => void;
  clearKbPath: () => void;
  clearChatId: () => void;
  /** Last resumeable chat id for bare `/dashboard/chat` client resume. */
  readChatId: () => string | null;
}

export function useNavResume(): NavResumeApi {
  const pathname = usePathname() ?? "";
  const { data } = useActiveRepo();
  const workspaceId = data?.workspaceId ?? null;

  // Hydrate sticky KB href after mount (matches useSidebarCollapse pattern).
  const [kbEntryHref, setKbEntryHref] = useState(KB_ROOT);
  const [chatEntryHref, setChatEntryHref] = useState(CHAT_ROOT);

  // Persist KB path + hydrate sticky href on pathname / workspace change.
  useEffect(() => {
    if (!workspaceId) {
      setKbEntryHref(KB_ROOT);
      return;
    }
    const extracted = kbPathFromPathname(pathname);
    const safe = sanitizeKbRelativePath(extracted);
    if (safe) {
      safeSession(resumeKey(workspaceId, "kb", "path"), safe);
      setKbEntryHref(kbEntryHrefFromStored(safe));
      return;
    }
    const stored = safeSession(resumeKey(workspaceId, "kb", "path"));
    setKbEntryHref(kbEntryHrefFromStored(stored));
  }, [pathname, workspaceId]);

  // Persist chat id (never "new") + hydrate sticky chat entry href.
  useEffect(() => {
    if (!workspaceId) {
      setChatEntryHref(CHAT_ROOT);
      return;
    }
    const id = chatIdFromPathname(pathname);
    if (id) {
      safeSession(resumeKey(workspaceId, "chat", "id"), id);
      setChatEntryHref(`/dashboard/chat/${id}`);
      return;
    }
    const stored = chatEntryIdFromStored(
      safeSession(resumeKey(workspaceId, "chat", "id")),
    );
    setChatEntryHref(stored ? `/dashboard/chat/${stored}` : CHAT_ROOT);
  }, [pathname, workspaceId]);

  const getKbEntryHref = useCallback(() => kbEntryHref, [kbEntryHref]);
  const getChatEntryHref = useCallback(() => chatEntryHref, [chatEntryHref]);

  const readExpanded = useCallback((): string[] => {
    if (!workspaceId) return [];
    return parseExpanded(
      safeSession(resumeKey(workspaceId, "kb", "expanded")),
    );
  }, [workspaceId]);

  const writeExpanded = useCallback(
    (paths: Iterable<string>) => {
      if (!workspaceId) return;
      safeSession(
        resumeKey(workspaceId, "kb", "expanded"),
        serializeExpanded(paths),
      );
    },
    [workspaceId],
  );

  const readScrollTop = useCallback((): number | null => {
    if (!workspaceId) return null;
    return parseScrollTop(
      safeSession(resumeKey(workspaceId, "kb", "scrollTop")),
    );
  }, [workspaceId]);

  const writeScrollTop = useCallback(
    (n: number) => {
      if (!workspaceId) return;
      if (!Number.isFinite(n) || n < 0) return;
      safeSession(
        resumeKey(workspaceId, "kb", "scrollTop"),
        String(Math.floor(n)),
      );
    },
    [workspaceId],
  );

  const clearKbPath = useCallback(() => {
    if (!workspaceId) return;
    safeSession(resumeKey(workspaceId, "kb", "path"), null);
    setKbEntryHref(KB_ROOT);
  }, [workspaceId]);

  const clearChatId = useCallback(() => {
    if (!workspaceId) return;
    safeSession(resumeKey(workspaceId, "chat", "id"), null);
    setChatEntryHref(CHAT_ROOT);
  }, [workspaceId]);

  const readChatId = useCallback((): string | null => {
    if (!workspaceId) return null;
    return chatEntryIdFromStored(
      safeSession(resumeKey(workspaceId, "chat", "id")),
    );
  }, [workspaceId]);

  return {
    workspaceId,
    getKbEntryHref,
    getChatEntryHref,
    readExpanded,
    writeExpanded,
    readScrollTop,
    writeScrollTop,
    clearKbPath,
    clearChatId,
    readChatId,
  };
}
