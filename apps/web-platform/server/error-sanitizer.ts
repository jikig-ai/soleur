import { KeyInvalidError } from "../lib/types";
import {
  ERR_WORKSPACE_NOT_PROVISIONED,
  ERR_NO_ACTIVE_SESSION,
  ERR_REVIEW_GATE_NOT_FOUND,
  ERR_CONVERSATION_NOT_FOUND,
  ERR_REVIEW_GATE_TIMED_OUT,
  ERR_SESSION_ABORTED,
  ERR_SESSION_EXPIRED,
  ERR_SDK_RESUME_FAILED,
  ERR_RATE_LIMITED,
  ERR_TOKEN_VALIDATION_FAILED,
  ERR_FAILED_TO_STORE_TOKEN,
  ERR_FAILED_TO_DISCONNECT,
  ERR_FILE_TOO_LARGE,
  ERR_UNSUPPORTED_FILE_TYPE,
  ERR_UPLOAD_FAILED,
  ERR_ATTACHMENT_NOT_FOUND,
  ERR_TOO_MANY_FILES,
} from "./error-messages";

const KNOWN_SAFE_MESSAGES: Record<string, string> = {
  [ERR_WORKSPACE_NOT_PROVISIONED]:
    "Your workspace is not ready yet. Please try again shortly.",
  [ERR_NO_ACTIVE_SESSION]:
    "No active session. Please start a new conversation.",
  [ERR_REVIEW_GATE_NOT_FOUND]:
    "This review prompt has already been answered.",
  [ERR_CONVERSATION_NOT_FOUND]:
    "Conversation not found. Please start a new session.",
  [ERR_REVIEW_GATE_TIMED_OUT]:
    "The review prompt timed out. Please start a new session.",
  "Invalid review gate selection":
    "Invalid selection. Please choose one of the offered options.",
  [ERR_SESSION_ABORTED]:
    "Your session was disconnected. Please reconnect to continue.",
  [ERR_SESSION_EXPIRED]:
    "Your session has expired. Context will be restored from history.",
  [ERR_SDK_RESUME_FAILED]:
    "Session resume failed. Falling back to conversation history.",
  [ERR_RATE_LIMITED]:
    "Too many sessions. Please wait before starting a new session.",
  [ERR_TOKEN_VALIDATION_FAILED]:
    "The provided token could not be validated. Please check and try again.",
  [ERR_FAILED_TO_STORE_TOKEN]:
    "Unable to save the service token. Please try again.",
  [ERR_FAILED_TO_DISCONNECT]:
    "Unable to remove the service connection. Please try again.",
  [ERR_FILE_TOO_LARGE]:
    "The file exceeds the 20 MB size limit. Please choose a smaller file.",
  [ERR_UNSUPPORTED_FILE_TYPE]:
    "This file type is not supported. Please upload an image (PNG, JPEG, GIF, WebP) or PDF.",
  [ERR_UPLOAD_FAILED]:
    "The file upload failed. Please try again.",
  [ERR_ATTACHMENT_NOT_FOUND]:
    "The attachment could not be found.",
  [ERR_TOO_MANY_FILES]:
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
