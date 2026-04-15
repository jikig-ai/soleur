# refactor(kb): extract route helpers, typed GitHub errors, FileNode component split

**Date:** 2026-04-14
**Branch:** `feat-refactor-kb-routes`
**Worktree:** `.worktrees/feat-refactor-kb-routes/`
**Milestone:** Post-MVP / Later
**Closes:** #2180, #2150, #2149
**Source:** PR #2172 review follow-ups
**Type:** refactor (non-functional; structure + typing only)

## Enhancement Summary

**Deepened on:** 2026-04-14
**Sections enhanced:** GitHubApiError design, test-mocking strategy, risk table
**Key corrections from deepen pass:**

1. **CRITICAL:** `GitHubApiError` already exists at `apps/web-platform/server/github-app.ts:62` with field `statusCode` (not `status`). The original plan prescribed a new class — wrong. Correct approach: **re-export the existing class from `server/github-api.ts`** and have `handleErrorResponse` throw the existing class. Do NOT introduce a second `GitHubApiError` or rename the field.
2. **Test mocking pattern correction:** Tests that need `instanceof GitHubApiError` in mocks must use the `vi.hoisted()` pattern (see learning `2026-04-10-vitest-hoisted-class-for-typed-error-mocking.md`). `importOriginal` inside `vi.mock("@/server/github-app")` or `vi.mock("@/server/github-api")` triggers transitive loader failures because the real modules pull in `@/server/logger.createChildLogger` which most test mocks don't provide. Use the hoisted class pattern proven by `test/create-route-error.test.ts:14-22`.
3. **Symlink-check pattern:** `learning 2026-04-07-symlink-escape` confirms this module already enforces symlink rejection correctly for point-access (which this refactor preserves). No new enumeration risk because this refactor does not add recursive traversal.
4. **Plan-review learning carry-forward:** Prior learnings (`2026-02-06-parallel-plan-review-catches-overengineering`, `2026-02-19-plan-review-catches-redundant-validation-gates`) warn that refactor plans tend to over-generalize helpers. The plan's "options bag" on `authenticateAndResolveKbPath` was flagged — kept minimal (`endpoint`, `blockMarkdown`) and added YAGNI note below.
5. **Field name alignment:** All plan references to `err.status` were wrong; use `err.statusCode` to match the existing class contract. Updated throughout.

**New considerations discovered:**

- The existing `GitHubApiError` only carries `statusCode`, not `bodyText` or `path`. The plan's expanded shape (add `bodyText` and `path`) is **optional** and additive — only if a test or caller needs them. Prefer minimal change: just extend the constructor to accept optional `bodyText`/`path` as a follow-up if needed. Do not break existing `new GitHubApiError(message, status)` call sites.
- `app/api/repo/create/route.ts:69` already uses `instanceof GitHubApiError && err.statusCode === 422` — the KB migration aligns with an established project convention, not a new one. This reduces review risk.

## Summary

Address three code-review follow-ups from PR #2172 in one cohesive PR. All three items target the KB feature area and reinforce each other:

1. **#2180** — PATCH and DELETE handlers in `apps/web-platform/app/api/kb/file/[...path]/route.ts` share ~100 lines of auth/validation/workspace-sync boilerplate. Extract into shared helpers.
2. **#2149** — KB routes currently do string matching on error messages (`errMsg.includes("404")`). Replace with a typed `GitHubApiError` that carries a numeric `status` field, thrown from `handleErrorResponse`.
3. **#2150** — `TreeItem` in `components/kb/file-tree.tsx` renders both directories and files in one ~490-line component. Extract `FileNode` (file rendering only) and keep `TreeItem` focused on directory rendering.

**Order matters:** implement #2149 first (typed errors are consumed by the new helpers), then #2180 (helpers use the typed errors), then #2150 (pure component split, independent).

**Non-goal:** registering a KB-rename agent tool (mentioned in #2180) is an explicit follow-up — do NOT include here. Plugin MCP / agent-tool wiring is a separate concern (parity gap tracked in #2180 body).

## Files to modify

### #2149 — Typed GitHubApiError

- `apps/web-platform/server/github-api.ts` — **re-export the existing `GitHubApiError` class from `@/server/github-app`**; update `handleErrorResponse` to throw it (instead of plain `Error`). Do NOT define a new class — the existing one at `server/github-app.ts:62` is already canonical and used by `app/api/repo/create/route.ts`.
- `apps/web-platform/app/api/kb/file/[...path]/route.ts` — replace `errMsg.includes("404")` / `includes("409")` / `includes("GitHub API")` with `instanceof GitHubApiError` + `err.statusCode === N` checks (note field name: **`statusCode`**, not `status`)
- `apps/web-platform/app/api/kb/upload/route.ts` — same replacements (both `errMsg.includes("404")` and `error.message.includes("GitHub API")`)

### #2180 — Extract helpers

- `apps/web-platform/server/kb-route-helpers.ts` — **new file**, contains:
  - `authenticateAndResolveKbPath(request, params)` — CSRF, auth, workspace fetch, path validation, null-byte, `.md` block, path traversal, symlink check, owner/repo parse, returns a typed result
  - `syncWorkspace(installationId, workspacePath, logger, context)` — git pull with installation token + credential helper scaffolding + cleanup; returns `{ ok: true }` or `{ ok: false, error }`
- `apps/web-platform/app/api/kb/file/[...path]/route.ts` — replace inline boilerplate in PATCH and DELETE with the helpers

### #2150 — FileNode extraction

- `apps/web-platform/components/kb/file-tree.tsx` — extract `FileNode` component (lines ~329-482 of current file); keep `TreeItem` focused on directory rendering; shared icons and `formatRelativeTime` stay colocated in this file (module-scope helpers, no new file churn).

### Tests (new + updated)

- `apps/web-platform/test/github-api.test.ts` — **update** — assert `handleErrorResponse` now throws `GitHubApiError` with correct `statusCode` (404, 403, 409, 500); assert re-export identity
- (No new `github-api-error.test.ts` — the class already has coverage in `test/github-app-create-repo.test.ts`)
- `apps/web-platform/test/kb-route-helpers.test.ts` — **new** — unit tests for `authenticateAndResolveKbPath` and `syncWorkspace` (each branch: unauth, workspace-not-ready, no-repo, empty path, null byte, `.md`, traversal, symlink, happy path)
- `apps/web-platform/test/kb-delete.test.ts` — **update** — replace any assertions on string-matched 404 messages with `GitHubApiError.status`
- `apps/web-platform/test/kb-rename.test.ts` — **update** — same
- `apps/web-platform/test/kb-upload.test.ts` — **update** — same
- `apps/web-platform/test/file-tree-delete.test.tsx`, `file-tree-rename.test.tsx`, `file-tree-upload.test.tsx` — **verify still green** after `FileNode` split (behavioral tests, unchanged expectations)

## Detailed design

### 1. `GitHubApiError` (issue #2149)

**Reuse the existing class** at `apps/web-platform/server/github-app.ts:62`:

```typescript
// apps/web-platform/server/github-app.ts (ALREADY EXISTS — DO NOT REDEFINE)
export class GitHubApiError extends Error {
  constructor(
    message: string,
    public readonly statusCode: number,
  ) {
    super(message);
    this.name = "GitHubApiError";
  }
}
```

**Change in `server/github-api.ts`:** re-export the class and have `handleErrorResponse` throw it.

```typescript
// apps/web-platform/server/github-api.ts

import { generateInstallationToken, GitHubApiError } from "./github-app";
// ... existing imports ...

export { GitHubApiError };  // re-export for route-layer callers

async function handleErrorResponse(
  response: Response,
  path: string,
): Promise<never> {
  const bodyText = await response.text();

  if (response.status === 403) {
    log.warn({ status: 403, path, body: bodyText.slice(0, 500) }, "GitHub API 403 — possible permission gap");
    throw new GitHubApiError(
      `GitHub API permission denied (403) for ${path}. ` +
      "Your Soleur GitHub App installation may need updated permissions. " +
      "Visit your GitHub App installation settings to approve new permissions.",
      403,
    );
  }

  log.error({ status: response.status, path, body: bodyText.slice(0, 500) }, "GitHub API request failed");
  throw new GitHubApiError(`GitHub API request failed: ${response.status} ${path}`, response.status);
}
```

**Why reuse, not re-introduce:** A second `GitHubApiError` class with a different field name (`status` vs `statusCode`) would fork the convention. `app/api/repo/create/route.ts:69` already uses `instanceof GitHubApiError && err.statusCode === 422`. One class, one field name, project-wide.

**Backward compatibility:** `GitHubApiError extends Error`, so existing `instanceof Error` + `.message.includes("GitHub API")` checks still pass during the transition. The message format is preserved verbatim (`"GitHub API request failed: {status} {path}"`), so any downstream code still grepping for it continues to match. The refactor migrates call sites to the typed form; the string form remains an accurate safety net.

**Callers updated (remove string matching):**

```typescript
// Before
const errMsg = err instanceof Error ? err.message : "";
if (errMsg.includes("404")) { ... }

// After
if (err instanceof GitHubApiError && err.statusCode === 404) { ... }
```

**Optional follow-up (not in this PR):** If the KB routes ever need `path` or `bodyText` on the error (e.g., to return the GitHub error body to the client), extend the existing constructor to accept optional fields rather than forking. Current call sites don't need them — the 502 fallback already includes `error.message`.

Call sites to migrate:

- `app/api/kb/file/[...path]/route.ts:126` (DELETE → GET 404)
- `app/api/kb/file/[...path]/route.ts:190` (DELETE → DELETE 409)
- `app/api/kb/file/[...path]/route.ts:204` (DELETE outer catch — GitHub API branch)
- `app/api/kb/file/[...path]/route.ts:383` (PATCH → GET 404)
- `app/api/kb/file/[...path]/route.ts:401` (PATCH → destination exists check, 404 expected)
- `app/api/kb/file/[...path]/route.ts:514` (PATCH outer catch — GitHub API branch)
- `app/api/kb/upload/route.ts:169` (upload → existence probe 404 expected)
- `app/api/kb/upload/route.ts:272` (upload outer catch — GitHub API branch)

### 2. Route helpers (issue #2180)

```typescript
// apps/web-platform/server/kb-route-helpers.ts

import { NextResponse } from "next/server";
import path from "path";
import { promises as fs, writeFileSync, unlinkSync } from "node:fs";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { createClient, createServiceClient } from "@/lib/supabase/server";
import { validateOrigin, rejectCsrf } from "@/lib/auth/validate-origin";
import { isPathInWorkspace } from "@/server/sandbox";
import { generateInstallationToken, randomCredentialPath } from "@/server/github-app";
import type { Logger } from "pino";

const execFileAsync = promisify(execFile);

export type KbRouteContext = {
  user: { id: string };
  userData: {
    workspace_path: string;
    repo_url: string;
    github_installation_id: number;
  };
  owner: string;
  repo: string;
  relativePath: string;          // e.g. "domain/file.pdf"
  filePath: string;              // e.g. "knowledge-base/domain/file.pdf"
  kbRoot: string;                // absolute path to workspace/knowledge-base
  fullPath: string;              // kbRoot + relativePath
  ext: string;                   // ".pdf" (lowercased)
};

/**
 * Authenticate, validate the KB path, and resolve repo metadata.
 * Returns either a typed context object or a NextResponse error to return.
 *
 * Shared across PATCH and DELETE handlers on /api/kb/file/[...path].
 * Does NOT enforce the `.md` extension block — caller decides (both current
 * handlers do reject `.md`, but the check is identical and kept inline here
 * as a config flag: `blockMarkdown: true`).
 */
export async function authenticateAndResolveKbPath(
  request: Request,
  params: Promise<{ path: string[] }>,
  opts: { endpoint: string; blockMarkdown: boolean } = {
    endpoint: "api/kb/file",
    blockMarkdown: true,
  },
): Promise<
  | { ok: true; ctx: KbRouteContext }
  | { ok: false; response: NextResponse }
> {
  // CSRF
  const { valid: originValid, origin } = validateOrigin(request);
  if (!originValid) return { ok: false, response: rejectCsrf(opts.endpoint, origin) };

  // Auth
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return err(401, "Unauthorized");

  // Workspace
  const serviceClient = createServiceClient();
  const { data: userData } = await serviceClient
    .from("users")
    .select("workspace_path, workspace_status, repo_url, github_installation_id")
    .eq("id", user.id)
    .single();

  if (!userData?.workspace_path || userData.workspace_status !== "ready") {
    return err(503, "Workspace not ready");
  }
  if (!userData.repo_url || !userData.github_installation_id) {
    return err(400, "No repository connected");
  }

  // Path
  const { path: pathSegments } = await params;
  const relativePath = pathSegments.join("/");
  if (!relativePath) return err(400, "File path required");
  if (relativePath.includes("\0")) return err(400, "Invalid path: null byte detected");

  const ext = path.extname(relativePath).toLowerCase();
  if (opts.blockMarkdown && ext === ".md") {
    return err(400, "Markdown files cannot be modified through this endpoint");
  }

  const kbRoot = path.join(userData.workspace_path, "knowledge-base");
  const fullPath = path.join(kbRoot, relativePath);
  if (!isPathInWorkspace(fullPath, kbRoot)) return err(400, "Invalid path");

  // Symlink check (tolerate ENOENT)
  try {
    const stat = await fs.lstat(fullPath);
    if (stat.isSymbolicLink()) return err(403, "Access denied");
  } catch (e) {
    const code = (e as NodeJS.ErrnoException).code;
    if (code !== "ENOENT") return err(403, "Access denied");
  }

  // Parse owner/repo
  const repoUrlParts = userData.repo_url.replace(/\.git$/, "").split("/");
  const repo = repoUrlParts.pop()!;
  const owner = repoUrlParts.pop()!;
  if (!owner || !repo) return err(500, "Invalid repository URL");

  const filePath = `knowledge-base/${relativePath}`;

  return {
    ok: true,
    ctx: {
      user: { id: user.id },
      userData: {
        workspace_path: userData.workspace_path,
        repo_url: userData.repo_url,
        github_installation_id: userData.github_installation_id,
      },
      owner,
      repo,
      relativePath,
      filePath,
      kbRoot,
      fullPath,
      ext,
    },
  };

  function err(status: number, message: string) {
    return { ok: false as const, response: NextResponse.json({ error: message }, { status }) };
  }
}

/**
 * Pull the workspace to sync local files with the remote repo after a
 * successful GitHub mutation. Uses an installation-scoped credential helper.
 *
 * Returns { ok: true } on success, { ok: false, error } on failure.
 * Callers decide which 500 response shape to return (different handlers
 * include different metadata — commitSha, oldPath/newPath, etc.).
 */
export async function syncWorkspace(
  installationId: number,
  workspacePath: string,
  log: Logger,
  context: { userId: string; op: "delete" | "rename" | "upload" },
): Promise<{ ok: true } | { ok: false; error: unknown }> {
  let helperPath: string | null = null;
  try {
    const token = await generateInstallationToken(installationId);
    helperPath = randomCredentialPath();
    writeFileSync(
      helperPath,
      `#!/bin/sh\necho "username=x-access-token"\necho "password=${token}"`,
      { mode: 0o700 },
    );
    await execFileAsync(
      "git",
      ["-c", `credential.helper=!${helperPath}`, "pull", "--ff-only"],
      { cwd: workspacePath, timeout: 30_000 },
    );
    return { ok: true };
  } catch (syncError) {
    log.error(
      { err: syncError, userId: context.userId, op: context.op },
      `kb/${context.op}: workspace sync failed`,
    );
    return { ok: false, error: syncError };
  } finally {
    if (helperPath) {
      try { unlinkSync(helperPath); } catch { /* best-effort cleanup */ }
    }
  }
}
```

**DELETE handler after refactor (sketch):**

```typescript
export async function DELETE(request, { params }) {
  const resolved = await authenticateAndResolveKbPath(request, params);
  if (!resolved.ok) return resolved.response;
  const { ctx } = resolved;
  const { user, userData, owner, repo, filePath, relativePath } = ctx;

  try {
    // GET SHA (still inline — it's the operation, not boilerplate)
    let fileSha: string;
    try {
      const fileData = await githubApiGet<...>(...);
      if (Array.isArray(fileData)) return NextResponse.json({ error: "Cannot delete a directory" }, { status: 400 });
      fileSha = fileData.sha;
    } catch (err) {
      if (err instanceof GitHubApiError && err.statusCode === 404) {
        return NextResponse.json({ error: "File not found" }, { status: 404 });
      }
      throw err;
    }

    // DELETE (still inline)
    try {
      const result = await githubApiDelete<...>(...);

      const sync = await syncWorkspace(userData.github_installation_id, userData.workspace_path, logger, { userId: user.id, op: "delete" });
      if (!sync.ok) {
        Sentry.captureException(sync.error);
        return NextResponse.json(
          { error: "File deleted from GitHub but workspace sync failed. Try refreshing.", code: "SYNC_FAILED", commitSha: result?.commit?.sha ?? null },
          { status: 500 },
        );
      }

      logger.info({ event: "kb_delete", userId: user.id, path: filePath }, "kb/delete: file deleted successfully");
      return NextResponse.json({ commitSha: result?.commit?.sha ?? null }, { status: 200 });
    } catch (deleteErr) {
      if (deleteErr instanceof GitHubApiError && deleteErr.statusCode === 409) {
        return NextResponse.json(
          { error: "File was modified since it was last read. Please refresh and try again.", code: "SHA_MISMATCH" },
          { status: 409 },
        );
      }
      throw deleteErr;
    }
  } catch (error) {
    Sentry.captureException(error);
    if (error instanceof GitHubApiError) {
      logger.error({ err: error, userId: user.id, path: filePath }, "kb/delete: GitHub API error");
      return NextResponse.json({ error: error.message, code: "GITHUB_API_ERROR" }, { status: 502 });
    }
    logger.error({ err: error, userId: user.id }, "kb/delete: unexpected error");
    return NextResponse.json({ error: "Internal server error" }, { status: 500 });
  }
}
```

The PATCH handler follows the same shape, with the only boilerplate removed: CSRF, auth, workspace fetch, path validation (null byte, `.md`, traversal), symlink, and owner/repo parsing.

**What stays inline in each handler (by design):**

- Extension-preservation check in PATCH (`newExt !== oldExt`) — PATCH-specific
- `newName` JSON body parsing, `sanitizeFilename`, same-name check, new path traversal check — all PATCH-specific
- SHA fetch / delete-call / rename-call (tree/commit/ref dance) — these ARE the operations
- Outer `try/catch` with Sentry + 502 mapping — different log context per handler

**Line count expectation:** DELETE drops from ~208 lines to ~80; PATCH from ~309 to ~160. Helper is ~170 lines (counting types, docstrings, imports).

### 3. `FileNode` extraction (issue #2150)

Split `file-tree.tsx` into three components:

- `FileTree` (top-level `<nav>`, unchanged)
- `TreeItem` — **directory-only** rendering: chevron, folder icon, upload button, upload state, recursion into children (including passing `FileNode` for leaf file children)
- `FileNode` — **file-only** rendering: file-type icon, link, rename input, rename/delete action buttons, delete confirmation, rename/delete error toasts

**Rendering flow:**

```text
FileTree
 └─ TreeItem (depth 0, node.type === "directory")
     ├─ (directory chrome)
     └─ children.map →
         ├─ TreeItem (nested directory)
         └─ FileNode (leaf file)
```

Current `TreeItem` dispatches on `node.type === "directory"`. After split, `TreeItem` assumes directory (no dispatch inside) and its child map dispatches:

```tsx
{node.children.map((child) =>
  child.type === "directory" ? (
    <TreeItem key={child.name} node={child} depth={depth + 1} parentPath={dirKey} expanded={expanded} onToggle={onToggle} />
  ) : (
    <FileNode key={child.name} node={child} depth={depth + 1} parentPath={dirKey} />
  )
)}
```

**State isolation:** Each component owns only its own state:

- `TreeItem`: `uploadState`, `fileInputRef`
- `FileNode`: `deleteState`, `renameState`, `renameInputRef`, `renameSubmittedRef`

This is a **pure structural** split — no behavior changes. Existing tests (`file-tree-delete.test.tsx`, `file-tree-rename.test.tsx`, `file-tree-upload.test.tsx`) should remain green with zero modification.

**Props contracts:**

```typescript
type TreeItemProps = {
  node: TreeNode;           // node.type === "directory" (not enforced by types — runtime invariant)
  depth: number;
  parentPath: string;
  expanded: Set<string>;
  onToggle: (path: string) => void;
};

type FileNodeProps = {
  node: TreeNode;           // node.type === "file"
  depth: number;
  parentPath: string;
};
```

Icons (`FolderIcon`, `FileTypeIcon`, `UploadIcon`, `PencilIcon`, `TrashIcon`) and `formatRelativeTime` stay as module-scope helpers in `file-tree.tsx`. Splitting them into a separate icons file is out of scope (pure churn; reviewer DHH would reject).

## Acceptance Criteria

- [x] `GitHubApiError` (the existing class from `server/github-app.ts`) is re-exported from `server/github-api.ts`
- [x] `handleErrorResponse` throws `GitHubApiError` (not plain `Error`), using the existing `statusCode` field; message format preserved
- [x] No duplicate `GitHubApiError` class introduced; no field rename
- [x] All 8 `errMsg.includes("404"|"409"|"GitHub API")` call sites in KB routes replaced with typed checks
- [x] `authenticateAndResolveKbPath` handles all 10 branches currently duplicated in PATCH + DELETE (CSRF, auth, workspace, no-repo, empty path, null byte, `.md` block, path traversal, symlink, invalid repo URL)
- [x] `syncWorkspace` handles credential-helper scaffolding and cleanup; returns `{ok}` discriminated result
- [x] PATCH and DELETE handlers use both helpers
- [x] No behavioral changes: every existing `kb-delete`, `kb-rename`, `kb-upload` test passes unchanged
- [x] `FileNode` component extracted; `TreeItem` now handles directories only
- [x] `file-tree-delete.test.tsx`, `file-tree-rename.test.tsx`, `file-tree-upload.test.tsx` all pass without modification
- [x] New tests: `github-api-error.test.ts`, `kb-route-helpers.test.ts`
- [x] `node node_modules/vitest/vitest.mjs run` passes green on all KB/github-api tests
- [x] `tsc --noEmit` clean
- [x] `eslint` clean for changed files

## Test Scenarios (write these first — TDD gate)

### `github-api.test.ts` (update — no new `github-api-error.test.ts` file needed)

The `GitHubApiError` class already has coverage via `test/github-app-create-repo.test.ts`. Add the KB-facing assertions here:

1. `handleErrorResponse` with 404 throws `GitHubApiError` with `.statusCode === 404`, `instanceof Error` true
2. `handleErrorResponse` with 403 throws `GitHubApiError` with `.statusCode === 403` and permission-denied message
3. `handleErrorResponse` with 500 throws `GitHubApiError` with `.statusCode === 500` and default `"GitHub API request failed: 500 {path}"` message
4. Existing `instanceof Error` + `.message.includes("GitHub API")` still passes (backward compat proof)
5. `GitHubApiError` re-exported from `server/github-api.ts` is the same class reference as from `server/github-app.ts` (`GitHubApiErrorA === GitHubApiErrorB`)

**Mocking pattern for new tests (per learning `2026-04-10-vitest-hoisted-class-for-typed-error-mocking.md`):**

```typescript
const { GitHubApiError, mockGet } = vi.hoisted(() => {
  class GitHubApiError extends Error {
    constructor(message: string, public readonly statusCode: number) {
      super(message);
      this.name = "GitHubApiError";
    }
  }
  return { GitHubApiError, mockGet: vi.fn() };
});

vi.mock("@/server/github-api", () => ({
  githubApiGet: mockGet,
  githubApiPost: vi.fn(),
  githubApiDelete: vi.fn(),
  GitHubApiError,  // same reference route handler sees
}));
```

Do NOT use `importOriginal` — it pulls in `@/server/logger` and breaks because logger mocks don't provide `createChildLogger`.

### `kb-route-helpers.test.ts` (new)

For `authenticateAndResolveKbPath`:

9. Invalid origin → 403 CSRF response (via `rejectCsrf`)
10. No user → 401 "Unauthorized"
11. Workspace not ready → 503
12. No repo connected → 400
13. Empty path → 400 "File path required"
14. Null byte → 400
15. `.md` extension with `blockMarkdown: true` → 400
16. Path traversal (`../../etc/passwd`) → 400 "Invalid path"
17. Symlink on disk → 403 "Access denied"
18. ENOENT on lstat → proceeds (no error)
19. Happy path → returns `{ok: true, ctx: {...}}` with all fields populated

For `syncWorkspace`:

20. Happy path git-pull → `{ok: true}`, helper file deleted
21. git-pull failure → `{ok: false, error}`, helper file still deleted (finally block)
22. Logger called with correct op tag

### `kb-delete.test.ts` + `kb-rename.test.ts` + `kb-upload.test.ts` (update existing)

23. Any existing test that mocks a 404 via throwing `new Error("GitHub API request failed: 404 ...")` continues to pass (the message format is preserved, so string-matching test doubles still work through the transition)
24. New assertions: when route catches a `GitHubApiError` with `.statusCode === 404`, response is 404 "File not found"
25. When route catches a `GitHubApiError` with `.statusCode === 409`, response is 409 "SHA_MISMATCH" (DELETE)
26. Update existing tests in `kb-delete.test.ts`, `kb-rename.test.ts`, `kb-upload.test.ts` that throw a mock error to use `new GitHubApiError("...", 404)` (hoisted) rather than `new Error("... 404 ...")` — cleaner assertion, catches real regressions

### Component tests (verify unchanged)

26. `file-tree-delete.test.tsx` — unchanged, passes
27. `file-tree-rename.test.tsx` — unchanged, passes
28. `file-tree-upload.test.tsx` — unchanged, passes

## Implementation order (TDD)

1. **RED #2149:** Update `github-api.test.ts` to assert `handleErrorResponse` throws `GitHubApiError` with `.statusCode` (fails — still plain Error). Do NOT create a new `GitHubApiError` class; the existing one at `server/github-app.ts:62` is reused.
2. **GREEN #2149:** Update `handleErrorResponse` in `server/github-api.ts` to throw the existing `GitHubApiError`. Re-export the class from `server/github-api.ts` so KB routes can import from one location.
3. **REFACTOR #2149:** Update all 8 call sites in KB routes to use `instanceof GitHubApiError && err.statusCode === N`. Keep `instanceof Error && .message.includes("GitHub API")` ONLY as a fallback in outer catches where any non-typed error could flow through; prefer `instanceof GitHubApiError`.
4. **RED #2180:** Write `kb-route-helpers.test.ts` (fails — file doesn't exist)
5. **GREEN #2180:** Implement `authenticateAndResolveKbPath` and `syncWorkspace`
6. **REFACTOR #2180:** Replace inline boilerplate in PATCH and DELETE with helpers. Confirm `kb-delete.test.ts` and `kb-rename.test.ts` still pass
7. **RED #2150:** Add prop-shape test for `FileNode` (renders file link, not directory chrome) — optional since existing tests cover behavior
8. **GREEN #2150:** Extract `FileNode`; update child map to dispatch on `node.type`
9. **REFACTOR #2150:** Confirm `file-tree-*.test.tsx` suite passes unchanged
10. Run full KB-affected test subset: `vitest run test/github-api test/kb- test/file-tree-`
11. Run `tsc --noEmit` and `eslint` on changed files

## Risks & Mitigations

| Risk | Mitigation |
| --- | --- |
| Existing tests mock `new Error("GitHub API request failed: 404 ...")` — typed-check migration could break them | `GitHubApiError extends Error` + preserved message format → `instanceof Error` + `.message.includes("404")` both still match. Migrate mocks one at a time. |
| Test mocks fail with "No createChildLogger export" when trying to `importOriginal` on `@/server/github-app` | Use `vi.hoisted()` pattern (learning 2026-04-10). Define `GitHubApiError` inside hoisted block, return from mock factory. Proven by `test/create-route-error.test.ts:14-22`. |
| Someone adds a second `GitHubApiError` class (e.g., plan originally suggested this) | Plan explicitly forbids it. Grep check before merge: `grep -n "class GitHubApiError" apps/web-platform/server/` must return exactly one match at `github-app.ts:62`. |
| Field-name drift (`status` vs `statusCode`) | Plan pinned to `statusCode` matching existing class. `tsc --noEmit` will catch any `.status` access. |
| `authenticateAndResolveKbPath` option surface bloats over time | Start minimal (`endpoint`, `blockMarkdown`). If uploads want to reuse this helper later, add flags then. Don't pre-generalize. |
| `syncWorkspace` signature tied to pino `Logger` type | Accept structural `{ error, info }` type if pino import causes circular deps. Prefer direct `Logger` for now (pino is already a peer dep everywhere this runs). |
| `FileNode` split breaks hover-state coordination across file/directory siblings | There is no shared hover state — each `<div className="group">` is independent. Verified by reading lines 227 (directory group) and 374 (file group): both are self-contained. |
| Helper accidentally changes response body shape (e.g., error codes, status semantics) | Plan preserves every response byte-for-byte. Diff-check each response JSON before merge. |
| Extracted helper imports break route bundling (Next.js edge vs node runtime) | Current route uses `node:child_process` and `node:fs` — already node runtime. Helper uses the same. No edge runtime added. |

## Alternative Approaches Considered

| Approach | Why rejected |
| --- | --- |
| Convert `handleErrorResponse` to return a discriminated union instead of throwing | Throws match existing control flow in all call sites. Returning would require rewriting every `await githubApi*()` site. High churn, no benefit. |
| Put helpers in `app/api/kb/_lib/` (Next.js underscore convention) | `server/` is where existing shared KB logic lives (`kb-reader.ts`, `kb-validation.ts`, `github-api.ts`). Stay consistent. |
| Extract icons to a separate `kb-icons.tsx` file | Pure churn. DHH would reject. Icons are co-located with the only consumer. |
| Split `TreeItem` into `DirectoryNode` (rename for symmetry with `FileNode`) | Callers already know `TreeItem`. Rename is gratuitous. Keep diff minimal. |
| Add a `GitHubApiError.is404()` convenience method | YAGNI. `err.status === 404` is 3 chars longer and idiomatic. |
| Register agent tool for KB rename in this PR (mentioned in #2180) | Explicit non-goal per user. Separate PR follow-up. |

## Domain Review

**Domains relevant:** Engineering (CTO)

This is a pure internal refactor with no user-visible changes, no new pages, no new capabilities, no billing/legal/marketing surface. Product/UX Gate does not apply: no `components/**/*.tsx` creation (only modifications), no `app/**/page.tsx`, no `app/**/layout.tsx`. `file-tree.tsx` is modified in place; no new component file is created (FileNode lives in the same file alongside TreeItem — matches existing file-tree.tsx structure where icons and TreeItem also colocate).

**Decision:** CTO review at plan-review phase is sufficient. No CPO/CMO/UX/copywriter invocation needed.

### CTO / Engineering

**Status:** reviewed inline by plan author
**Assessment:**

- Refactor is non-functional; all three items reinforce KB maintainability.
- Order (typed errors → helpers → component split) is correct: helpers depend on typed errors; component split is independent.
- Helper granularity is right: one auth/resolve helper + one sync helper matches the actual duplication. Resisting the urge to over-extract.
- No architectural implications (no new routes, no schema changes, no new dependencies).
- Rollout is safe: `GitHubApiError extends Error` keeps old string-matching callers compatible during the transition; component split is pure structural.

## Non-Goals / Out of Scope

- **Registering a `kb_rename` agent tool.** Tracked in #2180 body as a follow-up. Requires wiring in `server/service-tools.ts` and MCP plugin registration — separate concern, separate PR.
- **Leader/Dashboard polish PR.** Explicitly the user's next one-shot.
- **Harmonizing `kb/upload/route.ts` with the new helpers.** Upload has a different flow (multipart, base64 encode, duplicate probe) — not worth forcing into the same helper shape. Only migrate the typed-error call sites in upload.
- **Extracting icons to a separate file.** Churn with no benefit.

## Definition of Done

- [x] All acceptance criteria checked
- [x] All test scenarios green locally (`node node_modules/vitest/vitest.mjs run`)
- [x] `tsc --noEmit` clean
- [x] `eslint` clean on changed files
- [x] No new ESLint warnings introduced
- [x] Diff reviewed for byte-for-byte response preservation (DELETE + PATCH + upload response JSON shapes unchanged)
- [x] PR title: `refactor(kb): extract route helpers, typed GitHub errors, FileNode component split`
- [x] PR body includes `Closes #2180`, `Closes #2150`, `Closes #2149`
- [x] Semver label: `type/chore` (no user-visible change)
- [x] Compound run before commit
- [x] Plan review (DHH / Kieran / code-simplicity) addressed
