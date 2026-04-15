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

    // All checks passed. Return an explicit PreToolUse allow output
    // instead of `{}`. In SDK v0.2.80 the runtime Zod schema for hook
    // outputs produced `invalid_union` errors on the bare `{}` allow
    // path in some tool-call paths, which surfaced to the user as a
    // ZodError on Write/Edit. Shipping an explicit discriminated-union
    // branch satisfies both the permissive and strict schema variants.
    return {
      hookSpecificOutput: {
        hookEventName: "PreToolUse" as const,
        permissionDecision: "allow" as const,
      },
    };
  };
}
