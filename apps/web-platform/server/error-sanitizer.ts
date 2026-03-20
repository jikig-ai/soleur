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
};

export function sanitizeErrorForClient(err: unknown): string {
  if (err instanceof KeyInvalidError) {
    return "No valid API key found. Please set up your key first.";
  }

  if (err instanceof Error) {
    const safe = KNOWN_SAFE_MESSAGES[err.message];
    if (safe) return safe;

    if (err.message.startsWith("Unknown leader:")) {
      return "Invalid domain leader selected.";
    }
  }

  return "An unexpected error occurred. Please try again.";
}
