import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { lookupConversationForPath } from "@/server/lookup-conversation-for-path";
import { validateContextPath } from "@/server/validate-context-path";
import { withUserRateLimit } from "@/server/with-user-rate-limit";

async function getHandler(req: Request) {
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
    // Helper already mirrored to Sentry; thread-info's public contract
    // degrades to messageCount=0 rather than exposing the error.
    return NextResponse.json({ messageCount: 0 });
  }
  return NextResponse.json({
    messageCount: result.row?.message_count ?? 0,
  });
}

export const GET = withUserRateLimit(getHandler, {
  perMinute: 60,
  feature: "kb-chat.thread-info",
});
