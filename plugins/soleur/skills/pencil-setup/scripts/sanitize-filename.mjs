// sanitize-filename.mjs — filesystem-safe filename sanitization for pencil node names

/**
 * Sanitize a node name for use as a filename.
 * Replaces path separators and filesystem-unsafe characters with hyphens,
 * collapses consecutive hyphens, trims, and truncates.
 * Returns empty string if the result is empty (caller handles fallback to node ID).
 */
export function sanitizeFilename(name) {
  if (!name) return "";
  let result = name
    // Replace unsafe characters with hyphens
    .replace(/[/\\:*?"<>|]/g, "-")
    // Collapse consecutive hyphens
    .replace(/-{2,}/g, "-")
    // Trim hyphens and whitespace from edges
    .replace(/^[-\s]+|[-\s]+$/g, "");
  // Truncate to 200 characters
  if (result.length > 200) {
    result = result.slice(0, 200);
  }
  return result;
}
