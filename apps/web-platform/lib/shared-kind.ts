/**
 * Shared-document rendering kind. Used by the server
 * (`/api/shared/[token]`) to declare which renderer the client should
 * pick, and by the client (`/shared/[token]`) to branch on the declared
 * value rather than sniffing `Content-Type`.
 *
 * Adding a new variant forces every consumer with an exhaustive switch
 * (see `app/shared/[token]/page.tsx`) to add a render branch — a
 * forgotten branch becomes a build error, not silent "download".
 */
export type SharedContentKind = "markdown" | "pdf" | "image" | "download";

export const SHARED_CONTENT_KIND_HEADER = "X-Soleur-Kind";

export function isSharedContentKind(
  value: string | null | undefined,
): value is SharedContentKind {
  return (
    value === "markdown" ||
    value === "pdf" ||
    value === "image" ||
    value === "download"
  );
}
