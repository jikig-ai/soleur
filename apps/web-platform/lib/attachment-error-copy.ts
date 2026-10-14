import { MAX_ATTACHMENT_SIZE, type PresignErrorCode } from "@/lib/attachment-constants";

const GENERIC = "Upload failed. Check your connection and try again.";

const COPY: Record<PresignErrorCode, string> = {
  // The route also returns this code for `sizeBytes <= 0`.
  file_too_large: `File is empty or larger than ${MAX_ATTACHMENT_SIZE / 1024 / 1024} MB.`,
  unsupported_file_type:
    "This file type isn't supported. You can attach images, PDFs, .md or .txt files.",
  // The tile has no retry affordance; nearly unreachable once presign tolerates
  // an unmaterialized conversation id.
  conversation_not_found:
    "This conversation isn't ready for attachments yet. Remove the file and attach it again.",
  not_a_workspace_member: "You don't have access to attach files to this conversation.",
  unauthorized: "Your session expired. Sign in again to attach files.",
  invalid_request: GENERIC,
  upload_failed: GENERIC,
};

/**
 * Human copy for attachment-tile errors, keyed by the presign route's error
 * code (`app/api/attachments/presign/route.ts`). Presign failures surface as
 * `new Error(code)`, so the thrown message IS the code; anything else (storage
 * PUT failures, network errors, `"Presign failed"`) is not a code and falls to
 * the generic copy. Raw codes and XHR messages must never render on a tile.
 *
 * This is the vocabulary to reuse for any other attachment-upload surface
 * (e.g. the first-run failure notice tracked in #9316).
 */
export function attachmentErrorCopy(code?: string): string {
  if (code && Object.prototype.hasOwnProperty.call(COPY, code)) return COPY[code as PresignErrorCode];
  return GENERIC;
}
