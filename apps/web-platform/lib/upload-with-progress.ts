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

    // One failure leg for both storage-reject (non-2xx onload) and
    // network/CSP block (onerror): report with the discriminating
    // xhr.status, then reject — finally-guaranteed so a throwing report can
    // never hang the caller. `reportedToSentry` marks the error so callers
    // with their own catch (lib/upload-attachments.ts) skip re-capture.
    const fail = () => {
      const err = new Error("Upload to storage failed") as Error & {
        reportedToSentry?: boolean;
      };
      try {
        reportSilentFallback(err, {
          feature: "attachments",
          op: "storage-put",
          extra: {
            status: xhr.status,
            filename: sanitizeAttachmentFilename(file.name),
          },
        });
        err.reportedToSentry = true;
      } finally {
        reject(err);
      }
    };

    xhr.onload = () => {
      if (xhr.status >= 200 && xhr.status < 300) {
        resolve();
      } else {
        fail();
      }
    };

    xhr.onerror = fail;
    xhr.onabort = () => reject(new Error("Upload cancelled"));
    xhr.send(file);
  });

  return { promise, xhr };
}
