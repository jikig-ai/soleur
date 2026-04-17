export type SharedData =
  | { kind: "markdown"; content: string; path: string }
  | { kind: "pdf"; src: string; filename: string }
  | { kind: "image"; src: string; filename: string | null }
  | { kind: "download"; src: string; filename: string };

export type PageError = "not-found" | "revoked" | "content-changed" | "unknown";

export type ClassifyResult = { data: SharedData } | { error: PageError };

const FILENAME_STAR = /filename\*\s*=\s*([^']*)'[^']*'([^;]+)/i;
const FILENAME_ASCII = /filename\s*=\s*"?([^";]+)"?/i;

// Parses Content-Disposition per RFC 5987. Prefers the extended
// `filename*=UTF-8''<percent-encoded>` token (preserves non-ASCII bytes)
// over the ASCII-only `filename="..."` fallback. Returns `null` when the
// header is missing, parsing fails, or no filename token is present.
// Callers choose a sensible default at the usage site — never the string
// "file".
export function extractFilename(contentDisposition: string | null): string | null {
  if (!contentDisposition) return null;

  const starMatch = contentDisposition.match(FILENAME_STAR);
  if (starMatch) {
    const charset = starMatch[1].trim().toLowerCase();
    const encoded = starMatch[2].trim();
    try {
      const decoded =
        charset === "" || charset === "utf-8"
          ? decodeURIComponent(encoded)
          : encoded;
      if (decoded) return decoded;
    } catch {
      // fall through to ASCII fallback
    }
  }

  const asciiMatch = contentDisposition.match(FILENAME_ASCII);
  return asciiMatch?.[1]?.trim() ?? null;
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

    const contentType = res.headers.get("content-type") ?? "";
    const disposition = res.headers.get("content-disposition");
    const src = `/api/shared/${token}`;

    if (contentType.startsWith("application/json")) {
      const json = (await res.json()) as { content: string; path: string };
      return {
        data: { kind: "markdown", content: json.content, path: json.path },
      };
    }

    const filename = extractFilename(disposition);

    if (contentType.startsWith("application/pdf")) {
      return { data: { kind: "pdf", src, filename: filename ?? "download" } };
    }
    if (contentType.startsWith("image/")) {
      return { data: { kind: "image", src, filename } };
    }
    return {
      data: { kind: "download", src, filename: filename ?? "download" },
    };
  } catch {
    return { error: "unknown" };
  }
}
