import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { lookupConversationForPath } from "@/server/lookup-conversation-for-path";
import { validateContextPath } from "@/server/validate-context-path";

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
 * Responses:
 *   200 + JSON `{ conversationId, contextPath, lastActive, messageCount }` when hit
 *   200 + JSON `null` when no row matches (not an error)
 *   400 when `contextPath` is missing or invalid
 *   401 when unauthenticated
 *   500 on lookup / count error (mirrored to Sentry via `reportSilentFallback`)
 */
export async function GET(req: Request) {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const url = new URL(req.url);
  const contextPath = validateContextPath(url.searchParams.get("contextPath"));
  if (!contextPath) {
    return NextResponse.json({ error: "Invalid contextPath" }, { status: 400 });
  }

  const result = await lookupConversationForPath(user.id, contextPath);
  if (!result.ok) {
    // Helper already mirrored to Sentry; surface 500 so external agents
    // don't retry indefinitely against a broken backend.
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
