import { KeyInvalidError } from "../lib/types";

const KNOWN_SAFE_MESSAGES: Record<string, string> = {
  "Workspace not provisioned":
    "Your workspace is not ready yet. Please try again shortly.",
  "No active session":
    "No active session. Please start a new conversation.",
  "Review gate not found or already resolved":
    "This review prompt has already been answered.",
  "Conversation not found":
    "Conversation not found. Please start a new session.",
  "Review gate timed out":
    "The review prompt timed out. Please start a new session.",
  "Invalid review gate selection":
    "Invalid selection. Please choose one of the offered options.",
  "Session aborted: user disconnected":
    "Your session was disconnected. Please reconnect to continue.",
  "Session expired":
    "Your session has expired. Context will be restored from history.",
  "SDK resume failed":
    "Session resume failed. Falling back to conversation history.",
  "Rate limited: too many sessions":
    "Too many sessions. Please wait before starting a new session.",
  "Token validation failed":
    "The provided token could not be validated. Please check and try again.",
  "Failed to store token":
    "Unable to save the service token. Please try again.",
  "Failed to disconnect service":
    "Unable to remove the service connection. Please try again.",
  "File too large":
    "The file exceeds the 20 MB size limit. Please choose a smaller file.",
  "Unsupported file type":
    "This file type is not supported. Please upload an image (PNG, JPEG, GIF, WebP) or PDF.",
  "Upload failed":
    "The file upload failed. Please try again.",
  "Attachment not found":
    "The attachment could not be found.",
  "Too many files":
    "Maximum 5 files per message. Please remove some attachments.",
};

export function sanitizeErrorForClient(err: unknown): string {
  if (err instanceof KeyInvalidError) {
    return "No valid API key found. Please set up your key first.";
  }

  if (err instanceof Error) {
    const safe = KNOWN_SAFE_MESSAGES[err.message];
    if (safe) return safe;

    if (err.message.includes("No conversation found with session ID")) {
      return "Session resume failed. Falling back to conversation history.";
    }

    if (err.message.startsWith("Unknown leader:")) {
      return "Invalid domain leader selected.";
    }
  }

  return "An unexpected error occurred. Please try again.";
}
