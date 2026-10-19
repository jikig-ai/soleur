/**
 * Location-bearing patterns on file tools that have no `path` parameter for them.
 *
 * `extractToolPath` (tool-path-checker.ts) only sees file_path / path / notebook_path, and both
 * hooks let an EMPTY path through ("defaults to the workspace"). Glob's `pattern` and Grep's
 * `glob` are locations too: an absolute one (`/var/lib/soleur/egress-tokens/*`) lists any
 * directory in the container with no `path` at all, so it never reaches isPathInWorkspace.
 * The egress token dir is bind-mounted into the container and a token FILE NAME there is a
 * live gateway credential, so a listing is the theft. `denyRead` only masks SANDBOXED BASH;
 * these in-process tools run inside the CLI process, and AGENT_OUTER_WRAP is off in prod.
 *
 * Deny by SYNTAX, not by resolution (a glob has no single base directory): any alternative that
 * is absolute, starts with `~`, or carries a `..` segment escapes the workspace-relative
 * contract. Grep's regex `pattern` is searched CONTENT, not a location, so it is not checked.
 */

/** tool name -> the input field holding a glob (location), not a content regex. */
const GLOB_FIELD: Readonly<Record<string, string>> = { Glob: "pattern", Grep: "glob" };

export function patternEscapesWorkspace(
  toolName: string,
  toolInput: Record<string, unknown>,
): boolean {
  const field = GLOB_FIELD[toolName];
  if (!field) return false;
  const value = toolInput?.[field];
  if (typeof value !== "string" || value === "") return false;
  // Brace/comma alternatives are separate globs: `{src,/abs/dir}/*` names /abs/dir.
  for (const alt of value.split(/[{,]/)) {
    const g = alt.trim().replace(/^!+/, "");
    if (g.startsWith("/") || g.startsWith("~")) return true;
    if (g.split(/[\\/]/).includes("..")) return true;
  }
  return false;
}
