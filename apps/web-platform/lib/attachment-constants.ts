/**
 * Shared attachment validation constants.
 *
 * Used by both the client-side upload flow (chat-input.tsx) and the
 * server-side presign route + agent runner validation.  Keeping a single
 * source of truth prevents drift between front-end and back-end limits.
 */

export const ALLOWED_ATTACHMENT_TYPES = new Set([
  "image/png",
  "image/jpeg",
  "image/gif",
  "image/webp",
  "application/pdf",
]);

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
