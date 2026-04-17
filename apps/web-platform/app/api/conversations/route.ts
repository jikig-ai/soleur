import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { lookupConversationForPath } from "@/server/lookup-conversation-for-path";
import { reportSilentFallback } from "@/server/observability";

// Shared inline to avoid a sibling module; `validateContextPath` is also
// present in `thread-info/route.ts`. Kept inline here (not extracted) because
// the two routes are the only callers and each is <40 lines — premature
// helper extraction would add indirection without reuse.
const CONTEXT_PATH_MAX_LEN = 512;
const CONTEXT_PATH_PREFIX = "knowledge-base/";

function validateContextPath(v: string | null): string | null {
  if (!v || v.length === 0 || v.length > CONTEXT_PATH_MAX_LEN) return null;
  if (!v.startsWith(CONTEXT_PATH_PREFIX)) return null;
  if (v.includes("..") || v.includes("\0")) return null;
  const filename = v.split("/").pop() ?? "";
  if (filename.lastIndexOf(".") <= 0) return null;
  return v;
}

/**
 * GET /api/conversations?context_path=<path>
 *
 * Looks up the existing conversation bound to `(user_id, context_path)`.
 * Returns the full row shape when present, `null` otherwise. Non-WS agents
 * use this to discover whether a thread exists before resuming.
 *
 * Responses:
 *   200 + JSON `{ conversationId, context_path, last_active, message_count }` when hit
 *   200 + JSON `null` when no row matches (not an error)
 *   400 when `context_path` is missing or invalid
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
  const contextPath = validateContextPath(url.searchParams.get("context_path"));
  if (!contextPath) {
    return NextResponse.json({ error: "Invalid context_path" }, { status: 400 });
  }

  const result = await lookupConversationForPath(user.id, contextPath);
  if (!result.ok) {
    // Helper mirrored the underlying error; caller surfaces 500 so external
    // agents don't retry indefinitely against a broken backend.
    reportSilentFallback(null, {
      feature: "kb-chat",
      op: "conversations-lookup",
      message: `conversations lookup failed: ${result.error}`,
      extra: { contextPath },
    });
    return NextResponse.json({ error: "Internal error" }, { status: 500 });
  }

  if (result.row === null) {
    return NextResponse.json(null);
  }

  return NextResponse.json({
    conversationId: result.row.id,
    context_path: result.row.context_path,
    last_active: result.row.last_active,
    message_count: result.row.message_count,
  });
}
