import { NextResponse } from "next/server";
import { createClient, createServiceClient } from "@/lib/supabase/server";
import { validateOrigin, rejectCsrf } from "@/lib/auth/validate-origin";
import { isPathInWorkspace } from "@/server/sandbox";
import { githubApiGet, githubApiPost } from "@/server/github-api";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import path from "path";
import logger from "@/server/logger";
import * as Sentry from "@sentry/nextjs";

const execFileAsync = promisify(execFile);

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const ALLOWED_EXTENSIONS = new Set([
  "png", "jpg", "jpeg", "gif", "webp", "pdf", "csv", "txt", "docx",
]);
const WINDOWS_RESERVED = new Set([
  "con", "prn", "aux", "nul",
  "com1", "com2", "com3", "com4", "com5", "com6", "com7", "com8", "com9",
  "lpt1", "lpt2", "lpt3", "lpt4", "lpt5", "lpt6", "lpt7", "lpt8", "lpt9",
]);
const MAX_FILENAME_BYTES = 255;
const MAX_FILE_SIZE = 20 * 1024 * 1024; // 20 MB

// ---------------------------------------------------------------------------
// Filename sanitization
// ---------------------------------------------------------------------------

function sanitizeFilename(
  filename: string,
): { valid: boolean; sanitized: string; error?: string } {
  // Strip control chars (0x00-0x1F, 0x7F)
  const sanitized = filename.replace(/[\x00-\x1f\x7f]/g, "");

  if (!sanitized || sanitized.trim() === "") {
    return { valid: false, sanitized, error: "Empty filename" };
  }

  if (sanitized.startsWith(".")) {
    return { valid: false, sanitized, error: "Filename cannot start with a dot" };
  }

  if (new TextEncoder().encode(sanitized).length > MAX_FILENAME_BYTES) {
    return { valid: false, sanitized, error: "Filename too long" };
  }

  const nameWithoutExt = sanitized.replace(/\.[^.]+$/, "").toLowerCase();
  if (WINDOWS_RESERVED.has(nameWithoutExt)) {
    return { valid: false, sanitized, error: "Reserved filename" };
  }

  return { valid: true, sanitized };
}

// ---------------------------------------------------------------------------
// Route handler
// ---------------------------------------------------------------------------

export async function POST(request: Request) {
  // CSRF validation
  const { valid: originValid, origin } = validateOrigin(request);
  if (!originValid) return rejectCsrf("api/kb/upload", origin);

  // Authentication
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  // Fetch workspace data
  const serviceClient = createServiceClient();
  const { data: userData } = await serviceClient
    .from("users")
    .select("workspace_path, workspace_status, repo_url, github_installation_id")
    .eq("id", user.id)
    .single();

  if (!userData?.workspace_path || userData.workspace_status !== "ready") {
    return NextResponse.json({ error: "Workspace not ready" }, { status: 503 });
  }

  if (!userData.repo_url || !userData.github_installation_id) {
    return NextResponse.json({ error: "No repository connected" }, { status: 400 });
  }

  // Parse FormData
  let formData: FormData;
  try {
    formData = await request.formData();
  } catch {
    return NextResponse.json({ error: "Invalid form data" }, { status: 400 });
  }

  const file = formData.get("file") as File | null;
  const targetDir = formData.get("targetDir") as string | null;
  const sha = formData.get("sha") as string | null;

  if (!file || !targetDir) {
    return NextResponse.json(
      { error: "Missing file or targetDir" },
      { status: 400 },
    );
  }

  // Validate filename
  const { valid: nameValid, sanitized: sanitizedName, error: nameError } =
    sanitizeFilename(file.name);
  if (!nameValid) {
    return NextResponse.json(
      { error: nameError || "Invalid filename" },
      { status: 400 },
    );
  }

  // Validate extension
  const ext = sanitizedName.split(".").pop()?.toLowerCase();
  if (!ext || !ALLOWED_EXTENSIONS.has(ext)) {
    return NextResponse.json(
      { error: `Unsupported file type: .${ext || "unknown"}` },
      { status: 415 },
    );
  }

  // Validate file size
  if (file.size > MAX_FILE_SIZE) {
    return NextResponse.json(
      { error: `File exceeds maximum size of ${MAX_FILE_SIZE / 1024 / 1024}MB` },
      { status: 413 },
    );
  }

  // Validate targetDir: reject null bytes
  if (targetDir.includes("\0")) {
    return NextResponse.json(
      { error: "Invalid target directory" },
      { status: 400 },
    );
  }

  // Validate targetDir: path traversal check
  const kbRoot = path.join(userData.workspace_path, "knowledge-base");
  const fullTargetPath = path.join(kbRoot, targetDir, sanitizedName);
  if (!isPathInWorkspace(fullTargetPath, kbRoot)) {
    return NextResponse.json(
      { error: "Invalid target directory" },
      { status: 400 },
    );
  }

  // Parse owner/repo from repo_url (format: "https://github.com/owner/repo")
  const repoUrlParts = userData.repo_url.replace(/\.git$/, "").split("/");
  const repo = repoUrlParts.pop()!;
  const owner = repoUrlParts.pop()!;

  if (!owner || !repo) {
    return NextResponse.json(
      { error: "Invalid repository URL" },
      { status: 500 },
    );
  }

  const filePath = `knowledge-base/${targetDir}/${sanitizedName}`;

  try {
    // If no sha provided, check if file exists (duplicate detection)
    if (!sha) {
      try {
        const existing = await githubApiGet<{ sha: string }>(
          userData.github_installation_id,
          `/repos/${owner}/${repo}/contents/${filePath}`,
        );
        // File exists — return 409 with sha for client to use for overwrite
        return NextResponse.json(
          {
            error: "File already exists",
            code: "DUPLICATE",
            sha: existing.sha,
            path: filePath,
          },
          { status: 409 },
        );
      } catch (err) {
        // 404 is expected (file doesn't exist) — continue with upload
        const errMsg = err instanceof Error ? err.message : "";
        if (!errMsg.includes("404")) {
          throw err; // Re-throw non-404 errors
        }
      }
    }

    // Base64 encode file content
    const base64Content = Buffer.from(await file.arrayBuffer()).toString("base64");

    // Upload via GitHub Contents API (PUT)
    const result = await githubApiPost<{
      content: { sha: string; path: string };
      commit: { sha: string };
    }>(
      userData.github_installation_id,
      `/repos/${owner}/${repo}/contents/${filePath}`,
      {
        message: `Upload ${sanitizedName} via Soleur`,
        content: base64Content,
        ...(sha ? { sha } : {}),
      },
      "PUT",
    );

    // Workspace sync (best-effort — file is committed to GitHub)
    try {
      await execFileAsync("git", ["pull", "--ff-only"], {
        cwd: userData.workspace_path,
        timeout: 30000,
      });
    } catch (syncError) {
      logger.error(
        { err: syncError, userId: user.id },
        "kb/upload: workspace sync failed after successful commit",
      );
      Sentry.captureException(syncError);
      return NextResponse.json(
        {
          error: "File committed to GitHub but workspace sync failed. Try refreshing.",
          code: "SYNC_FAILED",
        },
        { status: 500 },
      );
    }

    logger.info(
      { event: "kb_upload", userId: user.id, path: filePath },
      "kb/upload: file uploaded successfully",
    );

    return NextResponse.json(
      {
        path: filePath,
        sha: result!.content.sha,
        commitSha: result!.commit.sha,
      },
      { status: 201 },
    );
  } catch (error) {
    Sentry.captureException(error);

    if (error instanceof Error && error.message.includes("GitHub API")) {
      logger.error(
        { err: error, userId: user.id, path: filePath },
        "kb/upload: GitHub API error",
      );
      return NextResponse.json(
        {
          error: error.message,
          code: "GITHUB_API_ERROR",
        },
        { status: 502 },
      );
    }

    logger.error(
      { err: error, userId: user.id },
      "kb/upload: unexpected error",
    );
    return NextResponse.json(
      { error: "Internal server error" },
      { status: 500 },
    );
  }
}
