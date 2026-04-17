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
import { MAX_BINARY_SIZE } from "@/server/kb-binary-response";
import { hashStream } from "@/server/kb-content-hash";
import { createChildLogger } from "@/server/logger";
import { reportSilentFallback } from "@/server/observability";

const log = createChildLogger("kb-share");

// 256 bits of entropy, ~43 base64url chars. Hoisted so the "why 32"
// is explicit at the call site — security-relevant constant.
const SHARE_TOKEN_BYTES = 32;

export type CreateShareErrorCode =
  | "invalid-path"
  | "not-found"
  | "not-a-file"
  | "symlink-rejected"
  | "too-large"
  | "concurrent-retry"
  | "db-error";

export type RevokeShareErrorCode = "forbidden" | "not-found" | "db-error";

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
      status: 400 | 404 | 409 | 413 | 500;
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
      status: 403 | 404 | 500;
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
    await table.update({ revoked: true }).eq("id", existing.id);
    log.info(
      {
        event: "share_reissued_on_content_drift",
        userId,
        documentPath,
      },
      "revoked stale share and issuing new token (content changed)",
    );
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

  log.info(
    { event: "share_revoked", userId, token },
    "share link revoked",
  );
  return { ok: true, token, documentPath: shareLink.document_path };
}
