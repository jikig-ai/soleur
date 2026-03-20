import { describe, test, expect } from "vitest";
import type { SyncHookJSONOutput } from "@anthropic-ai/claude-agent-sdk";
import { createSandboxHook, FILE_TOOLS } from "../server/sandbox-hook";

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

function expectDenied(result: SyncHookJSONOutput, messageSubstring: string) {
  const output = result.hookSpecificOutput as Record<string, unknown>;
  expect(output.hookEventName).toBe("PreToolUse");
  expect(output.permissionDecision).toBe("deny");
  expect(result.systemMessage).toContain(messageSubstring);
}

describe("createSandboxHook - file tools", () => {
  test.each([
    { tool: "Read", input: { file_path: "/etc/passwd" } },
    { tool: "Write", input: { file_path: "/tmp/evil.sh" } },
    { tool: "Edit", input: { file_path: "/etc/shadow" } },
    { tool: "Glob", input: { path: "/etc", pattern: "*.conf" } },
    { tool: "Grep", input: { path: "/etc", pattern: "password" } },
  ])("denies $tool outside workspace", async ({ tool, input }) => {
    const result = await invokeHook(tool, input);
    expectDenied(result, "workspace");
  });

  test("denies Read with ../ traversal escaping workspace", async () => {
    const result = await invokeHook("Read", {
      file_path: "/workspaces/user1/../user2/secret.md",
    });
    expectDenied(result, "workspace");
  });

  test("allows Read inside workspace", async () => {
    const result = await invokeHook("Read", {
      file_path: "/workspaces/user1/file.md",
    });
    expect(result).toEqual({});
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

  test("deny includes permissionDecisionReason", async () => {
    const result = await invokeHook("Read", { file_path: "/etc/passwd" });
    const output = result.hookSpecificOutput as Record<string, unknown>;
    expect(output.permissionDecisionReason).toContain("outside workspace");
  });

  test("allows Glob with no path (defaults to CWD)", async () => {
    const result = await invokeHook("Glob", { pattern: "*.ts" });
    expect(result).toEqual({});
  });

  test("allows Grep with no path (defaults to CWD)", async () => {
    const result = await invokeHook("Grep", { pattern: "TODO" });
    expect(result).toEqual({});
  });
});

describe("createSandboxHook - Bash env access", () => {
  test.each([
    { command: "env", label: "env command" },
    { command: "printenv", label: "printenv command" },
    { command: "echo $SUPABASE_URL", label: "sensitive variable reference" },
  ])("denies Bash with $label", async ({ command }) => {
    const result = await invokeHook("Bash", { command });
    expectDenied(result, "environment variables");
  });

  test("allows clean Bash command", async () => {
    const result = await invokeHook("Bash", { command: "ls -la" });
    expect(result).toEqual({});
  });

  test("allows Bash with empty command", async () => {
    const result = await invokeHook("Bash", { command: "" });
    expect(result).toEqual({});
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
  test("FILE_TOOLS covers all file-accessing tools", () => {
    // Asserts against the actual exported constant, not a local copy.
    // If a file-access tool is added to or removed from the implementation,
    // this test fails.
    const expectedFileTools = ["Read", "Write", "Edit", "Glob", "Grep"];
    expect([...FILE_TOOLS].sort()).toEqual(expectedFileTools.sort());
  });

  test("safe tools do not overlap with FILE_TOOLS", () => {
    const safeTools = ["Agent", "Skill", "TodoRead", "TodoWrite", "LS"];
    for (const tool of safeTools) {
      expect(FILE_TOOLS.has(tool)).toBe(false);
    }
  });
});
