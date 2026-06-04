// Pure helpers for the LikeC4 `likec4-view` markdown embed.
// Client- and server-safe (no imports) so the KB page can branch to the
// full-workspace layout and the markdown renderer can keep its inline embed.

import { LIKEC4_VIEW_LANG } from "@/lib/c4-constants";

export type LikeC4Embed = {
  /** The view id named inside the first ```likec4-view block. */
  viewId: string;
  /** The source markdown with that fenced block removed (for the Notes strip). */
  notes: string;
};

// Matches a fenced ```likec4-view block and captures its body (the view id).
// `[ \t]*` after the language token tolerates trailing spaces on the fence line.
const LIKEC4_VIEW_BLOCK = new RegExp(
  "```" + LIKEC4_VIEW_LANG + "[ \\t]*\\n([\\s\\S]*?)\\n```",
);

/**
 * Parse the first `likec4-view` embed out of a markdown document.
 * Returns the named view id plus the remaining prose (block stripped), or
 * `null` when the document has no embed. The view id is the first non-empty
 * line inside the block (extra lines, if any, are ignored).
 */
export function parseLikeC4Embed(markdown: string): LikeC4Embed | null {
  if (!markdown) return null;
  const match = LIKEC4_VIEW_BLOCK.exec(markdown);
  if (!match) return null;
  const viewId = (match[1] ?? "")
    .split("\n")
    .map((l) => l.trim())
    .find((l) => l.length > 0);
  if (!viewId) return null;
  const notes = markdown.replace(match[0], "").replace(/\n{3,}/g, "\n\n").trim();
  return { viewId, notes };
}
