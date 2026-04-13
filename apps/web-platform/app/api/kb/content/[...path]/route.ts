import fs from "node:fs";
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
import { isPathInWorkspace } from "@/server/sandbox";

const CONTENT_TYPE_MAP: Record<string, string> = {
  ".png": "image/png",
  ".jpg": "image/jpeg",
  ".jpeg": "image/jpeg",
  ".gif": "image/gif",
  ".webp": "image/webp",
  ".pdf": "application/pdf",
  ".csv": "text/csv",
  ".txt": "text/plain",
  ".docx":
    "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
};

const ATTACHMENT_EXTENSIONS = new Set([".docx"]);

const MAX_BINARY_SIZE = 50 * 1024 * 1024; // 50 MB

export async function GET(
  _request: Request,
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

  // Binary file serving
  const fullPath = path.join(kbRoot, relativePath);

  // Path traversal check — boundary is kbRoot
  if (!isPathInWorkspace(fullPath, kbRoot)) {
    return NextResponse.json({ error: "Access denied" }, { status: 403 });
  }

  // Symlink check — reject symlinks to prevent escaping kbRoot
  let lstat: fs.Stats;
  try {
    lstat = await fs.promises.lstat(fullPath);
    if (lstat.isSymbolicLink()) {
      return NextResponse.json({ error: "Access denied" }, { status: 403 });
    }
  } catch {
    return NextResponse.json({ error: "File not found" }, { status: 404 });
  }

  // Size guard — prevent reading arbitrarily large files into memory
  if (lstat.size > MAX_BINARY_SIZE) {
    return NextResponse.json(
      { error: "File exceeds maximum size limit" },
      { status: 413 },
    );
  }

  // Read and serve file
  try {
    const buffer = await fs.promises.readFile(fullPath);
    const contentType = CONTENT_TYPE_MAP[ext] || "application/octet-stream";
    const disposition = ATTACHMENT_EXTENSIONS.has(ext)
      ? "attachment"
      : "inline";
    // Sanitize filename for Content-Disposition header (RFC 5987)
    const rawName = path.basename(relativePath);
    const safeName = rawName.replace(/["\r\n\\]/g, "_");

    return new Response(buffer, {
      headers: {
        "Content-Type": contentType,
        "Content-Disposition": `${disposition}; filename="${safeName}"`,
        "Content-Length": buffer.length.toString(),
        "X-Content-Type-Options": "nosniff",
        "Cache-Control": "private, max-age=60",
      },
    });
  } catch {
    return NextResponse.json({ error: "File not found" }, { status: 404 });
  }
}
