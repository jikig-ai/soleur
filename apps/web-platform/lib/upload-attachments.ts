import * as Sentry from "@sentry/nextjs";
import type { AttachmentRef } from "@/lib/types";
import { uploadWithProgress } from "@/lib/upload-with-progress";

export interface UploadPendingFilesOptions {
  /** Invoked as each file progresses. `fileIndex` is the original 0-based
   *  position in the input array so callers can map progress back to UI. */
  onProgress?: (fileIndex: number, percent: number) => void;
  /** Cancels the batch: checked before each file, and aborts the in-flight
   *  presign fetch / storage PUT. Refs already uploaded are still returned. */
  signal?: AbortSignal;
  /** Invoked with each ref as soon as its file finishes, so a caller that stops
   *  waiting (deadline) can salvage the files that already made it. */
  onUploaded?: (ref: AttachmentRef) => void;
}

/**
 * Truncate + strip control characters from a user-controlled filename so it
 * is safe to pass to `console.warn` / Sentry payloads. The browser File API
 * accepts arbitrary strings; an attacker-chosen filename can carry log-injection
 * characters (`\r\n`, ANSI escapes) or be unbounded in size.
 */
function sanitizeFilenameForLog(name: string): string {
  return String(name).slice(0, 256).replace(/[\x00-\x1f\x7f]/g, "?");
}

/**
 * Re-wrap an error with a sanitized message for telemetry. `uploadWithProgress`
 * rejects with messages that could include the signed storage URL; shipping
 * that URL to Sentry would leak the signature token into issue payloads until
 * the short TTL expires. Stash the original message length as diagnostic
 * context without the URL body.
 */
function sanitizeErrorForLog(err: unknown, stage: "presign" | "storage"): Error {
  const original = err instanceof Error ? err.message : String(err);
  return new Error(`[kb-chat] ${stage} upload failed (original message length ${original.length})`);
}

/**
 * Shared helper for the presign → storage-PUT upload pattern used by the
 * `chat-surface.tsx` pending-files effect. Per-file failures (presign non-2xx,
 * storage upload reject) are logged via `console.warn` + `Sentry` so the batch
 * still completes with the successful files — replacing the prior silent
 * `catch {}` in chat-surface.
 *
 * NOTE: `chat-input.tsx` `uploadAttachments` intentionally keeps its own
 * presign+upload loop because it carries per-attachment UI state (progress,
 * inline error display, `activeXhrs` for cancellation) that this helper does
 * not expose. Any change to the presign request shape must be applied in both
 * places.
 *
 * Presign error codes are an HTTP vocabulary; `attachmentErrorCopy`
 * (`lib/attachment-error-copy.ts`) is the human-copy mapping for them and is
 * the one to reuse if this helper ever surfaces failures to the user (#9316).
 */
export async function uploadPendingFiles(
  files: File[],
  conversationId: string,
  opts?: UploadPendingFilesOptions,
): Promise<AttachmentRef[]> {
  const uploaded: AttachmentRef[] = [];

  const signal = opts?.signal;

  for (let i = 0; i < files.length; i++) {
    if (signal?.aborted) break;
    const file = files[i];
    const safeFilename = sanitizeFilenameForLog(file.name);
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
        signal,
      });

      if (!presignRes.ok) {
        const sanitized = new Error(
          `[kb-chat] presign failed (status ${presignRes.status})`,
        );
        console.warn("[kb-chat] pending upload failed (presign)", {
          err: sanitized,
          filename: safeFilename,
        });
        Sentry.captureException(sanitized, { extra: { filename: safeFilename } });
        continue;
      }

      const { uploadUrl, storagePath } = (await presignRes.json()) as {
        uploadUrl: string;
        storagePath: string;
      };

      if (signal?.aborted) break;

      const { promise, xhr } = uploadWithProgress(
        uploadUrl,
        file,
        file.type,
        (percent) => opts?.onProgress?.(i, percent),
      );
      const abortXhr = () => xhr.abort();
      signal?.addEventListener("abort", abortXhr, { once: true });
      try {
        await promise;
      } finally {
        signal?.removeEventListener("abort", abortXhr);
      }

      const ref: AttachmentRef = {
        storagePath,
        filename: file.name,
        contentType: file.type,
        sizeBytes: file.size,
      };
      uploaded.push(ref);
      opts?.onUploaded?.(ref);
    } catch (err) {
      // A cancelled batch is not a failure: stop quietly (no Sentry noise).
      if (signal?.aborted) break;
      // Sanitize: `uploadWithProgress` can reject with a message containing
      // the signed storage URL, which would leak into Sentry.
      const sanitized = sanitizeErrorForLog(err, "storage");
      console.warn("[kb-chat] pending upload failed (storage)", {
        err: sanitized,
        filename: safeFilename,
      });
      Sentry.captureException(sanitized, { extra: { filename: safeFilename } });
    }
  }

  return uploaded;
}
