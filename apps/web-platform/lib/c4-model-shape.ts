// Shape helpers for a LikeC4 `model.likec4.json` dump, shared by the server
// re-render (`server/c4-render.ts`), the project read route and the client
// diagnostics strip. Pure and import-free so it is safe on both sides of the
// client/server boundary.

/** A diagnostic shown in the C4 diagnostics strip. */
export type Diagnostic = { message: string; line: number; sourceFsPath: string };

/** The reserved `line` for a diagnostic about the whole model rather than a
 *  source line. `sourceFsPath` is then a bare filename. The strip omits the
 *  `line N:` prefix for `line <= MODEL_LEVEL_LINE`. */
export const MODEL_LEVEL_LINE = 0;

function plainObjectSize(v: unknown): number {
  return v && typeof v === "object" && !Array.isArray(v) ? Object.keys(v).length : 0;
}

/** Element and view counts of a parsed dump. `elements`/`views` count only
 *  when they are plain objects; anything else (absent, an array, a string)
 *  counts as zero, as does a non-object `model`. */
export function c4ModelCounts(model: unknown): { elements: number; views: number } {
  if (!model || typeof model !== "object") return { elements: 0, views: 0 };
  const m = model as { elements?: unknown; views?: unknown };
  return { elements: plainObjectSize(m.elements), views: plainObjectSize(m.views) };
}
