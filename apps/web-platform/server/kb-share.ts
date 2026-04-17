// Share lifecycle module: validates a KB document, hashes it, and writes
// the DB row for `kb_share_links`. Consumed by both HTTP routes
// (app/api/kb/share/route.ts, [token]/route.ts) and the in-process MCP
// tools (server/kb-share-tools.ts) so a single hardened implementation
// covers both surfaces. Closes #2298 by hoisting the validation and
// lifecycle out of the route handlers.
//
// Error shape is a tagged union with string-literal `code` values so
// telemetry and tests can discriminate failure modes without string
// matching on messages. `status` mirrors the HTTP status the callers
// should use (contract preserves the existing HTTP route behavior —
// null-byte/path-escape/symlink/non-file all 400, missing 404, size 413).

import fs from "node:fs";
import path from "node:path";
import { randomBytes } from "node:crypto";
import * as Sentry from "@sentry/nextjs";
import { isPathInWorkspace } from "@/server/sandbox";
import { MAX_BINARY_SIZE } from "@/server/kb-binary-response";
import { hashStream } from "@/server/kb-content-hash";
import logger from "@/server/logger";

export type ShareErrorCode =
  | "invalid-path"
  | "not-found"
  | "not-a-file"
  | "symlink-rejected"
  | "too-large"
  | "concurrent-retry"
  | "forbidden"
  | "db-error";

export interface ShareRecord {
  token: string;
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
      code: ShareErrorCode;
      error: string;
    };

export type ListSharesResult =
  | { ok: true; shares: ShareRecord[] }
  | { ok: false; status: 500; code: "db-error"; error: string };

export type RevokeShareResult =
  | { ok: true; token: string }
  | {
      ok: false;
      status: 403 | 404 | 500;
      code: ShareErrorCode;
      error: string;
    };

// Minimal shape of the PostgREST-like service client we rely on. Typed
// loosely so the HTTP routes (supabase-js v2 client) and test mocks both
// satisfy it without coupling to internal supabase-js generics.
export interface ShareServiceClient {
  from(table: string): unknown;
}

function invalidPath(error = "Invalid document path"): CreateShareResult {
  return { ok: false, status: 400, code: "invalid-path", error };
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
  // lstat-first so a symlink (even one inside kbRoot) produces the
  // discriminative "symlink-rejected" code. isPathInWorkspace resolves
  // realpath and would collapse symlinks-pointing-outside into a generic
  // "invalid-path" — losing the signal telemetry needs.
  try {
    const lstat = await fs.promises.lstat(fullPath);
    if (lstat.isSymbolicLink()) {
      return {
        ok: false,
        status: 400,
        code: "symlink-rejected",
        error: "Invalid document path",
      };
    }
  } catch (err) {
    const code = (err as NodeJS.ErrnoException).code;
    if (code !== "ENOENT") {
      // Non-ENOENT lstat failures (ELOOP, EACCES) — treat as invalid.
      return invalidPath();
    }
    // ENOENT passes through to isPathInWorkspace / open which yield
    // the canonical "not-found" after workspace validation.
  }
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
      return {
        ok: false,
        status: 400,
        code: "symlink-rejected",
        error: "Invalid document path",
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

  const table = serviceClient.from("kb_share_links") as {
    select: (cols: string) => unknown;
    insert: (row: Record<string, unknown>) => Promise<{ error: unknown }>;
    update: (patch: Record<string, unknown>) => {
      eq: (col: string, val: unknown) => Promise<{ error: unknown }> | { error: unknown };
    };
  };

  const existingChain = (table.select("id, token, content_sha256") as {
    eq: (col: string, val: unknown) => {
      eq: (col: string, val: unknown) => {
        eq: (col: string, val: unknown) => {
          maybeSingle: () => Promise<{
            data: { id: string; token: string; content_sha256: string | null } | null;
            error: unknown;
          }>;
        };
      };
    };
  })
    .eq("user_id", userId)
    .eq("document_path", documentPath)
    .eq("revoked", false);
  const { data: existing } = await existingChain.maybeSingle();

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
    await (table.update({ revoked: true }).eq("id", existing.id) as
      | Promise<{ error: unknown }>
      | { error: unknown });
    logger.info(
      {
        event: "share_reissued_on_content_drift",
        userId,
        documentPath,
      },
      "kb/share: revoked stale share and issuing new token (content changed)",
    );
  }

  const token = randomBytes(32).toString("base64url");
  const { error: insertError } = await table.insert({
    user_id: userId,
    token,
    document_path: documentPath,
    content_sha256: contentHash,
  });

  if (insertError) {
    if ((insertError as { code?: string }).code === "23505") {
      const winnerChain = (table.select("token, content_sha256") as {
        eq: (col: string, val: unknown) => {
          eq: (col: string, val: unknown) => {
            eq: (col: string, val: unknown) => {
              maybeSingle: () => Promise<{
                data: { token: string; content_sha256: string | null } | null;
                error: unknown;
              }>;
            };
          };
        };
      })
        .eq("user_id", userId)
        .eq("document_path", documentPath)
        .eq("revoked", false);
      const { data: winner } = await winnerChain.maybeSingle();
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
    logger.error(
      { err: insertError, userId, documentPath },
      "kb/share: failed to create share link",
    );
    Sentry.captureException(insertError, {
      tags: { feature: "kb-share", op: "create" },
      extra: { userId, documentPath },
    });
    return {
      ok: false,
      status: 500,
      code: "db-error",
      error: "Failed to create share link",
    };
  }

  logger.info(
    { event: "share_created", userId, documentPath },
    "kb/share: share link created",
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
  const table = serviceClient.from("kb_share_links") as {
    select: (cols: string) => {
      eq: (col: string, val: unknown) => {
        eq: (col: string, val: unknown) => {
          order: (
            col: string,
            opts: { ascending: boolean },
          ) => Promise<{ data: RowShape[] | null; error: { message: string } | null }>;
        };
        order: (
          col: string,
          opts: { ascending: boolean },
        ) => Promise<{ data: RowShape[] | null; error: { message: string } | null }>;
      };
    };
  };

  interface RowShape {
    token: string;
    document_path: string;
    created_at: string;
    revoked: boolean;
  }

  const userScoped = table.select("token, document_path, created_at, revoked").eq(
    "user_id",
    userId,
  );
  const finalQuery = filter?.documentPath
    ? userScoped.eq("document_path", filter.documentPath)
    : userScoped;

  const { data, error } = await finalQuery.order("created_at", { ascending: false });

  if (error) {
    logger.error(
      { err: error, userId, documentPath: filter?.documentPath },
      "kb/share: failed to list shares",
    );
    Sentry.captureException(error, {
      tags: { feature: "kb-share", op: "list" },
      extra: { userId, documentPath: filter?.documentPath },
    });
    return {
      ok: false,
      status: 500,
      code: "db-error",
      error: "Failed to list shares",
    };
  }

  const shares: ShareRecord[] = (data ?? []).map((row) => ({
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
  const table = serviceClient.from("kb_share_links") as {
    select: (cols: string) => {
      eq: (col: string, val: unknown) => {
        single: () => Promise<{
          data: { id: string; user_id: string } | null;
          error: { message: string } | null;
        }>;
      };
    };
    update: (patch: Record<string, unknown>) => {
      eq: (col: string, val: unknown) =>
        | Promise<{ error: { message: string } | null }>
        | { error: { message: string } | null };
    };
  };

  const { data: shareLink, error: fetchError } = await table
    .select("id, user_id")
    .eq("token", token)
    .single();

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
    logger.error(
      { err: updateResult.error, userId, token },
      "kb/share: failed to revoke share link",
    );
    Sentry.captureException(updateResult.error, {
      tags: { feature: "kb-share", op: "revoke" },
      extra: { userId, token },
    });
    return {
      ok: false,
      status: 500,
      code: "db-error",
      error: "Failed to revoke share link",
    };
  }

  logger.info(
    { event: "share_revoked", userId, token },
    "kb/share: share link revoked",
  );
  return { ok: true, token };
}
