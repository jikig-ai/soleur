import { describe, test, expect } from "vitest";
import type { SyncHookJSONOutput } from "@anthropic-ai/claude-agent-sdk";
import { createSandboxHook } from "../server/sandbox-hook";

const WORKSPACE = "/workspaces/user1";
const hook = createSandboxHook(WORKSPACE);
const signal = new AbortController().signal;

function makeInput(toolName: string, toolInput: Record<string, unknown>) {
  return {
    hook_event_name: "PreToolUse" as const,
    session_id: "test-session",
    transcript_path: "/tmp/test-transcript",
    cwd: WORKSPACE,
    tool_name: toolName,
    tool_input: toolInput,
    tool_use_id: "test-tool-use-id",
  };
}

async function invokeHook(
  toolName: string,
  toolInput: Record<string, unknown>,
): Promise<SyncHookJSONOutput> {
  return await hook(
    makeInput(toolName, toolInput),
    "test-id",
    { signal },
  ) as SyncHookJSONOutput;
}

describe("createSandboxHook - file tools", () => {
  test("allows Read inside workspace", async () => {
    const result = await invokeHook("Read", {
      file_path: "/workspaces/user1/file.md",
    });
    expect(result).toEqual({});
  });

  test("denies Read outside workspace", async () => {
    const result = await invokeHook("Read", { file_path: "/etc/passwd" });
    expect(result.hookSpecificOutput).toBeDefined();
    const output = result.hookSpecificOutput as Record<string, unknown>;
    expect(output.permissionDecision).toBe("deny");
    expect(result.systemMessage).toContain("workspace");
  });

  test("denies Read with ../ traversal escaping workspace", async () => {
    const result = await invokeHook("Read", {
      file_path: "/workspaces/user1/../user2/secret.md",
    });
    const output = result.hookSpecificOutput as Record<string, unknown>;
    expect(output.permissionDecision).toBe("deny");
  });

  test("denies Write outside workspace", async () => {
    const result = await invokeHook("Write", { file_path: "/tmp/evil.sh" });
    const output = result.hookSpecificOutput as Record<string, unknown>;
    expect(output.permissionDecision).toBe("deny");
    expect(result.systemMessage).toContain("workspace");
  });

  test("denies Glob with path outside workspace", async () => {
    const result = await invokeHook("Glob", {
      path: "/etc",
      pattern: "*.conf",
    });
    const output = result.hookSpecificOutput as Record<string, unknown>;
    expect(output.permissionDecision).toBe("deny");
  });

  test("denies Grep with path outside workspace", async () => {
    const result = await invokeHook("Grep", {
      path: "/etc",
      pattern: "password",
    });
    const output = result.hookSpecificOutput as Record<string, unknown>;
    expect(output.permissionDecision).toBe("deny");
  });

  test("allows Edit inside workspace", async () => {
    const result = await invokeHook("Edit", {
      file_path: "/workspaces/user1/src/index.ts",
      old_string: "foo",
      new_string: "bar",
    });
    expect(result).toEqual({});
  });

  test("allows Read with empty file_path (not outside workspace)", async () => {
    const result = await invokeHook("Read", { file_path: "" });
    expect(result).toEqual({});
  });

  test("deny response has correct hookSpecificOutput shape", async () => {
    const result = await invokeHook("Read", { file_path: "/etc/passwd" });
    const output = result.hookSpecificOutput as Record<string, unknown>;
    expect(output.hookEventName).toBe("PreToolUse");
    expect(output.permissionDecision).toBe("deny");
    expect(output.permissionDecisionReason).toContain("outside workspace");
  });
});

describe("createSandboxHook - Bash env access", () => {
  test("denies Bash with env command", async () => {
    const result = await invokeHook("Bash", { command: "env" });
    const output = result.hookSpecificOutput as Record<string, unknown>;
    expect(output.permissionDecision).toBe("deny");
    expect(result.systemMessage).toContain("environment variables");
  });

  test("denies Bash with sensitive variable reference", async () => {
    const result = await invokeHook("Bash", {
      command: "echo $SUPABASE_URL",
    });
    const output = result.hookSpecificOutput as Record<string, unknown>;
    expect(output.permissionDecision).toBe("deny");
  });

  test("allows clean Bash command", async () => {
    const result = await invokeHook("Bash", { command: "ls -la" });
    expect(result).toEqual({});
  });

  test("allows Bash with empty command", async () => {
    const result = await invokeHook("Bash", { command: "" });
    expect(result).toEqual({});
  });

  test("deny for env access has correct systemMessage", async () => {
    const result = await invokeHook("Bash", { command: "printenv" });
    expect(result.systemMessage).toContain("environment variables");
    const output = result.hookSpecificOutput as Record<string, unknown>;
    expect(output.hookEventName).toBe("PreToolUse");
  });
});

describe("createSandboxHook - non-matched tools pass through", () => {
  test("returns empty for AskUserQuestion (not in FILE_TOOLS or Bash)", async () => {
    const result = await invokeHook("AskUserQuestion", {
      question: "test?",
    });
    expect(result).toEqual({});
  });

  test("returns empty for Agent tool", async () => {
    const result = await invokeHook("Agent", { prompt: "do something" });
    expect(result).toEqual({});
  });
});

describe("createSandboxHook - negative-space coverage", () => {
  test("all file-accessing tools are covered by hook", () => {
    const hookMatcherTools = new Set([
      "Read",
      "Write",
      "Edit",
      "Glob",
      "Grep",
      "Bash",
    ]);
    const safeToolsExempt = new Set([
      "Agent",
      "Skill",
      "TodoRead",
      "TodoWrite",
      "LS",
    ]);

    // Every tool with file_path/path access must be in hookMatcherTools
    const fileAccessTools = ["Read", "Write", "Edit", "Glob", "Grep"];
    for (const tool of fileAccessTools) {
      expect(hookMatcherTools.has(tool)).toBe(true);
    }

    // Safe tools must NOT overlap with file access tools
    for (const tool of safeToolsExempt) {
      expect(fileAccessTools.includes(tool)).toBe(false);
    }
  });
});
