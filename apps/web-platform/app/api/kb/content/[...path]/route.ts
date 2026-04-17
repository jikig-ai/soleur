import path from "node:path";
import { NextResponse } from "next/server";
import { createClient, createServiceClient } from "@/lib/supabase/server";
import logger from "@/server/logger";
import {
  readContent,
  KbNotFoundError,
  KbAccessDeniedError,
  KbValidationError,
} from "@/server/kb-reader";
import { readBinaryFile, buildBinaryResponse } from "@/server/kb-binary-response";

export async function GET(
  request: Request,
  { params }: { params: Promise<{ path: string[] }> },
) {
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

  const { path: pathSegments } = await params;
  const relativePath = pathSegments.join("/");

  if (!relativePath) {
    return NextResponse.json({ error: "File not found" }, { status: 404 });
  }

  const kbRoot = path.join(userData.workspace_path, "knowledge-base");
  const ext = path.extname(relativePath).toLowerCase();

  // Fork: .md (or no extension) → readContent, non-.md → binary serving
  if (ext === ".md" || ext === "") {
    try {
      const result = await readContent(kbRoot, relativePath);
      return NextResponse.json(result);
    } catch (err) {
      if (err instanceof KbAccessDeniedError) {
        return NextResponse.json({ error: "Access denied" }, { status: 403 });
      }
      if (err instanceof KbNotFoundError) {
        return NextResponse.json({ error: "File not found" }, { status: 404 });
      }
      if (err instanceof KbValidationError) {
        return NextResponse.json({ error: err.message }, { status: 400 });
      }
      logger.error({ err }, "kb/content: unexpected error");
      return NextResponse.json(
        { error: "An unexpected error occurred" },
        { status: 500 },
      );
    }
  }

  // Binary file serving — delegate to shared helper so owner and public
  // (/api/shared/[token]) routes share one hardened implementation.
  const result = await readBinaryFile(kbRoot, relativePath);
  if (!result.ok) {
    return NextResponse.json({ error: result.error }, { status: result.status });
  }
  return buildBinaryResponse(result, request);
}
