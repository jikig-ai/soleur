import type {
  HookCallback,
  PreToolUseHookInput,
} from "@anthropic-ai/claude-agent-sdk";
import { isPathInWorkspace } from "./sandbox";
import { containsSensitiveEnvAccess } from "./bash-sandbox";
import { isFileTool, pathFieldsEscape } from "./tool-path-checker";
import { patternEscapesWorkspace } from "./tool-pattern-checker";
import { logPermissionDecision } from "./permission-log";
import {
  createGitCarrierDenyReporter,
  GIT_CARRIER_DENY_MESSAGE,
  gitCarrierMatch,
} from "./git-carrier-guard";

export function createSandboxHook(workspacePath: string): HookCallback {
  // #9600 — one budgeted reporter per hook instance (a session) for the `.git` file-tool deny.
  const reportGitCarrierDeny = createGitCarrierDenyReporter();
  return async (input, _toolUseID, _options) => {
    const preInput = input as PreToolUseHookInput;
    const toolInput = preInput.tool_input as Record<string, unknown>;
    const toolName = preInput.tool_name;

    // --- File-tool sandbox ---
    // Uses shared FILE_TOOLS list from tool-path-checker.ts.
    // Includes LS, NotebookRead, and NotebookEdit (#891).
    if (isFileTool(toolName)) {
      // Empty path is allowed through -- Glob/Grep default to CWD (workspacePath),
      // and Read/Write/Edit require file_path so the SDK rejects empty values. EVERY present
      // location field is checked, not just the first truthy one (#10455).
      const pathEscapes = pathFieldsEscape(toolInput ?? {}, (p) => isPathInWorkspace(p, workspacePath));
      const patternEscapes = !pathEscapes && patternEscapesWorkspace(toolName, toolInput ?? {});
      if (pathEscapes || patternEscapes) {
        // A distinct reason: an absolute Glob pattern is an attempt to ENUMERATE a directory (the egress
        // token dir's file names are credentials), which an ordinary path escape is not.
        logPermissionDecision(
          "sandbox-hook",
          toolName,
          "deny",
          patternEscapes ? "glob pattern outside workspace" : "file path outside workspace",
        );
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

    // --- Git config-carrier guard (#9600) ---
    // Write / Edit / NotebookEdit into any `.git` path plants a repo-local config that the auto-approved
    // git reads would execute. Plain deny; `git config` through Bash still reaches the review card.
    {
      const carrierMatch = gitCarrierMatch(toolName, toolInput ?? {}, workspacePath);
      if (carrierMatch) {
        logPermissionDecision("sandbox-hook", toolName, "deny", "git-carrier-path");
        reportGitCarrierDeny(toolName, "sandbox-hook", carrierMatch);
        return {
          systemMessage: GIT_CARRIER_DENY_MESSAGE,
          hookSpecificOutput: {
            hookEventName: "PreToolUse" as const,
            permissionDecision: "deny" as const,
            permissionDecisionReason: "Access denied: git configuration and hooks are protected",
          },
        };
      }
    }

    // --- Bash env-access defense-in-depth ---
    if (toolName === "Bash") {
      const command = (toolInput?.command as string) || "";
      if (containsSensitiveEnvAccess(command)) {
        logPermissionDecision("sandbox-hook", toolName, "deny", "sensitive env access");
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

    // Bash: NO permission decision from this hook (#10054). A hook `allow` resolves the
    // permission before `canUseTool` is consulted (SDK 0.3.284 with its bundled CLI 2.1.284, measured by
    // the real-SDK C9 probe under scripts/), which silently disabled every Bash gate in
    // `createCanUseTool` (safe-Bash allowlist, must-ask lane, batch cache, autonomous
    // toggle). The deny above stays; the allow/ask verdict belongs to `canUseTool`.
    // `continue: true` is the SDK's documented "no decision" hook output (verified on the live CLI by the probe). The explicit
    // allow below stays for the other tools: their behaviour is deliberately unchanged here.
    if (toolName === "Bash") {
      logPermissionDecision("sandbox-hook", toolName, "defer");
      return { continue: true };
    }

    // Explicit PreToolUse allow. SDK v0.2.80 rejected bare `{}` with
    // ZodError: invalid_union. Hook schema differs from canUseTool —
    // no updatedInput field here.
    logPermissionDecision("sandbox-hook", toolName, "allow");
    return {
      hookSpecificOutput: {
        hookEventName: "PreToolUse" as const,
        permissionDecision: "allow" as const,
      },
    };
  };
}
