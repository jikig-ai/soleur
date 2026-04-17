/**
 * Shared KB file-extension classifier. Pure string helpers with zero Node
 * dependencies so both client (React) and server (Next route handlers) can
 * import from one authority.
 *
 * The markdown dispatch fork in both `/api/kb/content/[...path]` and
 * `/api/shared/[token]` keys off `isMarkdownKbPath`; the dashboard viewer
 * page keys off the same helper so `NOTES.MD` classifies identically on
 * client and server.
 */

export function getKbExtension(relPath: string): string {
  const lastSlash = relPath.lastIndexOf("/");
  const basename = lastSlash === -1 ? relPath : relPath.slice(lastSlash + 1);
  const lastDot = basename.lastIndexOf(".");
  if (lastDot <= 0) return "";
  return basename.slice(lastDot).toLowerCase();
}

export function isMarkdownKbPath(relPath: string): boolean {
  const ext = getKbExtension(relPath);
  return ext === ".md" || ext === "";
}
