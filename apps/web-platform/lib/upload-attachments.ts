import * as Sentry from "@sentry/nextjs";
import type { AttachmentRef } from "@/lib/types";
import { uploadWithProgress } from "@/lib/upload-with-progress";

export interface UploadPendingFilesOptions {
  /** Invoked as each file progresses. `fileIndex` is the original 0-based
   *  position in the input array so callers can map progress back to UI. */
  onProgress?: (fileIndex: number, percent: number) => void;
}

/**
 * Shared helper for the presign → storage-PUT upload pattern used by both
 * `chat-input.tsx` (`uploadAttachments`) and `chat-surface.tsx` (pending-files
 * effect). Per-file failures (presign non-2xx, storage upload reject) are
 * logged via console.warn + Sentry so the batch still completes with the
 * successful files — replacing the prior silent `catch {}` in chat-surface.
 */
export async function uploadPendingFiles(
  files: File[],
  conversationId: string,
  opts?: UploadPendingFilesOptions,
): Promise<AttachmentRef[]> {
  const uploaded: AttachmentRef[] = [];

  for (let i = 0; i < files.length; i++) {
    const file = files[i];
    try {
      const presignRes = await fetch("/api/attachments/presign", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          filename: file.name,
          contentType: file.type,
          sizeBytes: file.size,
          conversationId,
        }),
      });

      if (!presignRes.ok) {
        const err = new Error(
          `[kb-chat] presign failed for ${file.name} (status ${presignRes.status})`,
        );
        console.warn("[kb-chat] pending upload failed", { err, filename: file.name });
        Sentry.captureException(err);
        continue;
      }

      const { uploadUrl, storagePath } = (await presignRes.json()) as {
        uploadUrl: string;
        storagePath: string;
      };

      const { promise } = uploadWithProgress(
        uploadUrl,
        file,
        file.type,
        (percent) => opts?.onProgress?.(i, percent),
      );
      await promise;

      uploaded.push({
        storagePath,
        filename: file.name,
        contentType: file.type,
        sizeBytes: file.size,
      });
    } catch (err) {
      console.warn("[kb-chat] pending upload failed", { err, filename: file.name });
      Sentry.captureException(err);
    }
  }

  return uploaded;
}
