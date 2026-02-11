import type { TurnStatus } from "./types";

export const MAX_CHUNK_SIZE = 4000;

export function escapeHtml(text: string): string {
  return text
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;");
}

export function markdownToHtml(text: string): string {
  // First, extract code blocks so they are not processed by inline rules.
  const codeBlocks: string[] = [];
  let processed = text.replace(/```(?:\w*)\n?([\s\S]*?)```/g, (_match, code) => {
    const idx = codeBlocks.length;
    codeBlocks.push(`<pre>${escapeHtml(code.trimEnd())}</pre>`);
    return `\x00CODEBLOCK_${idx}\x00`;
  });

  // Inline code (must come before bold to avoid conflicts inside backticks)
  const inlineCodes: string[] = [];
  processed = processed.replace(/`([^`]+)`/g, (_match, code) => {
    const idx = inlineCodes.length;
    inlineCodes.push(`<code>${escapeHtml(code)}</code>`);
    return `\x00INLINE_${idx}\x00`;
  });

  // Escape remaining HTML entities in the plain-text portions
  processed = escapeHtml(processed);

  // Bold: **text** or __text__
  processed = processed.replace(/\*\*(.+?)\*\*/g, "<b>$1</b>");
  processed = processed.replace(/__(.+?)__/g, "<b>$1</b>");

  // Restore inline codes
  processed = processed.replace(/\x00INLINE_(\d+)\x00/g, (_m, idx) => inlineCodes[Number(idx)]);

  // Restore code blocks
  processed = processed.replace(/\x00CODEBLOCK_(\d+)\x00/g, (_m, idx) => codeBlocks[Number(idx)]);

  // Strip remaining markdown that Telegram HTML mode cannot render
  // Headings: ### Heading -> <b>Heading</b>
  processed = processed.replace(/^#{1,6}\s+(.+)$/gm, "<b>$1</b>");

  // Italic: *text* (single asterisk, not bold)
  processed = processed.replace(/(?<!\*)\*([^*]+)\*(?!\*)/g, "<i>$1</i>");

  // Strip image/link markdown: [text](url) -> text
  processed = processed.replace(/\[([^\]]+)\]\([^)]+\)/g, "$1");

  return processed;
}

export function chunkMessage(text: string): string[] {
  if (text.length <= MAX_CHUNK_SIZE) return [text];

  const chunks: string[] = [];
  let remaining = text;

  while (remaining.length > 0) {
    if (remaining.length <= MAX_CHUNK_SIZE) {
      chunks.push(remaining);
      break;
    }

    // Try to split on double-newline within the limit
    const window = remaining.slice(0, MAX_CHUNK_SIZE);
    const splitIdx = window.lastIndexOf("\n\n");

    if (splitIdx > 0) {
      chunks.push(remaining.slice(0, splitIdx));
      remaining = remaining.slice(splitIdx + 2);
    } else {
      // Hard-split at MAX_CHUNK_SIZE
      chunks.push(remaining.slice(0, MAX_CHUNK_SIZE));
      remaining = remaining.slice(MAX_CHUNK_SIZE);
    }
  }

  return chunks;
}

export function stripHtmlTags(html: string): string {
  return html.replace(/<[^>]+>/g, "");
}

export function formatStatusText(status: TurnStatus): string {
  const elapsed = Math.floor((Date.now() - status.startTime) / 1000);
  const toolList = status.tools.length > 0
    ? status.tools.slice(-5).join(", ") // Show last 5 tools
    : "";

  if (elapsed < 2 && !toolList) {
    return "Thinking...";
  }

  let text = `Working... (${elapsed}s`;
  if (toolList) {
    text += ` \u00b7 ${toolList}`;
  }
  text += ")";
  return text;
}
