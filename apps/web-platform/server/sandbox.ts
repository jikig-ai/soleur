import fs from "fs";
import path from "path";

/**
 * Resolves a file path to its canonical form, following symlinks.
 *
 * For existing paths, uses fs.realpathSync to resolve the full symlink chain.
 * For non-existent paths (Write/Edit targets), walks up the directory tree
 * to find the deepest existing ancestor, resolves it with realpathSync,
 * and re-appends the non-existent tail segments.
 *
 * Returns null if the path cannot be safely resolved (ELOOP, EACCES, etc.).
 *
 * TOCTOU note: a race exists between this check and the file operation.
 * Mitigated by bubblewrap sandbox (layer 1) and the fact that the attacker
 * cannot interleave commands within a single tool invocation.
 *
 * @see https://cwe.mitre.org/data/definitions/59.html (CWE-59: Improper Link Resolution)
 * @see CVE-2025-55130 (Node.js Permissions Model symlink bypass)
 */
function resolveRealPath(filePath: string): string | null {
  const resolved = path.resolve(filePath);
  try {
    return fs.realpathSync(resolved);
  } catch (err: unknown) {
    const code = (err as NodeJS.ErrnoException).code;
    if (code === "ENOENT") {
      return resolveParentRealPath(resolved);
    }
    // ELOOP (circular symlinks), EACCES (permission denied),
    // ENOTDIR (component not a directory), etc.
    // Cannot verify safety -- deny
    return null;
  }
}

/**
 * Walks up the directory tree until finding an existing ancestor,
 * resolves it with realpathSync, then re-appends the non-existent tail.
 *
 * Returns null if any ancestor throws a non-ENOENT error (ELOOP, EACCES)
 * -- this prevents skipping a malicious symlink by walking past it.
 * Also returns null if a dangling symlink is detected (symlink exists
 * but its target does not) -- prevents walking past unresolvable symlinks.
 */
function resolveParentRealPath(filePath: string): string | null {
  let current = filePath;
  const segments: string[] = [];

  while (current !== path.dirname(current)) {
    segments.push(path.basename(current));
    current = path.dirname(current);
    try {
      const realParent = fs.realpathSync(current);
      return path.join(realParent, ...segments.toReversed());
    } catch (err: unknown) {
      const code = (err as NodeJS.ErrnoException).code;
      if (code !== "ENOENT") {
        // Non-ENOENT error (ELOOP, EACCES) at an intermediate directory.
        // Cannot verify safety -- deny rather than walk past it.
        return null;
      }
      // ENOENT -- check if this is a dangling symlink rather than
      // a genuinely non-existent path component.
      try {
        const stat = fs.lstatSync(current);
        if (stat.isSymbolicLink()) {
          // Dangling symlink: the symlink exists but its target does not.
          // Cannot verify where it resolves -- deny.
          return null;
        }
      } catch {
        // lstat also failed -- truly non-existent, continue walking up
      }
    }
  }

  // Reached filesystem root without finding existing ancestor
  return path.join(current, ...segments.toReversed());
}

/**
 * Resolves a workspace path to its canonical form.
 * Falls back to path.resolve() only on ENOENT (e.g., test environments
 * with mock paths). Returns null on ELOOP, EACCES, or other errors
 * to maintain fail-closed consistency with resolveRealPath.
 */
function resolveWorkspacePath(workspacePath: string): string | null {
  try {
    return fs.realpathSync(path.resolve(workspacePath));
  } catch (err: unknown) {
    const code = (err as NodeJS.ErrnoException).code;
    if (code === "ENOENT") {
      return path.resolve(workspacePath);
    }
    return null;
  }
}

/**
 * Checks whether a file path resolves to a location within the workspace.
 *
 * Canonicalizes both paths -- resolving symlinks via fs.realpathSync --
 * then checks containment with a trailing `/` guard to prevent prefix
 * collisions (e.g., /workspaces/user1 must not match /workspaces/user10).
 *
 * @see https://cwe.mitre.org/data/definitions/22.html (CWE-22)
 * @see https://cwe.mitre.org/data/definitions/59.html (CWE-59)
 */
export function isPathInWorkspace(
  filePath: string,
  workspacePath: string,
): boolean {
  if (!filePath) return false;

  const realPath = resolveRealPath(filePath);
  if (realPath === null) return false;

  const resolvedWorkspace = resolveWorkspacePath(workspacePath);
  if (resolvedWorkspace === null) return false;

  return (
    realPath === resolvedWorkspace ||
    realPath.startsWith(resolvedWorkspace + "/")
  );
}
