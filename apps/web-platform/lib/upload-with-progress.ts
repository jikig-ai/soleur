import { reportSilentFallback } from "@/lib/client-observability";
import { sanitizeAttachmentFilename } from "@/lib/attachment-constants";

/**
 * Upload a file via XHR with progress tracking.
 * Extracted from chat-input.tsx for reuse by the chat page's pending-file upload flow.
 *
 * This is the single transport chokepoint for both callers (composer
 * chat-input.tsx and first-run lib/upload-attachments.ts). A PUT failure here
 * must reach Sentry: the signed `url` embeds a short-TTL token, so it is never
 * reported — only xhr.status (0 = network/CSP block vs 4xx/5xx = storage
 * rejected) and the sanitized filename.
 */
export function uploadWithProgress(
  url: string,
  file: File,
  contentType: string,
  onProgress: (percent: number) => void,
): { promise: Promise<void>; xhr: XMLHttpRequest } {
  const xhr = new XMLHttpRequest();

  const promise = new Promise<void>((resolve, reject) => {
    xhr.open("PUT", url);
    xhr.setRequestHeader("Content-Type", contentType);

    xhr.upload.onprogress = (event) => {
      if (event.lengthComputable) {
        const percent = Math.round((event.loaded / event.total) * 100);
        onProgress(percent);
      }
    };

    xhr.onload = () => {
      if (xhr.status >= 200 && xhr.status < 300) {
        resolve();
      } else {
        const err = new Error("Upload to storage failed");
        reportSilentFallback(err, {
          feature: "attachments",
          op: "storage-put",
          extra: { status: xhr.status, filename: sanitizeAttachmentFilename(file.name) },
        });
        reject(err);
      }
    };

    xhr.onerror = () => {
      const err = new Error("Upload to storage failed");
      reportSilentFallback(err, {
        feature: "attachments",
        op: "storage-put",
        extra: { status: xhr.status, filename: sanitizeAttachmentFilename(file.name) },
      });
      reject(err);
    };
    xhr.onabort = () => reject(new Error("Upload cancelled"));
    xhr.send(file);
  });

  return { promise, xhr };
}
