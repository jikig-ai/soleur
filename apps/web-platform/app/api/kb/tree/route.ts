import { NextResponse } from "next/server";
import path from "path";
import type { User } from "@supabase/supabase-js";
import { createServiceClient } from "@/lib/supabase/server";
import logger from "@/server/logger";
import { buildTree } from "@/server/kb-reader";
import { withUserRateLimit } from "@/server/with-user-rate-limit";

async function getHandler(_req: Request, user: User) {
  const serviceClient = createServiceClient();
  const { data: userData, error: fetchError } = await serviceClient
    .from("users")
    .select("workspace_path, workspace_status, repo_status")
    .eq("id", user.id)
    .single();

  if (fetchError || !userData?.workspace_path || userData.repo_status === "not_connected") {
    return NextResponse.json({ error: "Workspace not found" }, { status: 404 });
  }

  if (userData.workspace_status !== "ready") {
    return NextResponse.json({ error: "Workspace not ready" }, { status: 503 });
  }

  try {
    const kbRoot = path.join(userData.workspace_path, "knowledge-base");
    const tree = await buildTree(kbRoot);
    return NextResponse.json({ tree });
  } catch (err) {
    logger.error({ err }, "kb/tree: unexpected error");
    return NextResponse.json(
      { error: "An unexpected error occurred" },
      { status: 500 },
    );
  }
}

export const GET = withUserRateLimit(getHandler, {
  perMinute: 60,
  feature: "kb.tree",
});
