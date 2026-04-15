import { NextResponse } from "next/server";
import {
  githubApiGet,
  githubApiPost,
  githubApiDelete,
  GitHubApiError,
} from "@/server/github-api";
import { isPathInWorkspace } from "@/server/sandbox";
import { sanitizeFilename } from "@/server/kb-validation";
import {
  authenticateAndResolveKbPath,
  syncWorkspace,
} from "@/server/kb-route-helpers";
import path from "path";
import logger from "@/server/logger";
import * as Sentry from "@sentry/nextjs";

export async function DELETE(
  request: Request,
  { params }: { params: Promise<{ path: string[] }> },
) {
  const resolved = await authenticateAndResolveKbPath(request, params);
  if (!resolved.ok) return resolved.response;
  const { ctx } = resolved;
  const { user, userData, owner, repo, relativePath, filePath } = ctx;

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
      if (err instanceof GitHubApiError && err.statusCode === 404) {
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
      const sync = await syncWorkspace(
        userData.github_installation_id,
        userData.workspace_path,
        logger,
        { userId: user.id, op: "delete" },
      );
      if (!sync.ok) {
        Sentry.captureException(sync.error);
        return NextResponse.json(
          {
            error:
              "File deleted from GitHub but workspace sync failed. Try refreshing.",
            code: "SYNC_FAILED",
            commitSha: result?.commit?.sha ?? null,
          },
          { status: 500 },
        );
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
      if (deleteErr instanceof GitHubApiError && deleteErr.statusCode === 409) {
        return NextResponse.json(
          {
            error:
              "File was modified since it was last read. Please refresh and try again.",
            code: "SHA_MISMATCH",
          },
          { status: 409 },
        );
      }
      throw deleteErr;
    }
  } catch (error) {
    Sentry.captureException(error);

    if (error instanceof GitHubApiError) {
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
  const resolved = await authenticateAndResolveKbPath(request, params);
  if (!resolved.ok) return resolved.response;
  const { ctx } = resolved;
  const {
    user,
    userData,
    owner,
    repo,
    relativePath,
    filePath: oldFilePath,
    kbRoot,
    ext: oldExt,
  } = ctx;

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
  const {
    valid: nameValid,
    sanitized: sanitizedNewName,
    error: nameError,
  } = sanitizeFilename(newName);
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
  const newRelativePath =
    dirPath === "." ? sanitizedNewName : `${dirPath}/${sanitizedNewName}`;
  const newFullPath = path.join(kbRoot, newRelativePath);
  if (!isPathInWorkspace(newFullPath, kbRoot)) {
    return NextResponse.json({ error: "Invalid path" }, { status: 400 });
  }

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
      if (err instanceof GitHubApiError && err.statusCode === 404) {
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
      if (!(err instanceof GitHubApiError) || err.statusCode !== 404) {
        throw err;
      }
      // 404 is expected — destination doesn't exist, proceed
    }

    // 3. GET current branch ref (fetch actual default branch from repo metadata)
    const repoMeta = await githubApiGet<{ default_branch: string }>(
      userData.github_installation_id,
      `/repos/${owner}/${repo}`,
    );
    const defaultBranch = repoMeta.default_branch;
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

    if (!treeData?.sha) {
      throw new Error("GitHub API: tree creation returned no data");
    }

    // 6. POST /git/commits
    const newCommit = await githubApiPost<{ sha: string }>(
      userData.github_installation_id,
      `/repos/${owner}/${repo}/git/commits`,
      {
        message: `Rename ${oldName} to ${sanitizedNewName} via Soleur`,
        tree: treeData.sha,
        parents: [currentCommitSha],
      },
    );

    if (!newCommit?.sha) {
      throw new Error("GitHub API: commit creation returned no data");
    }

    // 7. PATCH /git/refs to update branch pointer
    await githubApiPost(
      userData.github_installation_id,
      `/repos/${owner}/${repo}/git/refs/heads/${defaultBranch}`,
      { sha: newCommit.sha },
      "PATCH",
    );

    // 8. Workspace sync
    const sync = await syncWorkspace(
      userData.github_installation_id,
      userData.workspace_path,
      logger,
      { userId: user.id, op: "rename" },
    );
    if (!sync.ok) {
      Sentry.captureException(sync.error);
      return NextResponse.json(
        {
          error:
            "File renamed on GitHub but workspace sync failed. Try refreshing.",
          code: "SYNC_FAILED",
          commitSha: newCommit.sha,
        },
        { status: 500 },
      );
    }

    logger.info(
      {
        event: "kb_rename",
        userId: user.id,
        oldPath: oldFilePath,
        newPath: newFilePath,
      },
      "kb/rename: file renamed successfully",
    );

    return NextResponse.json(
      { oldPath: oldFilePath, newPath: newFilePath, commitSha: newCommit.sha },
      { status: 200 },
    );
  } catch (error) {
    Sentry.captureException(error);

    if (error instanceof GitHubApiError) {
      logger.error(
        {
          err: error,
          userId: user.id,
          oldPath: oldFilePath,
          newPath: newFilePath,
        },
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
