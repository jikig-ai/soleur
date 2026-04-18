import { NextResponse } from "next/server";
import type { User } from "@supabase/supabase-js";
import { lookupConversationForPath } from "@/server/lookup-conversation-for-path";
import { validateContextPath } from "@/server/validate-context-path";
import { withUserRateLimit } from "@/server/with-user-rate-limit";

/**
 * GET /api/conversations?contextPath=<path>
 *
 * Looks up the existing conversation bound to `(user_id, context_path)`.
 * Returns the full row shape when present, `null` otherwise. Non-WS agents
 * use this to discover whether a thread exists before resuming.
 *
 * Wire shape is camelCase to match the sibling `/api/chat/thread-info`
 * endpoint; DB columns remain snake_case internally (helper maps).
 *
 * Auth is performed by `withUserRateLimit`; the wrapper 401s unauthenticated
 * callers before this handler runs and passes the authenticated `user`.
 *
 * Responses:
 *   200 + JSON `{ conversationId, contextPath, lastActive, messageCount }` when hit
 *   200 + JSON `null` when no row matches (not an error)
 *   400 when `contextPath` is missing or invalid
 *   401 when unauthenticated (emitted by wrapper)
 *   429 when the authenticated user exceeds 60 req/min (emitted by wrapper)
 *   500 on lookup error (mirrored to Sentry via `reportSilentFallback`)
 */
async function getHandler(req: Request, user: User) {
  const url = new URL(req.url);
  const contextPath = validateContextPath(url.searchParams.get("contextPath"));
  if (!contextPath) {
    return NextResponse.json({ error: "Invalid contextPath" }, { status: 400 });
  }

  const result = await lookupConversationForPath(user.id, contextPath);
  if (!result.ok) {
    return NextResponse.json({ error: "Internal error" }, { status: 500 });
  }

  if (result.row === null) {
    return NextResponse.json(null);
  }

  return NextResponse.json({
    conversationId: result.row.id,
    contextPath: result.row.context_path,
    lastActive: result.row.last_active,
    messageCount: result.row.message_count,
  });
}

export const GET = withUserRateLimit(getHandler, {
  perMinute: 60,
  feature: "kb-chat.conversations",
});
