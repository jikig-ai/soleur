/**
 * Validation logic for custom domain leader names (TR3).
 * Constraints: max 30 chars, alphanumeric + spaces only, no reserved words.
 * Used by both the API route and client-side validation.
 */

export const MAX_NAME_LENGTH = 30;
const VALID_PATTERN = /^[a-zA-Z0-9 ]+$/;

/** Words that must not be used as custom names (embedded in system prompts). */
export const RESERVED_NAMES = [
  "system",
  "assistant",
  "user",
  "admin",
  "soleur",
  "human",
  "claude",
  "anthropic",
] as const;

export type ValidationResult =
  | { valid: true }
  | { valid: false; error: string };

export function validateCustomName(raw: string): ValidationResult {
  const name = raw.trim();

  if (name.length === 0) {
    return { valid: false, error: "Name cannot be empty" };
  }

  if (name.length > MAX_NAME_LENGTH) {
    return { valid: false, error: `Name must be between 1 and 30 characters` };
  }

  if (!VALID_PATTERN.test(name)) {
    return { valid: false, error: "Name must contain only alphanumeric characters and spaces" };
  }

  if (RESERVED_NAMES.includes(name.toLowerCase() as (typeof RESERVED_NAMES)[number])) {
    return { valid: false, error: `"${name}" is a reserved name` };
  }

  return { valid: true };
}
