// In-process MCP tools for conversation thread discovery + list + archive.
// Mirrors the `kb-share-tools.ts` factoring pattern so each tool's wiring
// has a single call site and its handler can be unit tested in isolation.

import { tool } from "@anthropic-ai/claude-agent-sdk";
import { z } from "zod/v4";
import { createServiceClient } from "@/lib/supabase/service";
import { getCurrentRepoUrl } from "@/server/current-repo-url";
import { DOMAIN_LEADERS } from "@/server/domain-leaders";
import { STATUS_LABELS } from "@/lib/types";
import {
  lookupConversationForPath,
  type LookupConversationResult,
} from "@/server/lookup-conversation-for-path";
import { validateContextPath } from "@/server/validate-context-path";

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

// Shared "disconnected" response — short-circuits every tool when the
// authenticated user has no currently-connected repo (users.repo_url IS NULL).
// Agents parse `code` to decide whether to prompt reconnect.
function disconnectedResponse(): ToolTextResponse {
  return textResponse(
    { error: "disconnected", code: "no_repo_connected" },
    true,
  );
}

// Enum inputs are rebuilt from the canonical types so tool validation
// cannot drift from UI validation. Bumping `STATUS_LABELS` or
// `DOMAIN_LEADERS` automatically widens the schemas here.
const STATUS_VALUES = Object.keys(STATUS_LABELS) as Array<
  keyof typeof STATUS_LABELS
>;
const DOMAIN_LEADER_IDS = DOMAIN_LEADERS.map((l) => l.id);

// Default + cap for `conversations_list` matches `useConversations` in
// `hooks/use-conversations.ts` — agents and UI see the same page size.
const LIST_LIMIT_DEFAULT = 50;
const LIST_LIMIT_MAX = 50;

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
        "Scoped to the user's currently connected repository: a null " +
        "response on a disconnected workspace does NOT mean no prior thread " +
        "exists for this path — orphaned threads from a previously " +
        "connected repo reappear only after reconnecting that exact URL. " +
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

        const repoUrl = await getCurrentRepoUrl(userId);
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
    tool(
      "conversations_list",
      "List the authenticated user's conversations for the currently " +
        "connected repository, mirroring the Command Center surface. " +
        "Optional filters: statusFilter (one of waiting_for_user, active, " +
        "completed, failed), domainLeader (one of the domain leader ids, " +
        "or 'general' to filter domain_leader IS NULL), archived " +
        "(boolean — defaults to false). Default page size is 50, capped " +
        "at 50. Returns an array of { id, status, domain_leader, " +
        "last_active, created_at, archived_at }. " +
        "When the user has no connected repository, returns the typed " +
        "disconnected error (see conversations_lookup description).",
      {
        statusFilter: z
          .enum(STATUS_VALUES as [string, ...string[]])
          .optional(),
        domainLeader: z
          .union([
            z.enum(DOMAIN_LEADER_IDS as [string, ...string[]]),
            z.literal("general"),
          ])
          .nullable()
          .optional(),
        archived: z.boolean().optional().default(false),
        limit: z
          .number()
          .int()
          .min(1)
          .max(LIST_LIMIT_MAX)
          .optional()
          .default(LIST_LIMIT_DEFAULT),
      },
      async (args) => {
        const repoUrl = await getCurrentRepoUrl(userId);
        if (!repoUrl) return disconnectedResponse();

        const supabase = createServiceClient();
        let query = supabase
          .from("conversations")
          .select(
            "id, status, domain_leader, last_active, created_at, archived_at",
          )
          .eq("user_id", userId)
          .eq("repo_url", repoUrl);

        if (args.archived) {
          query = query.not("archived_at", "is", null);
        } else {
          query = query.is("archived_at", null);
        }

        if (args.statusFilter) {
          query = query.eq("status", args.statusFilter);
        }

        if (args.domainLeader === "general") {
          query = query.is("domain_leader", null);
        } else if (args.domainLeader) {
          query = query.eq("domain_leader", args.domainLeader);
        }

        // Zod already clamps `limit` to `[1, LIST_LIMIT_MAX]` with the
        // LIST_LIMIT_DEFAULT default in production. The `?? DEFAULT` guards
        // direct-handler invocations (e.g. unit tests that skip Zod parse).
        const { data, error } = await query
          .order("last_active", { ascending: false })
          .limit(args.limit ?? LIST_LIMIT_DEFAULT);

        if (error) {
          return textResponse(
            { error: "List failed", code: "list_failed" },
            true,
          );
        }

        return textResponse(data ?? []);
      },
    ),
    tool(
      "conversation_archive",
      "Archive a conversation by id, scoped to the authenticated user and " +
        "the currently connected repository. The UPDATE WHERE clause " +
        "pins id, user_id, AND repo_url — a cached id from a different " +
        "repo or user fails closed as 'not found' rather than leaking " +
        "existence. Returns { id, archived_at } on success; isError " +
        "with code 'not_found' when 0 rows match; typed disconnected " +
        "error when the user has no connected repository.",
      { conversationId: z.string().uuid() },
      async (args) => {
        const repoUrl = await getCurrentRepoUrl(userId);
        if (!repoUrl) return disconnectedResponse();

        const supabase = createServiceClient();
        const nowIso = new Date().toISOString();
        const { data, error } = await supabase
          .from("conversations")
          .update({ archived_at: nowIso })
          .eq("id", args.conversationId)
          .eq("user_id", userId)
          .eq("repo_url", repoUrl)
          .select("id, archived_at");

        if (error) {
          return textResponse(
            { error: "Archive failed", code: "archive_failed" },
            true,
          );
        }
        if (!data || data.length === 0) {
          return textResponse(
            { error: "Not found", code: "not_found" },
            true,
          );
        }
        return textResponse(data[0]);
      },
    ),
    tool(
      "conversation_unarchive",
      "Unarchive a conversation by id, scoped to the authenticated user " +
        "and the currently connected repository. Same three-column WHERE " +
        "backstop as conversation_archive — cross-repo or cross-user " +
        "cached ids fail closed as 'not found'. Returns { id, archived_at } " +
        "(archived_at will be null on success).",
      { conversationId: z.string().uuid() },
      async (args) => {
        const repoUrl = await getCurrentRepoUrl(userId);
        if (!repoUrl) return disconnectedResponse();

        const supabase = createServiceClient();
        const { data, error } = await supabase
          .from("conversations")
          .update({ archived_at: null })
          .eq("id", args.conversationId)
          .eq("user_id", userId)
          .eq("repo_url", repoUrl)
          .select("id, archived_at");

        if (error) {
          return textResponse(
            { error: "Unarchive failed", code: "unarchive_failed" },
            true,
          );
        }
        if (!data || data.length === 0) {
          return textResponse(
            { error: "Not found", code: "not_found" },
            true,
          );
        }
        return textResponse(data[0]);
      },
    ),
    tool(
      "conversation_update_status",
      "Update a conversation's status by id, mirroring the Command Center " +
        "status-update action. Status must be one of the canonical " +
        "ConversationStatus values (waiting_for_user, active, completed, " +
        "failed). Same three-column WHERE backstop as conversation_archive " +
        "— cross-repo or cross-user cached ids fail closed as 'not found'. " +
        "Returns { id, status } on success; isError with code 'not_found' " +
        "when 0 rows match; typed disconnected error when the user has no " +
        "connected repository.",
      {
        conversationId: z.string().uuid(),
        status: z.enum(STATUS_VALUES as [string, ...string[]]),
      },
      async (args) => {
        const repoUrl = await getCurrentRepoUrl(userId);
        if (!repoUrl) return disconnectedResponse();

        const supabase = createServiceClient();
        const { data, error } = await supabase
          .from("conversations")
          .update({ status: args.status })
          .eq("id", args.conversationId)
          .eq("user_id", userId)
          .eq("repo_url", repoUrl)
          .select("id, status");

        if (error) {
          return textResponse(
            { error: "Status update failed", code: "update_failed" },
            true,
          );
        }
        if (!data || data.length === 0) {
          return textResponse(
            { error: "Not found", code: "not_found" },
            true,
          );
        }
        return textResponse(data[0]);
      },
    ),
  ];
}
