import type { ConversationContext } from "@/lib/types";
import { KB_MAX_FILE_SIZE } from "@/lib/kb-constants";

/** Safe path pattern: alphanumeric, hyphens, underscores, slashes, ending in .md */
const SAFE_PATH_RE = /^[a-zA-Z0-9_\-/]+\.md$/;
/** Allowed context types */
const ALLOWED_CONTEXT_TYPES = new Set(["kb-viewer"]);

/**
 * Validate a ConversationContext payload from the client.
 * Returns the validated context, or undefined if the input is nullish.
 * Throws on invalid input.
 */
export function validateConversationContext(
  raw: unknown,
): ConversationContext | undefined {
  if (raw === undefined || raw === null) return undefined;

  if (typeof raw !== "object") {
    throw new Error("Invalid context: expected object");
  }

  const obj = raw as Record<string, unknown>;

  // path: required, must match safe pattern (no traversal sequences)
  if (typeof obj.path !== "string" || !SAFE_PATH_RE.test(obj.path)) {
    throw new Error("Invalid context: path must match [a-zA-Z0-9_-/]+.md");
  }

  // type: required, must be from allowed set
  if (typeof obj.type !== "string" || !ALLOWED_CONTEXT_TYPES.has(obj.type)) {
    throw new Error(`Invalid context: type must be one of ${[...ALLOWED_CONTEXT_TYPES].join(", ")}`);
  }

  // content: optional, but bounded
  if (obj.content !== undefined) {
    if (typeof obj.content !== "string") {
      throw new Error("Invalid context: content must be a string");
    }
    if (obj.content.length > KB_MAX_FILE_SIZE) {
      throw new Error("Invalid context: content exceeds 1MB limit");
    }
  }

  return {
    path: obj.path,
    type: obj.type,
    content: obj.content as string | undefined,
  };
}
