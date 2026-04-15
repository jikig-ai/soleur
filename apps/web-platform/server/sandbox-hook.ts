import type {
  HookCallback,
  PreToolUseHookInput,
} from "@anthropic-ai/claude-agent-sdk";
import { isPathInWorkspace } from "./sandbox";
import { containsSensitiveEnvAccess } from "./bash-sandbox";
import { isFileTool, extractToolPath } from "./tool-path-checker";

export function createSandboxHook(workspacePath: string): HookCallback {
  return async (input, _toolUseID, _options) => {
    const preInput = input as PreToolUseHookInput;
    const toolInput = preInput.tool_input as Record<string, unknown>;
    const toolName = preInput.tool_name;

    // --- File-tool sandbox ---
    // Uses shared FILE_TOOLS list from tool-path-checker.ts.
    // Includes LS, NotebookRead, and NotebookEdit (#891).
    if (isFileTool(toolName)) {
      const filePath = extractToolPath(toolInput ?? {});

      // Empty path is allowed through -- Glob/Grep default to CWD (workspacePath),
      // and Read/Write/Edit require file_path so the SDK rejects empty values.
      if (filePath && !isPathInWorkspace(filePath, workspacePath)) {
        return {
          systemMessage:
            "File access outside the workspace is not permitted. " +
            "All file operations must target paths within the user workspace.",
          hookSpecificOutput: {
            hookEventName: "PreToolUse" as const,
            permissionDecision: "deny" as const,
            permissionDecisionReason:
              "Access denied: file path outside workspace boundary",
          },
        };
      }
    }

    // --- Bash env-access defense-in-depth ---
    if (toolName === "Bash") {
      const command = (toolInput?.command as string) || "";
      if (containsSensitiveEnvAccess(command)) {
        return {
          systemMessage:
            "Accessing sensitive environment variables is not permitted. " +
            "The agent environment contains only safe variables.",
          hookSpecificOutput: {
            hookEventName: "PreToolUse" as const,
            permissionDecision: "deny" as const,
            permissionDecisionReason:
              "Access denied: sensitive environment variable access",
          },
        };
      }
    }

    // Explicit PreToolUse allow. SDK v0.2.80 rejected bare `{}` with
    // ZodError: invalid_union. Hook schema differs from canUseTool —
    // no updatedInput field here.
    return {
      hookSpecificOutput: {
        hookEventName: "PreToolUse" as const,
        permissionDecision: "allow" as const,
      },
    };
  };
}
