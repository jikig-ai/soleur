/**
 * Error message constants shared between throw sites and error-sanitizer.
 *
 * Both agent-runner.ts (which throws) and error-sanitizer.ts (which matches
 * on `err.message`) must agree on the exact string. Extracting them here
 * ensures a rename shows up as a single-line diff instead of a silent
 * desync between two files.
 */

// agent-runner.ts
export const ERR_WORKSPACE_NOT_PROVISIONED = "Workspace not provisioned";
export const ERR_CONVERSATION_NOT_FOUND = "Conversation not found";
export const ERR_NO_ACTIVE_SESSION = "No active session";
export const ERR_REVIEW_GATE_NOT_FOUND = "Review gate not found or already resolved";
export const ERR_ATTACHMENT_NOT_FOUND = "Attachment not found";
export const ERR_UNSUPPORTED_FILE_TYPE = "Unsupported file type";
export const ERR_UPLOAD_FAILED = "Upload failed";

// review-gate.ts
export const ERR_REVIEW_GATE_TIMED_OUT = "Review gate timed out";

// ws-handler.ts
export const ERR_RATE_LIMITED = "Rate limited: too many sessions";
export const ERR_TOO_MANY_FILES = "Too many files";

// ws-client.ts / ws-handler.ts
export const ERR_SESSION_EXPIRED = "Session expired";
export const ERR_SESSION_ABORTED = "Session aborted: user disconnected";
export const ERR_SDK_RESUME_FAILED = "SDK resume failed";

// api/services/route.ts
export const ERR_TOKEN_VALIDATION_FAILED = "Token validation failed";
export const ERR_FAILED_TO_STORE_TOKEN = "Failed to store token";
export const ERR_FAILED_TO_DISCONNECT = "Failed to disconnect service";

// attachments
export const ERR_FILE_TOO_LARGE = "File too large";
