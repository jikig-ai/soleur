/**
 * Tool classification and path extraction for canUseTool workspace sandbox.
 *
 * Extracted from agent-runner.ts for unit testability without SDK/Supabase
 * dependencies. Follows the same extraction pattern as sandbox.ts and
 * error-sanitizer.ts.
 *
 * @see #891 - audit that added LS/NotebookRead/NotebookEdit to checked tools
 * @see #725 - original path traversal fix
 * @see #877 - symlink escape defense-in-depth
 */

/**
 * Tools with filesystem path inputs that must route through isPathInWorkspace.
 *
 * Parameter names vary by tool:
 * - file_path: Read, Write, Edit, NotebookRead (probable -- no exported SDK type)
 * - path: Glob, Grep, LS (probable -- no exported SDK type)
 * - notebook_path: NotebookEdit (confirmed via SDK NotebookEditInput)
 *
 * LS and NotebookRead are internal Claude Code tools without exported
 * ToolInputSchemas types. Parameter names are inferred from related tools
 * (FileReadInput, GlobInput) and checked defensively.
 */
export const FILE_TOOLS = [
  "Read",
  "Write",
  "Edit",
  "Glob",
  "Grep",
  "LS",
  "NotebookRead",
  "NotebookEdit",
] as const;

/**
 * SDK tools with no filesystem path inputs -- allowed without path checks.
 *
 * - Agent: orchestration tool (AgentInput: description/prompt/subagent_type)
 * - Skill: plugin-level tool (no exported SDK schema, no path args)
 * - TodoRead: in-memory task list (no exported SDK schema, no path args)
 * - TodoWrite: in-memory task list (TodoWriteInput: todos[] array only)
 *
 * NOTE: LS and NotebookRead removed from this list (#891) -- they accept
 * path inputs and must route through isPathInWorkspace. NotebookEdit also
 * added to the FILE_TOOLS list for defense-in-depth (previously hit
 * deny-by-default, now gets explicit path checking).
 */
export const SAFE_TOOLS = ["Agent", "Skill", "TodoRead", "TodoWrite"] as const;

/**
 * File tools whose parameter names are inferred (not confirmed via SDK
 * exported types). Used by the runtime warning in agent-runner.ts to
 * detect SDK parameter name changes. See #891.
 */
export const UNVERIFIED_PARAM_TOOLS = ["LS", "NotebookRead", "NotebookEdit"] as const;

/**
 * Extracts the filesystem path from a tool's input parameters.
 *
 * Checks all known parameter names used by file-accessing tools:
 * - file_path (Read, Write, Edit, NotebookRead)
 * - path (Glob, Grep, LS)
 * - notebook_path (NotebookEdit)
 *
 * Returns empty string if no recognized path parameter is found.
 */
export function extractToolPath(
  toolInput: Record<string, unknown>,
): string {
  return (
    (toolInput.file_path as string) ||
    (toolInput.path as string) ||
    (toolInput.notebook_path as string) ||
    ""
  );
}

/**
 * Checks whether a tool name is a file-accessing tool that requires
 * workspace path validation.
 */
export function isFileTool(toolName: string): boolean {
  return (FILE_TOOLS as readonly string[]).includes(toolName);
}

/**
 * Checks whether a tool name is in the safe tools list (no path inputs).
 */
export function isSafeTool(toolName: string): boolean {
  return (SAFE_TOOLS as readonly string[]).includes(toolName);
}
