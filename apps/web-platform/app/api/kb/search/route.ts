import { NextResponse } from "next/server";
import type { User } from "@supabase/supabase-js";
import { createServiceClient } from "@/lib/supabase/server";
import logger from "@/server/logger";
import { searchKb, KbValidationError } from "@/server/kb-reader";
import { withUserRateLimit } from "@/server/with-user-rate-limit";
import { resolveActiveWorkspaceKbRoot } from "@/server/workspace-resolver";

async function getHandler(request: Request, user: User) {
  const serviceClient = createServiceClient();
  // ADR-044 (#4543): search the ACTIVE workspace's KB, not the caller's own
  // `users` row (an invited member's solo row is empty → 404).
  const access = await resolveActiveWorkspaceKbRoot(user.id, serviceClient);
  if (!access.ok) {
    return access.status === 404
      ? NextResponse.json({ error: "Workspace not found" }, { status: 404 })
      : NextResponse.json({ error: "Workspace not ready" }, { status: 503 });
  }

  const url = new URL(request.url);
  const query = url.searchParams.get("q");

  if (!query) {
    return NextResponse.json(
      { error: "Search query is required" },
      { status: 400 },
    );
  }

  try {
    const result = await searchKb(access.kbRoot, query);
    return NextResponse.json({ query, ...result });
  } catch (err) {
    if (err instanceof KbValidationError) {
      return NextResponse.json({ error: err.message }, { status: 400 });
    }
    logger.error({ err }, "kb/search: unexpected error");
    return NextResponse.json(
      { error: "An unexpected error occurred" },
      { status: 500 },
    );
  }
}

export const GET = withUserRateLimit(getHandler, {
  perMinute: 60,
  feature: "kb.search",
});
