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
