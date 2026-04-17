import path from "node:path";
import { NextResponse } from "next/server";
import { createClient, createServiceClient } from "@/lib/supabase/server";
import logger from "@/server/logger";
import {
  readContent,
  KbNotFoundError,
  KbAccessDeniedError,
  KbFileTooLargeError,
  KbValidationError,
} from "@/server/kb-reader";
import { serveKbFile, serveBinary } from "@/server/kb-serve";

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

  return serveKbFile(kbRoot, relativePath, {
    request,
    onMarkdown: async (root, rel) => {
      try {
        const result = await readContent(root, rel);
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

  // Binary file serving — owner route streams unconditionally (no hash
  // gate). The share route adds a content-hash verdict cache on top of
  // the same helpers.
  try {
    const meta = await validateBinaryFile(kbRoot, relativePath);
    return await buildBinaryResponse(meta, request);
  } catch (err) {
    if (err instanceof KbAccessDeniedError) {
      return NextResponse.json({ error: "Access denied" }, { status: 403 });
    }
    if (err instanceof KbNotFoundError) {
      return NextResponse.json({ error: "File not found" }, { status: 404 });
    }
    if (err instanceof KbFileTooLargeError) {
      return NextResponse.json({ error: err.message }, { status: 413 });
    }
    if (err instanceof BinaryOpenError) {
      logger.warn(
        { err: err.message, code: err.code, path: relativePath },
        "kb/content: open failed on serve",
      );
      return NextResponse.json({ error: err.message }, { status: err.status });
    }
    logger.error({ err, path: relativePath }, "kb/content: unexpected error");
    return NextResponse.json(
      { error: "An unexpected error occurred" },
      { status: 500 },
    );
  }
}
