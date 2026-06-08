// feat-concierge-stream-commands — wire-size caps + UTF-8 byte-cap util for
// the streamed-command surface. Extracted from `cc-dispatcher.ts` so the
// debug-mode emit path (`server/debug-event.ts`) can REUSE the exact same caps
// without importing the full dispatcher (which would create a module cycle and
// drag the SDK/dispatch machinery into a pure unit test). `cc-dispatcher.ts`
// re-exports these names, so every existing importer is unaffected.

// The per-chunk cap bounds a single oversized `tool_use_result` (e.g. a `cat`
// of a multi-MB file) before it ever hits the WS frame; the per-command total
// cap bounds the cumulative output across however many result blocks one
// command produces. Byte-measured (not char-measured) to bound the actual wire
// payload regardless of multi-byte content.
export const COMMAND_STREAM_CHUNK_CAP_BYTES = 4096;
export const COMMAND_STREAM_TOTAL_CAP_BYTES = 16384;
// Pre-cap the raw command at the start emit (mirrors the output path) so the
// wire payload + redaction back-tracking are bounded regardless of an
// adversarially long command string. Matches `commandStreamSchema.command.max`.
export const COMMAND_STREAM_COMMAND_CAP_BYTES = 16384;
export const COMMAND_STREAM_TRUNCATION_MARKER = "\n[… truncated]";

/**
 * feat-concierge-stream-commands — byte-cap a UTF-8 string at `capBytes`,
 * never splitting a multi-byte code point. Returns the (possibly shorter)
 * string + whether it was truncated. Used to bound a single output chunk
 * before redaction (redaction can only shrink the string, so capping the
 * raw input keeps the regex back-tracking bounded too).
 */
export function capUtf8Bytes(
  s: string,
  capBytes: number,
): { text: string; truncated: boolean } {
  const buf = Buffer.from(s, "utf8");
  if (buf.length <= capBytes) return { text: s, truncated: false };
  // Walk back to a code-point boundary: UTF-8 continuation bytes are
  // 0b10xxxxxx (0x80–0xBF). Trim them off the cut edge.
  let end = capBytes;
  while (end > 0 && (buf[end] & 0xc0) === 0x80) end--;
  return { text: buf.subarray(0, end).toString("utf8"), truncated: true };
}
