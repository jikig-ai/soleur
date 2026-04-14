import { NextResponse } from "next/server";
import { createClient, createServiceClient } from "@/lib/supabase/server";
import { validateOrigin, rejectCsrf } from "@/lib/auth/validate-origin";
import { isPathInWorkspace } from "@/server/sandbox";
import { githubApiGet, githubApiPost, githubApiDelete } from "@/server/github-api";
import { generateInstallationToken, randomCredentialPath } from "@/server/github-app";
import { sanitizeFilename } from "@/server/kb-validation";
import { execFile } from "node:child_process";
import { writeFileSync, unlinkSync, promises as fs } from "node:fs";
import { promisify } from "node:util";
import path from "path";
import logger from "@/server/logger";
import * as Sentry from "@sentry/nextjs";

const execFileAsync = promisify(execFile);

export async function DELETE(
  request: Request,
  { params }: { params: Promise<{ path: string[] }> },
) {
  // CSRF validation
  const { valid: originValid, origin } = validateOrigin(request);
  if (!originValid) return rejectCsrf("api/kb/file", origin);

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

  // Extract and validate path
  const { path: pathSegments } = await params;
  const relativePath = pathSegments.join("/");

  if (!relativePath) {
    return NextResponse.json({ error: "File path required" }, { status: 400 });
  }

  // Null byte check
  if (relativePath.includes("\0")) {
    return NextResponse.json({ error: "Invalid path: null byte detected" }, { status: 400 });
  }

  // Extension check — only attachments are deletable, not markdown
  const ext = path.extname(relativePath).toLowerCase();
  if (ext === ".md") {
    return NextResponse.json(
      { error: "Markdown files cannot be deleted through this endpoint" },
      { status: 400 },
    );
  }

  // Path traversal check
  const kbRoot = path.join(userData.workspace_path, "knowledge-base");
  const fullPath = path.join(kbRoot, relativePath);
  if (!isPathInWorkspace(fullPath, kbRoot)) {
    return NextResponse.json({ error: "Invalid path" }, { status: 400 });
  }

  // Symlink check — skip if file doesn't exist locally (ENOENT)
  try {
    const stat = await fs.lstat(fullPath);
    if (stat.isSymbolicLink()) {
      return NextResponse.json({ error: "Access denied" }, { status: 403 });
    }
  } catch (err) {
    const code = (err as NodeJS.ErrnoException).code;
    if (code !== "ENOENT") {
      return NextResponse.json({ error: "Access denied" }, { status: 403 });
    }
    // ENOENT: file not on disk — skip symlink check, proceed with GitHub deletion
  }

  // Parse owner/repo from repo_url
  const repoUrlParts = userData.repo_url.replace(/\.git$/, "").split("/");
  const repo = repoUrlParts.pop()!;
  const owner = repoUrlParts.pop()!;

  if (!owner || !repo) {
    return NextResponse.json({ error: "Invalid repository URL" }, { status: 500 });
  }

  const filePath = `knowledge-base/${relativePath}`;

  try {
    // GET file SHA from GitHub Contents API
    let fileSha: string;
    try {
      const fileData = await githubApiGet<
        { sha: string; type: string } | Array<{ sha: string; type: string }>
      >(
        userData.github_installation_id,
        `/repos/${owner}/${repo}/contents/${filePath}`,
      );

      // GitHub returns an array for directories
      if (Array.isArray(fileData)) {
        return NextResponse.json(
          { error: "Cannot delete a directory" },
          { status: 400 },
        );
      }

      fileSha = fileData.sha;
    } catch (err) {
      const errMsg = err instanceof Error ? err.message : "";
      if (errMsg.includes("404")) {
        return NextResponse.json({ error: "File not found" }, { status: 404 });
      }
      throw err;
    }

    // DELETE file via GitHub Contents API
    try {
      const result = await githubApiDelete<{ commit: { sha: string } }>(
        userData.github_installation_id,
        `/repos/${owner}/${repo}/contents/${filePath}`,
        {
          message: `Delete ${path.basename(relativePath)} via Soleur`,
          sha: fileSha,
        },
      );

      // Workspace sync (best-effort — file is deleted from GitHub)
      let helperPath: string | null = null;
      try {
        const token = await generateInstallationToken(userData.github_installation_id);
        helperPath = randomCredentialPath();
        writeFileSync(
          helperPath,
          `#!/bin/sh\necho "username=x-access-token"\necho "password=${token}"`,
          { mode: 0o700 },
        );

        await execFileAsync(
          "git",
          ["-c", `credential.helper=!${helperPath}`, "pull", "--ff-only"],
          { cwd: userData.workspace_path, timeout: 30_000 },
        );
      } catch (syncError) {
        logger.error(
          { err: syncError, userId: user.id },
          "kb/delete: workspace sync failed after successful deletion",
        );
        Sentry.captureException(syncError);
        return NextResponse.json(
          {
            error: "File deleted from GitHub but workspace sync failed. Try refreshing.",
            code: "SYNC_FAILED",
            commitSha: result?.commit?.sha ?? null,
          },
          { status: 500 },
        );
      } finally {
        if (helperPath) {
          try { unlinkSync(helperPath); } catch { /* best-effort cleanup */ }
        }
      }

      logger.info(
        { event: "kb_delete", userId: user.id, path: filePath },
        "kb/delete: file deleted successfully",
      );

      return NextResponse.json(
        { commitSha: result?.commit?.sha ?? null },
        { status: 200 },
      );
    } catch (deleteErr) {
      const errMsg = deleteErr instanceof Error ? deleteErr.message : "";
      if (errMsg.includes("409")) {
        return NextResponse.json(
          {
            error: "File was modified since it was last read. Please refresh and try again.",
            code: "SHA_MISMATCH",
          },
          { status: 409 },
        );
      }
      throw deleteErr;
    }
  } catch (error) {
    Sentry.captureException(error);

    if (error instanceof Error && error.message.includes("GitHub API")) {
      logger.error(
        { err: error, userId: user.id, path: filePath },
        "kb/delete: GitHub API error",
      );
      return NextResponse.json(
        { error: error.message, code: "GITHUB_API_ERROR" },
        { status: 502 },
      );
    }

    logger.error(
      { err: error, userId: user.id },
      "kb/delete: unexpected error",
    );
    return NextResponse.json(
      { error: "Internal server error" },
      { status: 500 },
    );
  }
}

export async function PATCH(
  request: Request,
  { params }: { params: Promise<{ path: string[] }> },
) {
  // CSRF validation
  const { valid: originValid, origin } = validateOrigin(request);
  if (!originValid) return rejectCsrf("api/kb/file", origin);

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

  // Extract and validate path
  const { path: pathSegments } = await params;
  const relativePath = pathSegments.join("/");

  if (!relativePath) {
    return NextResponse.json({ error: "File path required" }, { status: 400 });
  }

  // Null byte check
  if (relativePath.includes("\0")) {
    return NextResponse.json({ error: "Invalid path: null byte detected" }, { status: 400 });
  }

  // Extension check — only attachments can be renamed, not markdown
  const oldExt = path.extname(relativePath).toLowerCase();
  if (oldExt === ".md") {
    return NextResponse.json(
      { error: "Markdown files cannot be renamed through this endpoint" },
      { status: 400 },
    );
  }

  // Path traversal check
  const kbRoot = path.join(userData.workspace_path, "knowledge-base");
  const fullPath = path.join(kbRoot, relativePath);
  if (!isPathInWorkspace(fullPath, kbRoot)) {
    return NextResponse.json({ error: "Invalid path" }, { status: 400 });
  }

  // Symlink check — skip if file doesn't exist locally (ENOENT)
  try {
    const stat = await fs.lstat(fullPath);
    if (stat.isSymbolicLink()) {
      return NextResponse.json({ error: "Access denied" }, { status: 403 });
    }
  } catch (err) {
    const code = (err as NodeJS.ErrnoException).code;
    if (code !== "ENOENT") {
      return NextResponse.json({ error: "Access denied" }, { status: 403 });
    }
  }

  // Parse newName from JSON body
  let newName: string;
  try {
    const body = await request.json();
    newName = body.newName;
  } catch {
    return NextResponse.json({ error: "Invalid JSON body" }, { status: 400 });
  }

  if (!newName || typeof newName !== "string") {
    return NextResponse.json({ error: "newName is required" }, { status: 400 });
  }

  // Sanitize newName
  const { valid: nameValid, sanitized: sanitizedNewName, error: nameError } =
    sanitizeFilename(newName);
  if (!nameValid) {
    return NextResponse.json(
      { error: nameError || "Invalid filename" },
      { status: 400 },
    );
  }

  // Extension preservation check
  const newExt = path.extname(sanitizedNewName).toLowerCase();
  if (newExt !== oldExt) {
    return NextResponse.json(
      { error: "Cannot change file extension" },
      { status: 400 },
    );
  }

  // Same-name check
  const oldName = path.basename(relativePath);
  if (sanitizedNewName === oldName) {
    return NextResponse.json(
      { error: "New name is the same as current name" },
      { status: 400 },
    );
  }

  // Path traversal check on new path
  const dirPath = path.dirname(relativePath);
  const newRelativePath = dirPath === "." ? sanitizedNewName : `${dirPath}/${sanitizedNewName}`;
  const newFullPath = path.join(kbRoot, newRelativePath);
  if (!isPathInWorkspace(newFullPath, kbRoot)) {
    return NextResponse.json({ error: "Invalid path" }, { status: 400 });
  }

  // Parse owner/repo from repo_url
  const repoUrlParts = userData.repo_url.replace(/\.git$/, "").split("/");
  const repo = repoUrlParts.pop()!;
  const owner = repoUrlParts.pop()!;

  if (!owner || !repo) {
    return NextResponse.json({ error: "Invalid repository URL" }, { status: 500 });
  }

  const oldFilePath = `knowledge-base/${relativePath}`;
  const newFilePath = `knowledge-base/${newRelativePath}`;

  try {
    // 1. GET file blob SHA from Contents API
    let blobSha: string;
    try {
      const fileData = await githubApiGet<
        { sha: string; type: string } | Array<{ sha: string; type: string }>
      >(
        userData.github_installation_id,
        `/repos/${owner}/${repo}/contents/${oldFilePath}`,
      );

      if (Array.isArray(fileData)) {
        return NextResponse.json(
          { error: "Cannot rename a directory" },
          { status: 400 },
        );
      }

      blobSha = fileData.sha;
    } catch (err) {
      const errMsg = err instanceof Error ? err.message : "";
      if (errMsg.includes("404")) {
        return NextResponse.json({ error: "File not found" }, { status: 404 });
      }
      throw err;
    }

    // 2. Check if destination already exists
    try {
      await githubApiGet(
        userData.github_installation_id,
        `/repos/${owner}/${repo}/contents/${newFilePath}`,
      );
      return NextResponse.json(
        { error: "A file with that name already exists" },
        { status: 409 },
      );
    } catch (err) {
      const errMsg = err instanceof Error ? err.message : "";
      if (!errMsg.includes("404")) {
        throw err;
      }
      // 404 is expected — destination doesn't exist, proceed
    }

    // 3. GET current branch ref
    const defaultBranch = userData.repo_url.includes("github.com") ? "main" : "main";
    const refData = await githubApiGet<{ object: { sha: string } }>(
      userData.github_installation_id,
      `/repos/${owner}/${repo}/git/ref/heads/${defaultBranch}`,
    );
    const currentCommitSha = refData.object.sha;

    // 4. GET commit to get tree SHA
    const commitData = await githubApiGet<{ tree: { sha: string } }>(
      userData.github_installation_id,
      `/repos/${owner}/${repo}/git/commits/${currentCommitSha}`,
    );
    const baseTreeSha = commitData.tree.sha;

    // 5. POST /git/trees — atomic rename (delete old + create new in one tree)
    const treeData = await githubApiPost<{ sha: string }>(
      userData.github_installation_id,
      `/repos/${owner}/${repo}/git/trees`,
      {
        base_tree: baseTreeSha,
        tree: [
          { path: oldFilePath, mode: "100644", type: "blob", sha: null },
          { path: newFilePath, mode: "100644", type: "blob", sha: blobSha },
        ],
      },
    );

    // 6. POST /git/commits
    const newCommit = await githubApiPost<{ sha: string }>(
      userData.github_installation_id,
      `/repos/${owner}/${repo}/git/commits`,
      {
        message: `Rename ${oldName} to ${sanitizedNewName} via Soleur`,
        tree: treeData!.sha,
        parents: [currentCommitSha],
      },
    );

    // 7. PATCH /git/refs to update branch pointer
    await githubApiPost(
      userData.github_installation_id,
      `/repos/${owner}/${repo}/git/refs/heads/${defaultBranch}`,
      { sha: newCommit!.sha },
      "PATCH",
    );

    // 8. Workspace sync
    let helperPath: string | null = null;
    try {
      const token = await generateInstallationToken(userData.github_installation_id);
      helperPath = randomCredentialPath();
      writeFileSync(
        helperPath,
        `#!/bin/sh\necho "username=x-access-token"\necho "password=${token}"`,
        { mode: 0o700 },
      );

      await execFileAsync(
        "git",
        ["-c", `credential.helper=!${helperPath}`, "pull", "--ff-only"],
        { cwd: userData.workspace_path, timeout: 30_000 },
      );
    } catch (syncError) {
      logger.error(
        { err: syncError, userId: user.id },
        "kb/rename: workspace sync failed after successful rename",
      );
      Sentry.captureException(syncError);
      return NextResponse.json(
        {
          error: "File renamed on GitHub but workspace sync failed. Try refreshing.",
          code: "SYNC_FAILED",
          commitSha: newCommit!.sha,
        },
        { status: 500 },
      );
    } finally {
      if (helperPath) {
        try { unlinkSync(helperPath); } catch { /* best-effort cleanup */ }
      }
    }

    logger.info(
      { event: "kb_rename", userId: user.id, oldPath: oldFilePath, newPath: newFilePath },
      "kb/rename: file renamed successfully",
    );

    return NextResponse.json(
      { oldPath: oldFilePath, newPath: newFilePath, commitSha: newCommit!.sha },
      { status: 200 },
    );
  } catch (error) {
    Sentry.captureException(error);

    if (error instanceof Error && error.message.includes("GitHub API")) {
      logger.error(
        { err: error, userId: user.id, oldPath: oldFilePath, newPath: newFilePath },
        "kb/rename: GitHub API error",
      );
      return NextResponse.json(
        { error: error.message, code: "GITHUB_API_ERROR" },
        { status: 502 },
      );
    }

    logger.error(
      { err: error, userId: user.id },
      "kb/rename: unexpected error",
    );
    return NextResponse.json(
      { error: "Internal server error" },
      { status: 500 },
    );
  }
}
