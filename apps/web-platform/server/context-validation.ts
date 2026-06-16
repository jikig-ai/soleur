import type { ConversationContext } from "@/lib/types";
import { KB_MAX_FILE_SIZE } from "@/lib/kb-constants";

/**
 * Safe path pattern: any characters except path traversal sequences.
 * Must start with a word character and contain at least one dot (file extension).
 * Rejects: "..", leading "/", null bytes.
 */
function isSafePath(path: string): boolean {
  if (!path || path.length > 512 || path.includes("..") || path.startsWith("/") || path.includes("\0")) {
    return false;
  }
  // Must have a real file extension (dot that is not the first character)
  const filename = path.split("/").pop() ?? "";
  return filename.lastIndexOf(".") > 0;
}
/** Allowed context types */
const ALLOWED_CONTEXT_TYPES = new Set(["kb-viewer", "routine-authoring"]);

/**
 * Mode-flag context types carry NO document (no path) — they only scope agent
 * behavior via a system-prompt directive. Document-context types (kb-viewer)
 * still require a valid path. #5402.
 */
const MODE_FLAG_CONTEXT_TYPES = new Set(["routine-authoring"]);

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

  // type: required, must be from allowed set (checked first so a bad type fails
  // before the type-conditional path rule below).
  if (typeof obj.type !== "string" || !ALLOWED_CONTEXT_TYPES.has(obj.type)) {
    throw new Error(`Invalid context: type must be one of ${[...ALLOWED_CONTEXT_TYPES].join(", ")}`);
  }

  const isModeFlag = MODE_FLAG_CONTEXT_TYPES.has(obj.type);

  // path: required for document-context types; absent for mode-flag types.
  // When present (either case), it must be a safe file path (no traversal).
  if (isModeFlag) {
    if (obj.path !== undefined && (typeof obj.path !== "string" || !isSafePath(obj.path))) {
      throw new Error("Invalid context: path must be a valid file path (no '..' or leading '/')");
    }
  } else if (typeof obj.path !== "string" || !isSafePath(obj.path)) {
    throw new Error("Invalid context: path must be a valid file path (no '..' or leading '/')");
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
    path: obj.path as string | undefined,
    type: obj.type,
    content: obj.content as string | undefined,
  };
}
