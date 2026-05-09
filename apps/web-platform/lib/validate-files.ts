import {
  ALLOWED_ATTACHMENT_TYPES,
  MAX_AGENT_READABLE_PDF_SIZE,
  MAX_ATTACHMENT_SIZE,
  MAX_ATTACHMENTS_PER_MESSAGE,
  isPdfAttachment,
} from "@/lib/attachment-constants";

const PDF_LIMIT_MB = Math.round(MAX_AGENT_READABLE_PDF_SIZE / 1024 / 1024);
const ATTACHMENT_LIMIT_MB = Math.round(MAX_ATTACHMENT_SIZE / 1024 / 1024);

/**
 * Validate files against attachment constraints (type, size, count).
 * Shared between the Command Center first-run form and ChatInput.
 *
 * Returns valid files and an optional error message for the first rejected file.
 */
export function validateFiles(
  files: FileList | File[],
  currentCount: number,
): { valid: File[]; error?: string } {
  const fileArray = Array.from(files);
  const valid: File[] = [];
  let error: string | undefined;

  for (const file of fileArray) {
    if (currentCount + valid.length >= MAX_ATTACHMENTS_PER_MESSAGE) {
      error = `Maximum ${MAX_ATTACHMENTS_PER_MESSAGE} files per message.`;
      break;
    }
    if (!ALLOWED_ATTACHMENT_TYPES.has(file.type)) {
      error = `"${file.name}" is not a supported file type.`;
      continue;
    }
    // Closes #3332: PDFs are bounded by Anthropic's request-size ceiling
    // (32 MB encoded) — base64 inflation pushes the raw cap to ~24 MB.
    if (
      isPdfAttachment({ contentType: file.type, filename: file.name }) &&
      file.size > MAX_AGENT_READABLE_PDF_SIZE
    ) {
      error = `"${file.name}" exceeds the ${PDF_LIMIT_MB} MB PDF size limit (Anthropic API request-size ceiling after base64 encoding).`;
      continue;
    }
    if (file.size > MAX_ATTACHMENT_SIZE) {
      error = `"${file.name}" exceeds the ${ATTACHMENT_LIMIT_MB} MB size limit.`;
      continue;
    }
    valid.push(file);
  }

  return { valid, error };
}
