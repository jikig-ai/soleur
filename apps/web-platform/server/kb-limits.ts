/**
 * Shared policy constants for KB binary serving and share-link gating.
 *
 * Consumers:
 * - `server/kb-binary-response.ts` — validates file size, maps extension
 *   → Content-Type, emits the binary response.
 * - `server/kb-share.ts` — gates share-link creation by size.
 * - `server/agent-runner.ts` — surfaces the MB limit in agent error text.
 * - `server/kb-file-kind.ts` — classifies by Content-Type using this map.
 *
 * Adding a new attachment-only extension: extend the `classifyByExtension`
 * switch in `kb-file-kind.ts` (single source of truth for kind). Adding a
 * new inline Content-Type: extend `CONTENT_TYPE_MAP` here.
 */

export const MAX_BINARY_SIZE = 50 * 1024 * 1024; // 50 MB

export const CONTENT_TYPE_MAP: Record<string, string> = {
  ".png": "image/png",
  ".jpg": "image/jpeg",
  ".jpeg": "image/jpeg",
  ".gif": "image/gif",
  ".webp": "image/webp",
  ".svg": "image/svg+xml",
  ".pdf": "application/pdf",
  ".csv": "text/csv",
  ".txt": "text/plain",
  ".docx":
    "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
};
