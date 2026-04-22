// In-process MCP tool for KB-chat thread discovery. Mirrors the
// `kb-share-tools.ts` factoring pattern so the tool's wiring has a single
// call site and its handler can be unit tested in isolation.
//
// Currently exposes one tool (`conversations_lookup`). The P3 siblings
// (`conversations_list`, `conversation_archive`) are deferred to a follow-
// up issue because they require new HTTP endpoints out of scope.

import { tool } from "@anthropic-ai/claude-agent-sdk";
import { z } from "zod/v4";
import { createServiceClient } from "@/lib/supabase/service";
import {
  lookupConversationForPath,
  type LookupConversationResult,
} from "@/server/lookup-conversation-for-path";
import { validateContextPath } from "@/server/validate-context-path";

interface BuildConversationsToolsOpts {
  /** Captured in closure — prevents cross-user lookups. */
  userId: string;
}

/**
 * Read the user's CURRENT repo_url so the lookup is scoped to the repository
 * they have connected right now — see plan
 * 2026-04-22-fix-command-center-stale-conversations-after-repo-swap-plan.md.
 */
async function currentRepoUrl(userId: string): Promise<string | null> {
  const service = createServiceClient();
  const { data } = await service
    .from("users")
    .select("repo_url")
    .eq("id", userId)
    .maybeSingle();
  return (data?.repo_url as string | null | undefined) ?? null;
}

type ToolTextResponse = {
  content: Array<{ type: "text"; text: string }>;
  isError?: true;
};

function textResponse(payload: unknown, isError = false): ToolTextResponse {
  const body: ToolTextResponse = {
    content: [{ type: "text", text: JSON.stringify(payload) }],
  };
  if (isError) body.isError = true;
  return body;
}

export function buildConversationsTools(opts: BuildConversationsToolsOpts) {
  const { userId } = opts;
  return [
    tool(
      "conversations_lookup",
      "Look up the existing KB-chat conversation thread bound to a " +
        "knowledge-base document. Use this before starting a new thread " +
        "to check whether an existing one can be resumed. " +
        "Input: contextPath (the KB file path, e.g., " +
        "'knowledge-base/product/roadmap.md'). " +
        "Returns { conversationId, contextPath, lastActive, messageCount } " +
        "when a thread exists, or null when no thread is bound to the path. " +
        "Does NOT return message bodies (threads are opaque from the agent's " +
        "perspective — use the UI to read them).",
      { contextPath: z.string() },
      async (args) => {
        // Mirror the HTTP-route validation — /api/conversations calls
        // validateContextPath before lookup, so the MCP path does the same.
        const validated = validateContextPath(args.contextPath);
        if (!validated) {
          return textResponse(
            { error: "Invalid contextPath", code: "invalid_context_path" },
            true,
          );
        }

        const repoUrl = await currentRepoUrl(userId);
        const result: LookupConversationResult =
          await lookupConversationForPath(userId, validated, repoUrl);
        if (!result.ok) {
          // Exhaustiveness check — adding a new error discriminant without
          // updating this wrapper fails tsc --noEmit. Mirrors the pattern
          // in `kb-share-tools.ts` per learning
          // 2026-04-10-discriminated-union-exhaustive-switch-miss.
          const _exhaustive: "lookup_failed" = result.error;
          void _exhaustive;
          return textResponse(
            { error: "Lookup failed", code: result.error },
            true,
          );
        }
        if (result.row === null) return textResponse(null);
        return textResponse({
          conversationId: result.row.id,
          contextPath: result.row.context_path,
          lastActive: result.row.last_active,
          messageCount: result.row.message_count,
        });
      },
    ),
  ];
}
