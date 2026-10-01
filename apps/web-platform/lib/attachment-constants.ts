/**
 * Shared attachment validation constants.
 *
 * Used by both the client-side upload flow (chat-input.tsx) and the
 * server-side presign route + agent runner validation.  Keeping a single
 * source of truth prevents drift between front-end and back-end limits.
 */

/**
 * The one MIME -> file-extension map (storage path suffix, on-disk name, and
 * the preview tile label), keyed by CANONICAL type. Every other table in this
 * module is DERIVED from it, so adding a type here is the whole change.
 */
export const ATTACHMENT_EXTENSION_BY_TYPE: Record<string, string> = {
  "image/png": "png",
  "image/jpeg": "jpeg",
  "image/gif": "gif",
  "image/webp": "webp",
  "application/pdf": "pdf",
  "text/markdown": "md",
  "text/plain": "txt",
};

/**
 * CANONICAL content types an attachment may carry once it has passed
 * `resolveAttachmentContentType`. Never test a browser-reported `file.type`
 * against this set directly: browsers report `.md` as "", `text/markdown`,
 * `application/octet-stream` and more, so the resolver decides the canonical
 * type and every surface (client validator, presign, attachment pipeline)
 * goes through it.
 */
export const ALLOWED_ATTACHMENT_TYPES: ReadonlySet<string> = new Set(
  Object.keys(ATTACHMENT_EXTENSION_BY_TYPE),
);

/** Text types the EXTENSION decides (the browser-reported type is unreliable). */
const TEXT_ATTACHMENT_TYPE_BY_EXTENSION: Record<string, string> = {
  md: "text/markdown",
  txt: "text/plain",
};

/** Types decided by the reported MIME alone: everything that is not text. */
const BINARY_ATTACHMENT_TYPES: ReadonlySet<string> = new Set(
  [...ALLOWED_ATTACHMENT_TYPES].filter(
    (type) => !Object.values(TEXT_ATTACHMENT_TYPE_BY_EXTENSION).includes(type),
  ),
);

/**
 * Storage-path extensions rendered inline (`<img>` thumbnails, the PDF viewer).
 * Every other extension is signed for DOWNLOAD only, so an unrecognised suffix
 * fails closed to `Content-Disposition: attachment`.
 */
export const INLINE_ATTACHMENT_EXTENSIONS: ReadonlySet<string> = new Set(
  [...ALLOWED_ATTACHMENT_TYPES]
    .filter((type) => type.startsWith("image/") || type === "application/pdf")
    .map((type) => ATTACHMENT_EXTENSION_BY_TYPE[type]),
);

/**
 * `accept=` for the chat / first-run pickers. Explicit rather than derived from
 * the allowlist: `text/plain` in `accept` would make pickers offer every
 * `.log`/`.py` only for the resolver to reject it.
 */
export const ATTACHMENT_ACCEPT =
  "image/png,image/jpeg,image/gif,image/webp,application/pdf,text/markdown,.md,.txt";

/** Preview-tile label for a (canonical) attachment type: "MD", "TXT", "PDF"... */
export function attachmentTileLabel(canonicalType: string): string {
  return ATTACHMENT_EXTENSION_BY_TYPE[canonicalType]?.toUpperCase() ?? "FILE";
}

/**
 * Neutralise a client-supplied filename before it is stored, shown to the
 * agent or used as a download name: path separators, C0 controls + DEL,
 * Unicode line separators (U+2028/U+2029, NEL), bidi controls and marks,
 * zero-width characters and the BOM, so a crafted name cannot smuggle a
 * forged extra line into the model context or reorder itself visually.
 * Escape sequences only (cq-regex-unicode-separators-escape-only).
 */
export function sanitizeAttachmentFilename(name: string, maxLength = 255): string {
  return String(name ?? "")
    // eslint-disable-next-line no-control-regex
    .replace(/[/\\\x00-\x1f\x7f\u0085\u061c\u200b-\u200f\u2028\u2029\u202a-\u202e\u2060\u2066-\u2069\ufeff]/g, "_")
    .slice(0, maxLength);
}

/**
 * Lowercased text after the LAST dot of the basename, or "" when there is none
 * (a leading dot is not an extension: `.md` and `md` both yield ""). Trailing
 * whitespace/dots are deliberately not trimmed, so `notes.md ` and `notes.md.`
 * do not count as `.md`. No Node imports (`path.extname`) — this module ships
 * in the client bundle.
 */
export function fileExtension(name: string): string {
  const full = typeof name === "string" ? name : String(name ?? "");
  const base = full.slice(Math.max(full.lastIndexOf("/"), full.lastIndexOf("\\")) + 1);
  const dot = base.lastIndexOf(".");
  if (dot <= 0) return "";
  return base.slice(dot + 1).toLowerCase();
}

/**
 * Reported types a `.md`/`.txt` may legitimately arrive as: empty, generic
 * binary, any `text/*` except `text/html`, and the Mega Drive ROM glob some
 * Linux/Windows shells map `*.md` to.
 */
function isTextTolerantReportedType(type: string): boolean {
  if (type === "" || type === "application/octet-stream") return true;
  if (type === "application/x-markdown" || type === "application/x-genesis-rom") {
    return true;
  }
  return type.startsWith("text/") && type !== "text/html";
}

/**
 * Decide the canonical attachment content type, or `null` when unsupported.
 *
 * - `.md` / `.txt`: the EXTENSION decides the canonical type, provided the
 *   reported type is not something that contradicts text (e.g. an executable
 *   or `text/html`).
 * - images / PDF: the reported type, exactly as before.
 *
 * This is a consistency check on client-declared values, not integrity: bytes
 * are never sniffed (same posture as images/PDF). The server binds the stored
 * path suffix to the resolved type separately.
 */
export function resolveAttachmentContentType(opts: {
  contentType?: string | null;
  filename?: string | null;
}): string | null {
  const reported = String(opts.contentType ?? "")
    .split(";")[0]
    .trim()
    .toLowerCase();
  const textType = TEXT_ATTACHMENT_TYPE_BY_EXTENSION[fileExtension(String(opts.filename ?? ""))];
  if (textType && isTextTolerantReportedType(reported)) return textType;
  if (BINARY_ATTACHMENT_TYPES.has(reported)) return reported;
  return null;
}

/**
 * Strict lowercase 8-4-4-4-12 hex shape for a conversation id that is about to
 * be interpolated into a storage path (`${userId}/${conversationId}/...`).
 * Structural, not v4-only (fixtures use non-v4 hex ids). Lowercase-only: the
 * DB `eq` on a uuid column normalises case while the storage path and the
 * attachment pipeline's `${userId}/${conversationId}/` prefix check are
 * case-sensitive. Loosening this is a path-traversal change, not a style one.
 */
export const CONVERSATION_ID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

/**
 * Every `error` code `/api/attachments/presign` can return. The route types
 * its responses against this tuple and the client tile copy
 * (`lib/attachment-error-copy.ts`) is a `Record` over it, so a new code is a
 * compile error until it has human copy.
 */
export const PRESIGN_ERROR_CODES = [
  "unauthorized",
  "invalid_request",
  "unsupported_file_type",
  "file_too_large",
  "conversation_not_found",
  "not_a_workspace_member",
  "upload_failed",
] as const;
export type PresignErrorCode = (typeof PRESIGN_ERROR_CODES)[number];

export const MAX_ATTACHMENT_SIZE = 20 * 1024 * 1024; // 20 MB

export const MAX_ATTACHMENTS_PER_MESSAGE = 5;

/**
 * Maximum raw size of a PDF the agent can Read in a single API request.
 *
 * Anthropic's PDF beta caps the entire encoded request payload at 32 MB
 * (https://platform.claude.com/docs/en/docs/build-with-claude/pdf-support).
 * The SDK's Read tool returns PDF bytes as base64 (FileReadOutput.pdf.base64),
 * which inflates raw bytes by ~33%. So 32 MB encoded ÷ 1.33 ≈ 24 MB raw.
 * System prompt + prior turns also count toward the 32 MB encoded ceiling, so
 * a request near 24 MB raw can still trip the API limit; this cap is the
 * upper bound, not a guaranteed-fit budget.
 *
 * Closes #3332.
 */
export const MAX_AGENT_READABLE_PDF_SIZE = 24 * 1024 * 1024; // 24 MB

/**
 * Detect whether an attachment is (or may be) a PDF for the purpose of
 * applying MAX_AGENT_READABLE_PDF_SIZE. Branch on Content-Type OR filename
 * extension — clients sometimes send "application/octet-stream" with a .pdf
 * filename. Either signal triggers the PDF cap. Used by the chat-attachment
 * validator and KB upload route.
 */
export function isPdfAttachment(opts: {
  contentType?: string | null;
  filename?: string | null;
}): boolean {
  if (opts.contentType === "application/pdf") return true;
  const name = opts.filename?.toLowerCase() ?? "";
  return name.endsWith(".pdf");
}
