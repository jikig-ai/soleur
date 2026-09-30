/**
 * Shared attachment validation constants.
 *
 * Used by both the client-side upload flow (chat-input.tsx) and the
 * server-side presign route + agent runner validation.  Keeping a single
 * source of truth prevents drift between front-end and back-end limits.
 */

/**
 * CANONICAL content types an attachment may carry once it has passed
 * `resolveAttachmentContentType`. Never test a browser-reported `file.type`
 * against this set directly: browsers report `.md` as "", `text/markdown`,
 * `application/octet-stream` and more, so the resolver decides the canonical
 * type and every surface (client validator, presign, attachment pipeline)
 * goes through it.
 */
export const ALLOWED_ATTACHMENT_TYPES = new Set([
  "image/png",
  "image/jpeg",
  "image/gif",
  "image/webp",
  "application/pdf",
  "text/markdown",
  "text/plain",
]);

/**
 * The one MIME -> file-extension map (storage path suffix, on-disk name, and
 * the preview tile label). Keyed by canonical type; a parity test pins it to
 * `ALLOWED_ATTACHMENT_TYPES`.
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
 * `accept=` for the chat / first-run pickers. Explicit rather than derived from
 * the allowlist: `text/plain` in `accept` would make pickers offer every
 * `.log`/`.py` only for the resolver to reject it.
 */
export const ATTACHMENT_ACCEPT =
  "image/png,image/jpeg,image/gif,image/webp,application/pdf,text/markdown,.md,.txt";

const BINARY_ATTACHMENT_TYPES = new Set([
  "image/png",
  "image/jpeg",
  "image/gif",
  "image/webp",
  "application/pdf",
]);

const TEXT_ATTACHMENT_TYPE_BY_EXTENSION: Record<string, string> = {
  md: "text/markdown",
  txt: "text/plain",
};

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
