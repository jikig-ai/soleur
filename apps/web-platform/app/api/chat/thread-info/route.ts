import { NextResponse } from "next/server";
import type { User } from "@supabase/supabase-js";
import { createServiceClient } from "@/lib/supabase/service";
import { lookupConversationForPath } from "@/server/lookup-conversation-for-path";
import { validateContextPath } from "@/server/validate-context-path";
import { withUserRateLimit } from "@/server/with-user-rate-limit";

async function getHandler(req: Request, user: User) {
  const url = new URL(req.url);
  const contextPath = validateContextPath(url.searchParams.get("contextPath"));
  if (!contextPath) {
    return NextResponse.json({ error: "Invalid contextPath" }, { status: 400 });
  }

  // Scope the lookup to the user's CURRENT repo_url — see plan
  // 2026-04-22-fix-command-center-stale-conversations-after-repo-swap-plan.md.
  const service = createServiceClient();
  const { data: userRow } = await service
    .from("users")
    .select("repo_url")
    .eq("id", user.id)
    .maybeSingle();
  const repoUrl = (userRow?.repo_url as string | null | undefined) ?? null;

  const result = await lookupConversationForPath(user.id, contextPath, repoUrl);
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
