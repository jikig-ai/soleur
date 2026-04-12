/**
 * Branch name validation following git check-ref-format rules.
 *
 * Extracted into a standalone module with zero heavy dependencies
 * (following sandbox.ts, error-sanitizer.ts extraction pattern)
 * for unit testability without mocking SDK/Supabase.
 *
 * See: git check-ref-format(1) man page for the 10 rules.
 */

const MAX_BRANCH_LENGTH = 255;

// ASCII control characters (0x00-0x1F, 0x7F) plus banned characters
const BANNED_CHARS_RE = /[\x00-\x1f\x7f ~^:?*[\]\\]/;

/**
 * Validate a branch name against git's ref format rules.
 * Uses --allow-onelevel semantics (single-component names like "feat-x" are valid).
 *
 * Throws with a descriptive message on the first rule violation.
 */
export function validateBranchFormat(branch: string): void {
  if (!branch || branch.length > MAX_BRANCH_LENGTH) {
    throw new Error(
      `Invalid branch name: ${!branch ? "empty" : "exceeds 255 characters"}`,
    );
  }

  // Rule 9: cannot be single character @
  if (branch === "@") {
    throw new Error("Invalid branch name '@'");
  }

  const display = branch.slice(0, 100);

  // Rule 6: cannot begin or end with /
  if (branch.startsWith("/") || branch.endsWith("/")) {
    throw new Error(
      `Invalid branch name '${display}': cannot begin or end with '/'`,
    );
  }

  // Rule 7: cannot end with .
  if (branch.endsWith(".")) {
    throw new Error(
      `Invalid branch name '${display}': cannot end with '.'`,
    );
  }

  // Rule 3: no .. anywhere
  if (branch.includes("..")) {
    throw new Error(
      `Invalid branch name '${display}': cannot contain '..'`,
    );
  }

  // Rule 6: no consecutive //
  if (branch.includes("//")) {
    throw new Error(
      `Invalid branch name '${display}': cannot contain '//'`,
    );
  }

  // Rule 8: no @{ sequence
  if (branch.includes("@{")) {
    throw new Error(
      `Invalid branch name '${display}': cannot contain '@{'`,
    );
  }

  // Rule 4+5+10: no control chars, space, ~, ^, :, ?, *, [, ], \
  if (BANNED_CHARS_RE.test(branch)) {
    throw new Error(
      `Invalid branch name '${display}': contains forbidden characters`,
    );
  }

  // Rule 1: no component starts with . or ends with .lock
  const components = branch.split("/");
  for (const component of components) {
    const componentDisplay = component.slice(0, 50);
    if (component.startsWith(".")) {
      throw new Error(
        `Invalid branch name '${display}': component '${componentDisplay}' starts with '.'`,
      );
    }
    if (component.endsWith(".lock")) {
      throw new Error(
        `Invalid branch name '${display}': component '${componentDisplay}' ends with '.lock'`,
      );
    }
  }
}
