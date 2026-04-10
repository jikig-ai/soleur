/**
 * Given a relative file path like "engineering/specs/file.md",
 * returns all ancestor directory paths: ["engineering", "engineering/specs"].
 * Skips the last segment (the file itself).
 */
export function getAncestorPaths(relativePath: string): string[] {
  if (!relativePath) return [];

  const segments = relativePath.split("/").filter(Boolean);
  const ancestors: string[] = [];

  for (let i = 0; i < segments.length - 1; i++) {
    ancestors.push(segments.slice(0, i + 1).join("/"));
  }

  return ancestors;
}
