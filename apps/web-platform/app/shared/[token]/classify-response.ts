import {
  SHARED_CONTENT_KIND_HEADER,
  isSharedContentKind,
  type SharedContentKind,
} from "@/lib/shared-kind";

export type SharedData =
  | { kind: "markdown"; content: string; path: string }
  | { kind: "pdf"; src: string; filename: string }
  | { kind: "image"; src: string; filename: string | null }
  | { kind: "text"; src: string; filename: string }
  | { kind: "download"; src: string; filename: string };

export type PageError = "not-found" | "revoked" | "content-changed" | "unknown";

export type ClassifyResult = { data: SharedData } | { error: PageError };

const FILENAME_STAR = /filename\*\s*=\s*UTF-8''([^;]+)/i;
const FILENAME_ASCII = /filename\s*=\s*"?([^";]+)"?/i;

// Parses Content-Disposition per RFC 5987. Prefers the
// `filename*=UTF-8''<percent-encoded>` token (preserves non-ASCII bytes)
// over the ASCII-only `filename="..."` fallback. Returns `null` when the
// header is missing, parsing fails, or no filename token is present.
// Callers choose a sensible default at the usage site — never the string
// "file".
export function extractFilename(contentDisposition: string | null): string | null {
  if (!contentDisposition) return null;
  const starMatch = contentDisposition.match(FILENAME_STAR);
  if (starMatch?.[1]) {
    try {
      const decoded = decodeURIComponent(starMatch[1].trim());
      if (decoded) return decoded;
    } catch {
      // fall through to ASCII fallback
    }
  }
  const asciiMatch = contentDisposition.match(FILENAME_ASCII);
  return asciiMatch?.[1]?.trim() || null;
}

function basenameFromToken(token: string): string {
  // Last-resort label when the server violates the Content-Disposition
  // contract (no filename, no filename*).
  return `shared-${token}`;
}

export async function classifyResponse(
  res: Response,
  token: string,
): Promise<ClassifyResult> {
  try {
    if (res.status === 404) return { error: "not-found" };
    if (res.status === 410) {
      const body = (await res.json().catch(() => null)) as { code?: string } | null;
      const code = body?.code;
      return code === "content-changed" || code === "legacy-null-hash"
        ? { error: "content-changed" }
        : { error: "revoked" };
    }
    if (!res.ok) return { error: "unknown" };

    // Server-declared kind — branch on X-Soleur-Kind rather than sniffing
    // the content-type string. Keeps the UI decoupled from the transport
    // mime map.
    const headerKind = res.headers.get(SHARED_CONTENT_KIND_HEADER);
    const kind: SharedContentKind | null = isSharedContentKind(headerKind)
      ? headerKind
      : null;
    if (!kind) return { error: "unknown" };

    const disposition = res.headers.get("content-disposition");
    const filename = extractFilename(disposition);
    const src = `/api/shared/${token}`;

    switch (kind) {
      case "markdown": {
        const json = (await res.json()) as { content: string; path: string };
        return {
          data: { kind: "markdown", content: json.content, path: json.path },
        };
      }
      case "pdf":
        return {
          data: { kind: "pdf", src, filename: filename ?? basenameFromToken(token) },
        };
      case "image":
        // Image returns `null` when filename is unknown (never "file") so
        // the renderer can choose between `title={filename}` and no title.
        return { data: { kind: "image", src, filename } };
      case "text":
        return {
          data: { kind: "text", src, filename: filename ?? basenameFromToken(token) },
        };
      case "download":
        return {
          data: {
            kind: "download",
            src,
            filename: filename ?? basenameFromToken(token),
          },
        };
      default: {
        // Exhaustiveness guard — adding a new SharedContentKind without a
        // render branch fails the build here.
        const _exhaustive: never = kind;
        void _exhaustive;
        return { error: "unknown" };
      }
    }
  } catch {
    return { error: "unknown" };
  }
}
