/**
 * Shared KB filename validation utilities.
 *
 * Used by upload and rename routes to enforce consistent filename rules.
 */

export const WINDOWS_RESERVED = new Set([
  "con", "prn", "aux", "nul",
  "com1", "com2", "com3", "com4", "com5", "com6", "com7", "com8", "com9",
  "lpt1", "lpt2", "lpt3", "lpt4", "lpt5", "lpt6", "lpt7", "lpt8", "lpt9",
]);

export const MAX_FILENAME_BYTES = 255;

export function sanitizeFilename(
  filename: string,
): { valid: boolean; sanitized: string; error?: string } {
  // Strip control chars (0x00-0x1F, 0x7F)
  const sanitized = filename.replace(/[\x00-\x1f\x7f]/g, "");

  if (!sanitized || sanitized.trim() === "") {
    return { valid: false, sanitized, error: "Empty filename" };
  }

  if (sanitized.startsWith(".")) {
    return { valid: false, sanitized, error: "Filename cannot start with a dot" };
  }

  if (new TextEncoder().encode(sanitized).length > MAX_FILENAME_BYTES) {
    return { valid: false, sanitized, error: "Filename too long" };
  }

  const nameWithoutExt = sanitized.replace(/\.[^.]+$/, "").toLowerCase();
  if (WINDOWS_RESERVED.has(nameWithoutExt)) {
    return { valid: false, sanitized, error: "Reserved filename" };
  }

  return { valid: true, sanitized };
}
