/**
 * Shared attachment pipeline used by both `agent-runner.ts:sendUserMessage`
 * (legacy single-leader path) and `cc-dispatcher.ts:dispatchSoleurGo`
 * (cc-soleur-go / KB Concierge path). Lifted verbatim from
 * `agent-runner.ts:1342-1421` (#3254) so the cc path stops silently
 * dropping `msg.attachments`.
 *
 * The helper:
 *  1. Validates each attachment ref against the per-user/per-conversation
 *     storage prefix and rejects path-traversal (`..`).
 *  2. Validates the content-type against `ALLOWED_ATTACHMENT_TYPES`.
 *  3. Sanitizes filenames by stripping `/` and `\`.
 *  4. Inserts one `message_attachments` row per attachment, FK'd to the
 *     caller-provided `messageId`. Caller is responsible for inserting
 *     the parent `messages` row before calling this helper.
 *  5. Looks up the user's workspace path, mkdirs the per-conv attachment
 *     dir, and downloads each file from the `chat-attachments` storage
 *     bucket into `<workspace>/attachments/<conversationId>/<random>.<ext>`.
 *  6. Returns an `attachmentContext` text block — the same shape the
 *     legacy path appended to the LLM prompt — or `undefined` when no
 *     files landed (workspace lookup empty, or every download failed).
 */
import { randomUUID } from "crypto";
import { mkdir, writeFile } from "fs/promises";
import path from "path";

import type { SupabaseClient } from "@supabase/supabase-js";

import type { AttachmentRef } from "@/lib/types";
import { ALLOWED_ATTACHMENT_TYPES } from "@/lib/attachment-constants";
import {
  ERR_ATTACHMENT_NOT_FOUND,
  ERR_UNSUPPORTED_FILE_TYPE,
  ERR_UPLOAD_FAILED,
} from "./error-messages";
import { createChildLogger } from "./logger";

const log = createChildLogger("attachment-pipeline");

export interface PersistAttachmentsArgs {
  /** Service-role Supabase client. Caller owns lifetime. */
  supabase: SupabaseClient;
  userId: string;
  conversationId: string;
  /**
   * UUID of the parent `messages` row. The helper FKs every
   * `message_attachments` row to this id; caller MUST insert the
   * `messages` row BEFORE calling.
   */
  messageId: string;
  attachments: AttachmentRef[];
}

export interface PersistAttachmentsResult {
  /**
   * Text block to append to the LLM prompt, or `undefined` when no files
   * landed on disk (empty workspace path, or every download failed).
   * Format:
   *   "The user attached the following files:\n- <name> (<type>, <bytes>): <path>"
   */
  attachmentContext: string | undefined;
}

const EXT_MAP: Record<string, string> = {
  "image/png": "png",
  "image/jpeg": "jpeg",
  "image/gif": "gif",
  "image/webp": "webp",
  "application/pdf": "pdf",
};

export async function persistAndDownloadAttachments(
  args: PersistAttachmentsArgs,
): Promise<PersistAttachmentsResult> {
  const { supabase, userId, conversationId, messageId, attachments } = args;

  if (attachments.length === 0) {
    return { attachmentContext: undefined };
  }

  // Validate and sanitize each attachment (defense-in-depth — client is untrusted).
  const pathPrefix = `${userId}/${conversationId}/`;

  for (const att of attachments) {
    if (!att.storagePath.startsWith(pathPrefix) || att.storagePath.includes("..")) {
      throw new Error(ERR_ATTACHMENT_NOT_FOUND);
    }
    if (!ALLOWED_ATTACHMENT_TYPES.has(att.contentType)) {
      throw new Error(ERR_UNSUPPORTED_FILE_TYPE);
    }
    att.filename = att.filename.replace(/[/\\]/g, "_");
  }

  // Insert attachment metadata rows.
  const attachmentRows = attachments.map((att) => ({
    message_id: messageId,
    storage_path: att.storagePath,
    filename: att.filename,
    content_type: att.contentType,
    size_bytes: att.sizeBytes,
  }));

  const { error: attErr } = await supabase
    .from("message_attachments")
    .insert(attachmentRows);

  if (attErr) {
    log.error({ err: attErr, messageId }, "Failed to save attachment metadata");
    throw new Error(ERR_UPLOAD_FAILED);
  }

  // Download files to workspace for agent access.
  const { data: user } = await supabase
    .from("users")
    .select("workspace_path")
    .eq("id", userId)
    .single();

  const workspacePath = (user as { workspace_path?: string } | null)?.workspace_path;
  if (!workspacePath) {
    return { attachmentContext: undefined };
  }

  const attachDir = path.join(workspacePath, "attachments", conversationId);
  await mkdir(attachDir, { recursive: true });

  const results = await Promise.allSettled(
    attachments.map(async (att) => {
      const { data: fileData, error: dlErr } = await supabase
        .storage
        .from("chat-attachments")
        .download(att.storagePath);

      if (dlErr || !fileData) {
        log.error({ err: dlErr, storagePath: att.storagePath }, "Failed to download attachment");
        return null;
      }

      const ext = EXT_MAP[att.contentType] || "bin";
      const localPath = path.join(attachDir, `${randomUUID()}.${ext}`);
      await writeFile(localPath, Buffer.from(await fileData.arrayBuffer()));
      return `- ${att.filename} (${att.contentType}, ${att.sizeBytes} bytes): ${localPath}`;
    }),
  );

  const filePaths = results
    .filter((r): r is PromiseFulfilledResult<string | null> => r.status === "fulfilled")
    .map((r) => r.value)
    .filter((v): v is string => v !== null);

  if (filePaths.length === 0) {
    return { attachmentContext: undefined };
  }

  return {
    attachmentContext: `The user attached the following files:\n${filePaths.join("\n")}`,
  };
}
