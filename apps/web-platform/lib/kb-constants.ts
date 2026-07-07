/**
 * Shared KB reading constants.
 *
 * Used by kb-reader.ts (file reading) and context-validation.ts (context
 * content validation).  Keeping a single source of truth prevents drift.
 */

export const KB_MAX_FILE_SIZE = 1024 * 1024; // 1MB

/**
 * User-uploadable file extensions (no dot prefix, lowercase).
 *
 * Single source of truth for:
 * - apps/web-platform/app/api/kb/upload/route.ts (gates uploads)
 * - apps/web-platform/server/kb-reader.ts (gates filename-search corpus)
 *
 * Native .md files are NOT included — those are authored content, not uploads.
 */
export const KB_UPLOAD_EXTENSIONS = [
  "pdf",
  "docx",
  "csv",
  "txt",
  "png",
  "jpg",
  "jpeg",
  "gif",
  "webp",
] as const;

/**
 * Text-native extensions that searchKb scans byte-by-byte for content matches.
 * Subset of upload extensions plus .md (native KB content).
 */
export const KB_TEXT_EXTENSIONS = ["md", "txt", "csv"] as const;

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

/**
 * The exact KB paths the dashboard needs to derive foundation/operational card
 * completion + first-run (`vision.md`) state. `/api/dashboard/foundation-status`
 * stats ONLY these known paths instead of walking the whole KB tree (`buildTree`)
 * on cold dashboard load — the previous render-blocking over-fetch.
 *
 * MUST stay a SUPERSET of every `kbPath` in dashboard/page.tsx's FOUNDATION_PATHS
 * + OPERATIONAL_TASKS (plus `overview/vision.md`). The page looks each card's
 * kbPath up in the returned map; a missing path reads as not-done. A coverage
 * test (dashboard-foundation-status.test.ts) asserts the page's kbPaths ⊆ this.
 */
export const DASHBOARD_FOUNDATION_KB_PATHS = [
  "overview/vision.md",
  "marketing/brand-guide.md",
  "product/business-validation.md",
  "legal/privacy-policy.md",
  "product/pricing-strategy.md",
  "product/competitive-analysis.md",
  "marketing/launch-plan.md",
  "operations/hiring-plan.md",
  "marketing/distribution-strategy.md",
  "finance/financial-projections.md",
] as const;
