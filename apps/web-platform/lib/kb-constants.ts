/**
 * Shared KB reading constants.
 *
 * Used by kb-reader.ts (file reading) and context-validation.ts (context
 * content validation).  Keeping a single source of truth prevents drift.
 */

export const KB_MAX_FILE_SIZE = 1024 * 1024; // 1MB

/**
 * Minimum file size (bytes) to consider a foundation document "complete".
 * Used by:
 * - dashboard/page.tsx: Foundation card completion check
 * - vision-helpers.ts: buildVisionEnhancementPrompt threshold
 *
 * A typical stub (# Title + placeholder) is ~100-300 bytes.
 * Real authored content (multiple sections) exceeds 500 bytes.
 */
export const FOUNDATION_MIN_CONTENT_BYTES = 500;
