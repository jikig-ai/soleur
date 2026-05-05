/**
 * Detection helper for `[Image #N]` placeholders that the
 * `claude-agent-sdk` CLI emits inside its interactive text-editor surface.
 *
 * These placeholders are NOT supposed to leave the SDK's textarea — when
 * they reach a server-side prompt or a chat history record, image bytes
 * have been silently dropped while the marker text survived end-to-end.
 *
 * Used at two boundaries to prevent the leak:
 *   - Server: `apps/web-platform/server/ws-handler.ts` strips inbound
 *     `chat` content and emits `errorCode: "image_paste_lost"`.
 *   - Client: `apps/web-platform/components/chat/chat-input.tsx`
 *     `handlePaste` rejects `text/plain` paste data containing the marker.
 *
 * The regex uses `.replace(re, () => { count++; return "" })` rather than
 * `.test() + .replace()` to sidestep `lastIndex` reset bugs on the global
 * flag (see `2026-04-17-pii-regex-scrubber-three-invariants.md`).
 */

export const IMAGE_PLACEHOLDER_REGEX = /\[Image #\d+\]/g;

export interface DetectImagePlaceholdersResult {
  count: number;
  cleaned: string;
}

export function detectImagePlaceholders(text: string): DetectImagePlaceholdersResult {
  if (typeof text !== "string" || text.length === 0) {
    return { count: 0, cleaned: text ?? "" };
  }
  let count = 0;
  const stripped = text.replace(IMAGE_PLACEHOLDER_REGEX, () => {
    count += 1;
    return "";
  });
  if (count === 0) {
    return { count: 0, cleaned: text };
  }
  const cleaned = stripped.replace(/\s{2,}/g, " ").trim();
  return { count, cleaned };
}
