// Share lifecycle module: validates a KB document, hashes it, and writes
// the DB row for `kb_share_links`. Consumed by both HTTP routes
// (app/api/kb/share/route.ts, [token]/route.ts) and the in-process MCP
// tools (server/kb-share-tools.ts) so a single hardened implementation
// covers both surfaces. Closes #2298 by hoisting the validation and
// lifecycle out of the route handlers.
//
// Error shape is a tagged union with string-literal `code` values so
// telemetry and tests can discriminate failure modes without string
// matching on messages. Several codes share the canonical "Invalid
// document path" message by design — tests MUST assert on `code`, not
// `error`. `status` mirrors the HTTP status the callers should use
// (contract preserves the existing HTTP route behavior — null-byte /
// path-escape all 400, missing 404, size 413).

import fs from "node:fs";
import path from "node:path";
import { randomBytes } from "node:crypto";
import { isPathInWorkspace } from "@/server/sandbox";
import { MAX_BINARY_SIZE } from "@/server/kb-limits";
import {
  validateBinaryFile,
  openBinaryStream,
  deriveBinaryKind,
  BinaryOpenError,
  type BinaryFileMetadata,
} from "@/server/kb-binary-response";
import { hashBytes, hashStream } from "@/server/kb-content-hash";
import {
  readContentRaw,
  KbAccessDeniedError,
  KbFileTooLargeError,
  KbNotFoundError,
} from "@/server/kb-reader";
import { isMarkdownKbPath } from "@/lib/kb-extensions";
import { shareHashVerdictCache } from "@/server/share-hash-verdict-cache";
import {
  readPdfMetadata,
  readImageMetadata,
  type PdfPreview,
  type ImagePreview,
} from "@/server/kb-preview-metadata";
import { createChildLogger } from "@/server/logger";
import { reportSilentFallback } from "@/server/observability";
import { purgeSharedToken } from "@/server/cf-cache-purge";

const log = createChildLogger("kb-share");

// 256 bits of entropy, ~43 base64url chars. Hoisted so the "why 32"
// is explicit at the call site — security-relevant constant.
const SHARE_TOKEN_BYTES = 32;

// Single source of truth for the user-facing 502 error string. The
// "60 seconds" matches the s-maxage value in
// `kb-binary-response.ts::CACHE_CONTROL_BY_SCOPE.public` — keep them
// in lockstep when the public TTL changes.
export const REVOKE_PURGE_FAILED_MESSAGE =
  "Revoke succeeded but cache purge failed; share may be served from cache for up to 60 seconds";

export type CreateShareErrorCode =
  | "invalid-path"
  | "not-found"
  | "not-a-file"
  | "symlink-rejected"
  | "too-large"
  | "concurrent-retry"
  | "db-error";

export type RevokeShareErrorCode =
  | "forbidden"
  | "not-found"
  | "db-error"
  | "purge-failed";

export interface ShareRecord {
  token: string;
  // camelCase at the MCP-tool boundary. The HTTP route re-snake_cases
  // this into the existing `{ document_path, created_at }` wire shape
  // so web clients are unaffected by the extraction.
  documentPath: string;
  createdAt: string;
  revoked: boolean;
}

export type CreateShareResult =
  | {
      ok: true;
      // 200 when returning an existing token (idempotent on unchanged
      // content, or concurrent-retry winner). 201 when a fresh row was
      // inserted. HTTP route maps the value directly to the response code.
      status: 200 | 201;
      token: string;
      url: string;
      documentPath: string;
      size: number;
    }
  | {
      ok: false;
      status: 400 | 403 | 404 | 409 | 413 | 500;
      code: CreateShareErrorCode;
      error: string;
    };

export type ListSharesResult =
  | { ok: true; shares: ShareRecord[] }
  | { ok: false; status: 500; code: "db-error"; error: string };

export type RevokeShareResult =
  | { ok: true; token: string; documentPath: string }
  | {
      ok: false;
      status: 403 | 404 | 500 | 502;
      code: RevokeShareErrorCode;
      error: string;
    };

// Hoisted chain-shape type. One declaration keeps createShare /
// listShares / revokeShare aligned on the exact PostgREST builder shape
// their queries expect. If supabase-js changes, drift here is loud.
interface KbShareLinksTable {
  select(cols: string): KbShareSelect;
  insert(row: Record<string, unknown>): Promise<{ error: { code?: string } | null }>;
  update(patch: Record<string, unknown>): {
    eq(
      col: string,
      val: unknown,
    ):
      | Promise<{ error: { message: string } | null }>
      | { error: { message: string } | null };
  };
}

interface KbShareSelect {
  eq(col: string, val: unknown): KbShareEq;
}

interface KbShareEq {
  eq(col: string, val: unknown): KbShareEq;
  maybeSingle(): Promise<{
    data: Record<string, unknown> | null;
    error: { message: string } | null;
  }>;
  single(): Promise<{
    data: Record<string, unknown> | null;
    error: { message: string } | null;
  }>;
  order(
    col: string,
    opts: { ascending: boolean },
  ): Promise<{
    data: Record<string, unknown>[] | null;
    error: { message: string } | null;
  }>;
}

// Minimal shape of the PostgREST-like service client we rely on. Typed
// as `Pick<SupabaseClient, "from">`-compatible so the real supabase-js
// client and test mocks both satisfy it without coupling to internal
// supabase-js generics.
export interface ShareServiceClient {
  from(table: string): unknown;
}

function shareLinksTable(client: ShareServiceClient): KbShareLinksTable {
  return client.from("kb_share_links") as KbShareLinksTable;
}

function invalidPath(error = "Invalid document path"): Extract<
  CreateShareResult,
  { ok: false }
> {
  return { ok: false, status: 400, code: "invalid-path", error };
}

async function findActiveShare(
  table: KbShareLinksTable,
  userId: string,
  documentPath: string,
  cols: string,
): Promise<Record<string, unknown> | null> {
  const { data } = await table
    .select(cols)
    .eq("user_id", userId)
    .eq("document_path", documentPath)
    .eq("revoked", false)
    .maybeSingle();
  return data;
}

export async function createShare(
  serviceClient: ShareServiceClient,
  userId: string,
  kbRoot: string,
  documentPath: string,
): Promise<CreateShareResult> {
  if (documentPath.includes("\0")) {
    return invalidPath();
  }
  const fullPath = path.join(kbRoot, documentPath);
  // isPathInWorkspace uses realpath, which collapses intermediate
  // symlinks — catches path-escape here. The terminal O_NOFOLLOW open
  // below catches symlinks at the leaf. No pre-open lstat, which would
  // reintroduce the CodeQL js/file-system-race TOCTOU window the
  // pre-PR route deliberately avoided.
  if (!isPathInWorkspace(fullPath, kbRoot)) {
    return invalidPath();
  }

  let handle: fs.promises.FileHandle;
  try {
    handle = await fs.promises.open(
      fullPath,
      fs.constants.O_RDONLY | fs.constants.O_NOFOLLOW,
    );
  } catch (err) {
    const code = (err as NodeJS.ErrnoException).code;
    if (code === "ELOOP" || code === "EMLINK") {
      // 403 to match KbAccessDeniedError; telemetry keys on `code`.
      return {
        ok: false,
        status: 403,
        code: "symlink-rejected",
        error: "Access denied",
      };
    }
    return {
      ok: false,
      status: 404,
      code: "not-found",
      error: "File not found",
    };
  }

  let size: number;
  let contentHash: string;
  try {
    const stat = await handle.stat();
    if (!stat.isFile()) {
      return {
        ok: false,
        status: 400,
        code: "not-a-file",
        error: "Invalid document path",
      };
    }
    if (stat.size > MAX_BINARY_SIZE) {
      return {
        ok: false,
        status: 413,
        code: "too-large",
        error: "File exceeds maximum size limit",
      };
    }
    size = stat.size;
    contentHash = await hashStream(handle.createReadStream({ autoClose: false }));
  } finally {
    await handle.close().catch(() => {});
  }

  const table = shareLinksTable(serviceClient);
  const existing = (await findActiveShare(
    table,
    userId,
    documentPath,
    "id, token, content_sha256",
  )) as { id: string; token: string; content_sha256: string | null } | null;

  if (existing) {
    if (existing.content_sha256 === contentHash) {
      return {
        ok: true,
        status: 200,
        token: existing.token,
        url: `/shared/${existing.token}`,
        documentPath,
        size,
      };
    }
    // Content drift: revoke stale row and issue a fresh token.
    // Same security invariant as the explicit revoke path (#2568): the
    // stale token's previously-cached 200 must be evicted from the CF
    // edge so the new content-drifted document is the only thing
    // reachable. Purge failure here is best-effort (the new token is
    // about to be issued and overwhelmingly more valuable than waiting
    // on CF to ack); Sentry alarms via reportSilentFallback inside the
    // helper so the operator sees the partial-failure state.
    await table.update({ revoked: true }).eq("id", existing.id);
    log.info(
      {
        event: "share_reissued_on_content_drift",
        userId,
        documentPath,
      },
      "revoked stale share and issuing new token (content changed)",
    );
    await purgeSharedToken(existing.token);
  }

  const token = randomBytes(SHARE_TOKEN_BYTES).toString("base64url");
  const { error: insertError } = await table.insert({
    user_id: userId,
    token,
    document_path: documentPath,
    content_sha256: contentHash,
  });

  if (insertError) {
    if ((insertError as { code?: string }).code === "23505") {
      const winner = (await findActiveShare(
        table,
        userId,
        documentPath,
        "token, content_sha256",
      )) as { token: string; content_sha256: string | null } | null;
      if (winner && winner.content_sha256 === contentHash) {
        return {
          ok: true,
          status: 200,
          token: winner.token,
          url: `/shared/${winner.token}`,
          documentPath,
          size,
        };
      }
      return {
        ok: false,
        status: 409,
        code: "concurrent-retry",
        error: "Concurrent share creation — retry",
      };
    }
    reportSilentFallback(insertError, {
      feature: "kb-share",
      op: "create",
      extra: { userId, documentPath },
    });
    return {
      ok: false,
      status: 500,
      code: "db-error",
      error: "Failed to create share link",
    };
  }

  log.info(
    { event: "share_created", userId, documentPath },
    "share link created",
  );
  return {
    ok: true,
    status: 201,
    token,
    url: `/shared/${token}`,
    documentPath,
    size,
  };
}

export async function listShares(
  serviceClient: ShareServiceClient,
  userId: string,
  filter?: { documentPath?: string },
): Promise<ListSharesResult> {
  interface RowShape {
    token: string;
    document_path: string;
    created_at: string;
    revoked: boolean;
  }

  const table = shareLinksTable(serviceClient);
  const userScoped = table
    .select("token, document_path, created_at, revoked")
    .eq("user_id", userId);
  const finalQuery = filter?.documentPath
    ? userScoped.eq("document_path", filter.documentPath)
    : userScoped;

  const { data, error } = await finalQuery.order("created_at", {
    ascending: false,
  });

  if (error) {
    reportSilentFallback(error as unknown as Error, {
      feature: "kb-share",
      op: "list",
      extra: { userId, documentPath: filter?.documentPath },
    });
    return {
      ok: false,
      status: 500,
      code: "db-error",
      error: "Failed to list shares",
    };
  }

  const shares: ShareRecord[] = ((data ?? []) as unknown as RowShape[]).map((row) => ({
    token: row.token,
    documentPath: row.document_path,
    createdAt: row.created_at,
    revoked: row.revoked,
  }));
  return { ok: true, shares };
}

export async function revokeShare(
  serviceClient: ShareServiceClient,
  userId: string,
  token: string,
): Promise<RevokeShareResult> {
  const table = shareLinksTable(serviceClient);

  const { data: shareLink, error: fetchError } = (await table
    .select("id, user_id, document_path")
    .eq("token", token)
    .single()) as {
    data: { id: string; user_id: string; document_path: string } | null;
    error: { message: string } | null;
  };

  if (fetchError || !shareLink) {
    return {
      ok: false,
      status: 404,
      code: "not-found",
      error: "Share link not found",
    };
  }

  if (shareLink.user_id !== userId) {
    return {
      ok: false,
      status: 403,
      code: "forbidden",
      error: "Forbidden",
    };
  }

  const updateResult = await table.update({ revoked: true }).eq("id", shareLink.id);

  if (updateResult.error) {
    reportSilentFallback(updateResult.error as unknown as Error, {
      feature: "kb-share",
      op: "revoke",
      extra: { userId, token },
    });
    return {
      ok: false,
      status: 500,
      code: "db-error",
      error: "Failed to revoke share link",
    };
  }

  // Audit-trail decoupling: emit `share_revoked` BEFORE the purge call so
  // the audit/observability pipeline sees every successful DB revoke,
  // even when the downstream CF purge fails (502 path below).
  log.info(
    { event: "share_revoked", userId, token },
    "share link revoked",
  );

  // Active CF edge purge so a previously-cached 200 doesn't keep serving
  // for the s-maxage TTL after the DB row is revoked. The helper alarms
  // to Sentry on every non-ok branch; do NOT re-emit reportSilentFallback
  // here. We surface 502 to the caller so the operator sees the
  // partial-failure state rather than a silent leak (#2568).
  const purgeResult = await purgeSharedToken(token);
  if (!purgeResult.ok) {
    return {
      ok: false,
      status: 502,
      code: "purge-failed",
      error: REVOKE_PURGE_FAILED_MESSAGE,
    };
  }

  return { ok: true, token, documentPath: shareLink.document_path };
}

// -----------------------------------------------------------------------------
// previewShare (#2322): view-parity projection of /api/shared/[token]
// -----------------------------------------------------------------------------

export type PreviewShareErrorCode =
  | "not-found"
  | "revoked"
  | "legacy-null-hash"
  | "content-changed"
  | "access-denied"
  | "too-large"
  | "invalid-path"
  | "db-error";

export type FirstPagePreview = PdfPreview | ImagePreview;

export type PreviewShareResult =
  | {
      ok: true;
      status: 200;
      token: string;
      documentPath: string;
      kind: "markdown" | "binary";
      contentType: string;
      size: number;
      filename: string;
      firstPagePreview?: FirstPagePreview;
    }
  | {
      ok: false;
      status: 404 | 403 | 410 | 413 | 500;
      code: PreviewShareErrorCode;
      error: string;
    };

type PreviewShareRow = {
  document_path: string;
  revoked: boolean;
  content_sha256: string | null;
  users:
    | { workspace_path: string | null; workspace_status: string | null }
    | { workspace_path: string | null; workspace_status: string | null }[]
    | null;
};

// Map any error thrown by validateBinaryFile / readContentRaw /
// openBinaryStream to a PreviewShareResult. Mirrors mapSharedError in the
// public route so both surfaces agree on terminal states.
function mapPreviewError(
  err: unknown,
  tokenPrefix: string,
  documentPath: string,
): Extract<PreviewShareResult, { ok: false }> {
  if (err instanceof KbAccessDeniedError) {
    return {
      ok: false,
      status: 403,
      code: "access-denied",
      error: "Access denied",
    };
  }
  if (err instanceof KbNotFoundError) {
    return {
      ok: false,
      status: 404,
      code: "not-found",
      error: "Document no longer available",
    };
  }
  if (err instanceof KbFileTooLargeError) {
    return {
      ok: false,
      status: 413,
      code: "too-large",
      error: err.message,
    };
  }
  if (err instanceof BinaryOpenError) {
    if (err.code === "content-changed") {
      return {
        ok: false,
        status: 410,
        code: "content-changed",
        error: "Document has changed since share was created",
      };
    }
    if (err.status === 403) {
      return {
        ok: false,
        status: 403,
        code: "access-denied",
        error: "Access denied",
      };
    }
    if (err.status === 404) {
      return {
        ok: false,
        status: 404,
        code: "not-found",
        error: "Document no longer available",
      };
    }
    // 500 / 503 — surface as db-error (closest generic we expose)
    reportSilentFallback(err, {
      feature: "kb-share",
      op: "preview",
      extra: { tokenPrefix, documentPath },
    });
    return {
      ok: false,
      status: 500,
      code: "db-error",
      error: "Failed to read document",
    };
  }
  reportSilentFallback(err, {
    feature: "kb-share",
    op: "preview",
    extra: { tokenPrefix, documentPath },
  });
  return {
    ok: false,
    status: 500,
    code: "db-error",
    error: "Unexpected error reading document",
  };
}

async function hashBinaryWithVerdictCache(
  token: string,
  meta: BinaryFileMetadata,
  expectedHash: string,
): Promise<"match" | "mismatch"> {
  const cached = shareHashVerdictCache.get(
    token,
    meta.ino,
    meta.mtimeMs,
    meta.size,
  );
  if (cached === true) return "match";

  const stream = await openBinaryStream(meta.filePath, {
    expected: { ino: meta.ino, size: meta.size },
  });
  const currentHash = await hashStream(stream);
  if (currentHash !== expectedHash) return "mismatch";
  shareHashVerdictCache.set(token, meta.ino, meta.mtimeMs, meta.size);
  return "match";
}

async function maybeFirstPagePreview(
  meta: BinaryFileMetadata,
): Promise<FirstPagePreview | undefined> {
  if (meta.contentType === "application/pdf") {
    const stream = await openBinaryStream(meta.filePath, {
      expected: { ino: meta.ino, size: meta.size },
    });
    const preview = await readPdfMetadata(stream);
    return preview ?? undefined;
  }
  if (deriveBinaryKind(meta) === "image") {
    const stream = await openBinaryStream(meta.filePath, {
      expected: { ino: meta.ino, size: meta.size },
    });
    const preview = await readImageMetadata(stream);
    return preview ?? undefined;
  }
  return undefined;
}

/**
 * Preview what a recipient sees at /shared/[token]. Runs the same
 * ownership-agnostic share-row lookup + hash gate as the public HTTP
 * route. Returns metadata (no bytes) for the agent to verify the link
 * renders correctly. Called by the kb_share_preview MCP tool.
 *
 * Reuses validateBinaryFile + readContentRaw via the stored document
 * path; does NOT re-implement traversal / null-byte / symlink checks.
 * TOCTOU-safe: every openBinaryStream call passes `expected: { ino, size }`
 * so a rename-swap between validate and read closes out as content-changed.
 */
export async function previewShare(
  serviceClient: ShareServiceClient,
  token: string,
  kbRootResolver: (workspacePath: string) => string = (w) =>
    path.join(w, "knowledge-base"),
): Promise<PreviewShareResult> {
  const tokenPrefix = token.slice(0, 8);

  // Look up the share row and embedded owner workspace. Same select shape
  // as prepareSharedRequest() in app/api/shared/[token]/route.ts.
  let row: PreviewShareRow | null;
  try {
    const result = (await (
      serviceClient.from("kb_share_links") as {
        select: (cols: string) => {
          eq: (col: string, val: unknown) => {
            single: () => Promise<{
              data: PreviewShareRow | null;
              error: { code?: string; message: string } | null;
            }>;
          };
        };
      }
    )
      .select(
        "document_path, revoked, content_sha256, users!inner(workspace_path, workspace_status)",
      )
      .eq("token", token)
      .single()) as {
      data: PreviewShareRow | null;
      error: { code?: string; message: string } | null;
    };

    if (result.error) {
      // PGRST116 = zero rows on .single() — treat as not-found, not db-error.
      if (result.error.code === "PGRST116") {
        return {
          ok: false,
          status: 404,
          code: "not-found",
          error: "Document no longer available",
        };
      }
      reportSilentFallback(result.error, {
        feature: "kb-share",
        op: "preview",
        extra: { tokenPrefix },
      });
      return {
        ok: false,
        status: 500,
        code: "db-error",
        error: "Failed to look up share",
      };
    }
    row = result.data;
  } catch (err) {
    reportSilentFallback(err, {
      feature: "kb-share",
      op: "preview",
      extra: { tokenPrefix },
    });
    return {
      ok: false,
      status: 500,
      code: "db-error",
      error: "Failed to look up share",
    };
  }

  if (!row) {
    return {
      ok: false,
      status: 404,
      code: "not-found",
      error: "Document no longer available",
    };
  }

  if (row.revoked) {
    return {
      ok: false,
      status: 410,
      code: "revoked",
      error: "This link has been disabled",
    };
  }

  if (!row.content_sha256) {
    // Migration 026 installs a CHECK constraint that makes a null hash on
    // a non-revoked row unrepresentable. Hitting this branch means the
    // DB invariant has been broken — alarm to Sentry so a schema regression
    // surfaces in the dashboard, not just in a pino line.
    reportSilentFallback(null, {
      feature: "kb-share",
      op: "preview-invariant",
      message: "null content_sha256 on non-revoked share (schema invariant broken)",
      extra: { tokenPrefix },
    });
    return {
      ok: false,
      status: 410,
      code: "legacy-null-hash",
      error: "This link is from an older share system and is no longer valid.",
    };
  }

  const owner = Array.isArray(row.users) ? row.users[0] : row.users;
  if (!owner?.workspace_path || owner.workspace_status !== "ready") {
    return {
      ok: false,
      status: 404,
      code: "not-found",
      error: "Document no longer available",
    };
  }

  const kbRoot = kbRootResolver(owner.workspace_path);
  const documentPath = row.document_path;
  const contentSha256 = row.content_sha256;

  if (isMarkdownKbPath(documentPath)) {
    try {
      const { buffer } = await readContentRaw(kbRoot, documentPath);
      if (hashBytes(buffer) !== contentSha256) {
        return {
          ok: false,
          status: 410,
          code: "content-changed",
          error: "Document has changed since share was created",
        };
      }
      return {
        ok: true,
        status: 200,
        token,
        documentPath,
        kind: "markdown",
        contentType: "text/markdown",
        size: buffer.length,
        filename: path.basename(documentPath),
      };
    } catch (err) {
      return mapPreviewError(err, tokenPrefix, documentPath);
    }
  }

  // Binary branch
  let meta: BinaryFileMetadata;
  try {
    meta = await validateBinaryFile(kbRoot, documentPath);
  } catch (err) {
    return mapPreviewError(err, tokenPrefix, documentPath);
  }

  try {
    const verdict = await hashBinaryWithVerdictCache(
      token,
      meta,
      contentSha256,
    );
    if (verdict === "mismatch") {
      return {
        ok: false,
        status: 410,
        code: "content-changed",
        error: "Document has changed since share was created",
      };
    }
  } catch (err) {
    return mapPreviewError(err, tokenPrefix, documentPath);
  }

  let firstPagePreview: FirstPagePreview | undefined;
  try {
    firstPagePreview = await maybeFirstPagePreview(meta);
  } catch (err) {
    // Preview is best-effort — upstream readers already silent-fallback,
    // but a BinaryOpenError("content-changed") on the second open is a
    // genuine terminal state: the file mutated between hash pass and
    // preview pass. Surface as content-changed to match the route.
    if (err instanceof BinaryOpenError && err.code === "content-changed") {
      return {
        ok: false,
        status: 410,
        code: "content-changed",
        error: "Document has changed since share was created",
      };
    }
    // Any other error → silent-fallback, still return core metadata.
    reportSilentFallback(err, {
      feature: "kb-share",
      op: "preview",
      extra: { tokenPrefix, documentPath, stage: "first-page-preview" },
    });
    firstPagePreview = undefined;
  }

  const result: Extract<PreviewShareResult, { ok: true }> = {
    ok: true,
    status: 200,
    token,
    documentPath,
    kind: "binary",
    contentType: meta.contentType,
    size: meta.size,
    filename: meta.rawName,
  };
  if (firstPagePreview !== undefined) {
    result.firstPagePreview = firstPagePreview;
  }
  return result;
}
