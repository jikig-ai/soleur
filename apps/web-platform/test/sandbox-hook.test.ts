import { describe, test, expect } from "vitest";
import { z } from "zod";
import type { SyncHookJSONOutput } from "@anthropic-ai/claude-agent-sdk";
import { createSandboxHook } from "../server/sandbox-hook";
import { FILE_TOOLS } from "../server/tool-path-checker";

const WORKSPACE = "/workspaces/user1";
const hook = createSandboxHook(WORKSPACE);
const signal = new AbortController().signal;

// Hand-written zod schema mirroring SDK `SyncHookJSONOutput` +
// `PreToolUseHookSpecificOutput`. Used to schema-validate hook returns at
// test time so that silently-malformed output (which surfaces as
// `ZodError: invalid_union` inside the CLI) fails the test here instead.
const preToolUseHookSpecificOutputSchema = z.object({
  hookEventName: z.literal("PreToolUse"),
  permissionDecision: z.enum(["allow", "deny", "ask"]).optional(),
  permissionDecisionReason: z.string().optional(),
});

const syncHookJSONOutputSchema = z.object({
  continue: z.boolean().optional(),
  suppressOutput: z.boolean().optional(),
  stopReason: z.string().optional(),
  decision: z.string().optional(),
  systemMessage: z.string().optional(),
  reason: z.string().optional(),
  hookSpecificOutput: preToolUseHookSpecificOutputSchema.optional(),
});

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

function expectExplicitAllow(result: SyncHookJSONOutput) {
  // Since the SDK's runtime discriminated-union parse (`ZodError:
  // invalid_union`) rejected the bare `{}` allow path in v0.2.80, we now
  // require an explicit PreToolUse allow output. Reverting to `{}` would
  // reintroduce the user-visible ZodError. See plan Phase 4a.
  const parsed = syncHookJSONOutputSchema.parse(result);
  expect(parsed.hookSpecificOutput).toEqual({
    hookEventName: "PreToolUse",
    permissionDecision: "allow",
  });
}

describe("createSandboxHook - file tools", () => {
  test.each([
    { tool: "Read", input: { file_path: "/etc/passwd" } },
    { tool: "Write", input: { file_path: "/tmp/evil.sh" } },
    { tool: "Edit", input: { file_path: "/etc/shadow" } },
    { tool: "Glob", input: { path: "/etc", pattern: "*.conf" } },
    { tool: "Grep", input: { path: "/etc", pattern: "password" } },
    { tool: "LS", input: { path: "/etc" } },
    { tool: "NotebookEdit", input: { notebook_path: "/tmp/evil.ipynb" } },
  ])("denies $tool outside workspace", async ({ tool, input }) => {
    const result = await invokeHook(tool, input);
    expectDenied(result, "workspace");
  });

  test("denies Read of /proc/1/environ at hook layer (defense-in-depth)", async () => {
    const result = await invokeHook("Read", {
      file_path: "/proc/1/environ",
    });
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
    expectExplicitAllow(result);
  });

  test("allows Edit inside workspace", async () => {
    const result = await invokeHook("Edit", {
      file_path: "/workspaces/user1/src/index.ts",
      old_string: "foo",
      new_string: "bar",
    });
    expectExplicitAllow(result);
  });

  test("allows Write targeting a path whose parent dir does not yet exist", async () => {
    // Regression: vision.md update triggers Write on
    // <workspace>/knowledge-base/overview/vision.md even before the
    // provisioner pre-creates overview/. The hook must allow because
    // isPathInWorkspace walks up to the first existing ancestor.
    const result = await invokeHook("Write", {
      file_path: "/workspaces/user1/knowledge-base/overview/vision.md",
      content: "# Vision\n",
    });
    expectExplicitAllow(result);
  });

  test("allows Read with empty file_path (not outside workspace)", async () => {
    const result = await invokeHook("Read", { file_path: "" });
    expectExplicitAllow(result);
  });

  test("deny includes permissionDecisionReason", async () => {
    const result = await invokeHook("Read", { file_path: "/etc/passwd" });
    const output = result.hookSpecificOutput as Record<string, unknown>;
    expect(output.permissionDecisionReason).toContain("outside workspace");
  });

  test("allows Glob with no path (defaults to CWD)", async () => {
    const result = await invokeHook("Glob", { pattern: "*.ts" });
    expectExplicitAllow(result);
  });

  test("allows Grep with no path (defaults to CWD)", async () => {
    const result = await invokeHook("Grep", { pattern: "TODO" });
    expectExplicitAllow(result);
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
    expectExplicitAllow(result);
  });

  test("allows Bash with empty command", async () => {
    const result = await invokeHook("Bash", { command: "" });
    expectExplicitAllow(result);
  });
});

describe("createSandboxHook - non-matched tools pass through", () => {
  test("returns explicit allow for AskUserQuestion (not in FILE_TOOLS or Bash)", async () => {
    const result = await invokeHook("AskUserQuestion", {
      question: "test?",
    });
    expectExplicitAllow(result);
  });

  test("returns explicit allow for Agent tool", async () => {
    const result = await invokeHook("Agent", { prompt: "do something" });
    expectExplicitAllow(result);
  });
});

describe("createSandboxHook - schema shape validation", () => {
  test("every allow return parses against SyncHookJSONOutput schema", async () => {
    const cases: Array<[string, Record<string, unknown>]> = [
      ["Read", { file_path: "/workspaces/user1/file.md" }],
      ["Write", { file_path: "/workspaces/user1/notes.md", content: "x" }],
      ["Edit", { file_path: "/workspaces/user1/src/i.ts", old_string: "a", new_string: "b" }],
      ["Glob", { pattern: "*.ts" }],
      ["Bash", { command: "ls" }],
      ["AskUserQuestion", { question: "?" }],
    ];
    for (const [tool, input] of cases) {
      const result = await invokeHook(tool, input);
      expect(() => syncHookJSONOutputSchema.parse(result)).not.toThrow();
    }
  });

  test("every deny return parses against SyncHookJSONOutput schema", async () => {
    const cases: Array<[string, Record<string, unknown>]> = [
      ["Write", { file_path: "/etc/passwd", content: "x" }],
      ["Bash", { command: "env" }],
    ];
    for (const [tool, input] of cases) {
      const result = await invokeHook(tool, input);
      const parsed = syncHookJSONOutputSchema.parse(result);
      expect(parsed.hookSpecificOutput?.permissionDecision).toBe("deny");
      expect(parsed.systemMessage).toBeTruthy();
    }
  });
});

describe("createSandboxHook - negative-space coverage", () => {
  test("FILE_TOOLS covers all file-accessing tools", () => {
    // Asserts against the actual exported constant, not a local copy.
    // If a file-access tool is added to or removed from the implementation,
    // this test fails. LS/NotebookRead/NotebookEdit added in #891.
    const fileToolsArray = [...FILE_TOOLS] as string[];
    const expectedFileTools = [
      "Read", "Write", "Edit", "Glob", "Grep",
      "LS", "NotebookRead", "NotebookEdit",
    ];
    expect(fileToolsArray.sort()).toEqual(expectedFileTools.sort());
  });

  test("safe tools do not overlap with FILE_TOOLS", () => {
    // LS removed from safe tools in #891 -- it has path inputs
    // Agent removed from safe tools in #910 -- handled explicitly in canUseTool
    const safeTools = ["Skill", "TodoRead", "TodoWrite"];
    const fileSet = new Set(FILE_TOOLS as readonly string[]);
    for (const tool of safeTools) {
      expect(fileSet.has(tool), `${tool} should NOT be a file tool`).toBe(false);
    }
  });
});
