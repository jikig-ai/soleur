import type { SharedContentKind } from "@/lib/shared-kind";

/**
 * Shared file-kind enum for KB viewers. Alias of `SharedContentKind` so
 * the server's `X-Soleur-Kind` header and the viewer dispatch table stay
 * anchored on a single type. Adding a kind requires:
 *   (1) extend `SharedContentKind` in `lib/shared-kind.ts`,
 *   (2) add a `classifyByExtension` branch here,
 *   (3) add a `classifyByContentType` branch here,
 *   (4) add a renderer to `components/kb/file-preview.tsx` and
 *       `app/shared/[token]/page.tsx` (both surface exhaustive switches).
 *
 * The switches are exhaustive with a `: never` rail — a forgotten arm
 * is a build error, not a silent "download".
 *
 * Colocated in `lib/` (not `server/`) so client-side viewer code can
 * import it without bundler complaints. The classifier has no Node
 * dependencies — it's pure branching over strings.
 */
export type FileKind = SharedContentKind;

/**
 * Classify a KB file by its lowercase extension (leading dot, e.g. `.pdf`).
 * Callers gate on `isMarkdownKbPath` BEFORE calling this; an empty string
 * or unmapped extension falls through to `"download"`.
 */
export function classifyByExtension(ext: string): FileKind {
  if (ext === ".md") return "markdown";
  if (ext === ".pdf") return "pdf";
  if (
    ext === ".png" ||
    ext === ".jpg" ||
    ext === ".jpeg" ||
    ext === ".gif" ||
    ext === ".webp" ||
    ext === ".svg"
  ) {
    return "image";
  }
  if (ext === ".txt") return "text";
  return "download";
}

/**
 * Classify a KB binary response by its Content-Type and Content-Disposition.
 * Disposition wins — `.docx` carries a specific `contentType` but the
 * serving layer forces `disposition: "attachment"`, so it correctly
 * classifies as `"download"` regardless of the content-type map.
 *
 * Never returns `"markdown"` at runtime — markdown is served via the
 * JSON path (`/api/shared/<token>` returns `application/json` for `.md`),
 * not the binary path that yields a raw Content-Type. The `"markdown"`
 * branch is absent from this function's body by design.
 */
export function classifyByContentType(
  contentType: string,
  disposition: "inline" | "attachment",
): FileKind {
  if (disposition === "attachment") return "download";
  if (contentType === "application/pdf") return "pdf";
  if (contentType.startsWith("image/")) return "image";
  if (contentType === "text/plain") return "text";
  return "download";
}
