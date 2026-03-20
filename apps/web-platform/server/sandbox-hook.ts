import type {
  HookCallback,
  PreToolUseHookInput,
} from "@anthropic-ai/claude-agent-sdk";
import { isPathInWorkspace } from "./sandbox";
import { containsSensitiveEnvAccess } from "./bash-sandbox";

// File-accessing tools and the input fields that carry paths.
// Read handles notebooks (.ipynb) natively -- no separate NotebookRead tool exists.
const FILE_TOOLS = new Set(["Read", "Write", "Edit", "Glob", "Grep"]);

export function createSandboxHook(workspacePath: string): HookCallback {
  return async (input, _toolUseID, _options) => {
    const preInput = input as PreToolUseHookInput;
    const toolInput = preInput.tool_input as Record<string, unknown>;
    const toolName = preInput.tool_name;

    // --- File-tool sandbox ---
    if (FILE_TOOLS.has(toolName)) {
      const filePath =
        (toolInput?.file_path as string) ||
        (toolInput?.path as string) ||
        "";

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

    // All checks passed -- return empty to continue permission chain
    return {};
  };
}
