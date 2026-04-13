import {
  ALLOWED_ATTACHMENT_TYPES,
  MAX_ATTACHMENT_SIZE,
  MAX_ATTACHMENTS_PER_MESSAGE,
} from "@/lib/attachment-constants";

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
    if (file.size > MAX_ATTACHMENT_SIZE) {
      error = `"${file.name}" exceeds the 20 MB size limit.`;
      continue;
    }
    valid.push(file);
  }

  return { valid, error };
}
