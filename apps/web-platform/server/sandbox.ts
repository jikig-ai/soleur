import path from "path";

/**
 * Checks whether a file path resolves to a location within the workspace.
 *
 * Canonicalizes both paths with `path.resolve()` to neutralize `../` traversal
 * and appends a trailing `/` to the workspace path to prevent prefix collisions
 * (e.g., `/workspaces/user1` must not match `/workspaces/user10`).
 *
 * @see https://cwe.mitre.org/data/definitions/22.html (CWE-22)
 */
export function isPathInWorkspace(
  filePath: string,
  workspacePath: string,
): boolean {
  const resolved = path.resolve(filePath);
  const resolvedWorkspace = path.resolve(workspacePath);
  return (
    resolved === resolvedWorkspace ||
    resolved.startsWith(resolvedWorkspace + "/")
  );
}
