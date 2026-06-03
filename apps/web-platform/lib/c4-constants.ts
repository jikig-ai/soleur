// Shared constants for the LikeC4 C4-model visualizer (ADR-pending).
// Client-safe: no server-only imports so both the markdown renderer (client)
// and the API routes / writer (server) can import it.

/** KB-relative directory that holds the canonical LikeC4 project. */
export const C4_DIAGRAMS_DIR = "engineering/architecture/diagrams";

/** Canonical LikeC4 source extension. */
export const C4_SOURCE_EXT = ".c4";

/** Fenced-code language token that embeds a LikeC4 view in a markdown page. */
export const LIKEC4_VIEW_LANG = "likec4-view";

/** Runtime feature flag gating the whole visualizer. */
export const C4_VISUALIZER_FLAG = "c4-visualizer" as const;

/**
 * True when `relativePath` (KB-relative, forward-slashed) is a writable
 * canonical diagram source: a `.c4` or `.md` file directly under the diagrams
 * dir. This is the scope guard for every C4 write surface — keep it strict.
 */
export function isC4DiagramPath(relativePath: string): boolean {
  if (!relativePath || relativePath.includes("\0")) return false;
  // Normalize and reject traversal.
  const normalized = relativePath.replace(/\\/g, "/");
  if (normalized.includes("..")) return false;
  const prefix = `${C4_DIAGRAMS_DIR}/`;
  if (!normalized.startsWith(prefix)) return false;
  const rest = normalized.slice(prefix.length);
  // Must be a direct child (no nested subdirectories).
  if (rest.includes("/")) return false;
  return rest.endsWith(C4_SOURCE_EXT) || rest.endsWith(".md");
}
