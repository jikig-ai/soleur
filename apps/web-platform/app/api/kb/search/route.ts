import { NextResponse } from "next/server";
import path from "path";
import { createClient, createServiceClient } from "@/lib/supabase/server";
import logger from "@/server/logger";
import { searchKb, KbValidationError } from "@/server/kb-reader";
import { withUserRateLimit } from "@/server/with-user-rate-limit";

async function getHandler(request: Request) {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const serviceClient = createServiceClient();
  const { data: userData, error: fetchError } = await serviceClient
    .from("users")
    .select("workspace_path, workspace_status")
    .eq("id", user.id)
    .single();

  if (fetchError || !userData?.workspace_path) {
    return NextResponse.json({ error: "Workspace not found" }, { status: 404 });
  }

  if (userData.workspace_status !== "ready") {
    return NextResponse.json({ error: "Workspace not ready" }, { status: 503 });
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
    const kbRoot = path.join(userData.workspace_path, "knowledge-base");
    const result = await searchKb(kbRoot, query);
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
