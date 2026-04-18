// In-process MCP tool for KB-chat thread discovery. Factored out of
// agent-runner.ts mirroring the kb-share-tools.ts precedent from PR #2497
// so the tool's wiring has a single call site and its handler can be unit
// tested in isolation.
//
// Currently exposes one tool (`conversations_lookup`). The P3 siblings
// (`conversations_list`, `conversation_archive`) are deferred to a follow-
// up issue because they require new HTTP endpoints out of scope.
//
// The handler delegates the full lookup lifecycle to
// server/lookup-conversation-for-path.ts — this module only translates the
// discriminated-union result into the platform-tool response shape.
// The MCP path intentionally does NOT route through the HTTP endpoint, so
// the `withUserRateLimit` wrapper on `/api/conversations` does not apply
// here; the agent-runner's per-user `query()` invocation is the rate-
// limiting boundary (one agent session ≈ one user).

import { tool } from "@anthropic-ai/claude-agent-sdk";
import { z } from "zod/v4";
import {
  lookupConversationForPath,
  type LookupConversationResult,
} from "@/server/lookup-conversation-for-path";

interface BuildConversationsToolsOpts {
  /** Captured in closure — prevents cross-user lookups. */
  userId: string;
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
        const result: LookupConversationResult =
          await lookupConversationForPath(userId, args.contextPath);
        if (!result.ok) {
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
