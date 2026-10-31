import { afterAll, beforeAll, describe, test, expect } from "vitest";
import { mkdirSync, mkdtempSync, realpathSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import type { SyncHookJSONOutput } from "@anthropic-ai/claude-agent-sdk";
import { createSandboxHook } from "../server/sandbox-hook";
import { FILE_TOOLS } from "../server/tool-path-checker";

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

// Reverting to `{}` would reintroduce the SDK v0.2.80 `ZodError:
// invalid_union` in the web-UI chat. Keep this assertion strict.
function expectExplicitAllow(result: SyncHookJSONOutput) {
  expect(result.hookSpecificOutput).toEqual({
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

  // Glob `pattern` / Grep `glob` carry a location but no `path` param: an absolute one
  // lists any directory in the container, including the egress token dir whose file
  // NAMES are live gateway credentials (the dir is bind-mounted into the container).
  test.each([
    { tool: "Glob", input: { pattern: "/var/lib/soleur/egress-tokens/*" } },
    { tool: "Glob", input: { pattern: "~/.claude/**" } },
    { tool: "Glob", input: { pattern: "../user2/**" } },
    { tool: "Grep", input: { pattern: "x", glob: "/var/lib/soleur/egress-tokens/*" } },
    // an in-workspace `path` must NOT excuse an escaping pattern (the CLI lets an absolute pattern win over `path`)
    { tool: "Glob", input: { path: "/workspaces/user1", pattern: "/var/lib/soleur/egress-tokens/*" } },
    { tool: "Grep", input: { path: "/workspaces/user1", pattern: "x", glob: "/var/lib/soleur/egress-tokens/*" } },
    { tool: "Glob", input: { pattern: "{/var/lib/soleur/egress-tokens,x}/*" } },
  ])("denies $tool with an escaping pattern/glob ($input)", async ({ tool, input }) => {
    const result = await invokeHook(tool, input);
    expectDenied(result, "outside the workspace");
  });

  test("allows Grep whose regex pattern looks like a path (content, not a location)", async () => {
    const result = await invokeHook("Grep", { pattern: "/etc/passwd", glob: "*.md" });
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

  // #10054: a hook `allow` resolves the permission BEFORE `canUseTool` (SDK 0.3.284), which made every
  // Bash gate in createCanUseTool inert. The hook must give Bash NO decision so `canUseTool` decides.
  function expectNoDecision(result: SyncHookJSONOutput) {
    expect(result.hookSpecificOutput).toBeUndefined();
    expect(result.continue).toBe(true);
  }

  test("gives a clean Bash command no decision (canUseTool decides)", async () => {
    expectNoDecision(await invokeHook("Bash", { command: "ls -la" }));
  });

  test("gives Bash with an empty command no decision", async () => {
    expectNoDecision(await invokeHook("Bash", { command: "" }));
  });

  test("gives a destroy-family Bash command no decision (never an allow)", async () => {
    expectNoDecision(await invokeHook("Bash", { command: "git push --force origin main" }));
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

// #10455 PR 1a: the file tools (Read, Grep, Glob, LS, Notebook*) run in the CLI process OUTSIDE bwrap, so the sandbox
// `denyRead` list never applies to them; this hook is their only containment. The shared HOME holds the CLI's persisted
// state for EVERY tenant on the host (history, session metadata, shell snapshots), so each of those paths, reached by an
// absolute path, a relative escape, a glob, or a symlink planted inside the workspace, must be refused here.
describe("createSandboxHook - the shared HOME's persisted CLI state is unreachable through the file tools (#10455)", () => {
  let base: string;
  let ws: string;
  let home: string;
  let realHook: ReturnType<typeof createSandboxHook>;

  const call = async (toolName: string, toolInput: Record<string, unknown>) =>
    (await realHook(makeInput(toolName, toolInput), "test-id", { signal })) as SyncHookJSONOutput;

  beforeAll(() => {
    base = realpathSync(mkdtempSync(join(tmpdir(), "sbx-hook-home-")));
    ws = join(base, "workspaces", "00000000-0000-0000-0000-00000000000a");
    home = join(base, "home");
    mkdirSync(ws, { recursive: true });
    mkdirSync(join(home, ".claude", "sessions"), { recursive: true });
    mkdirSync(join(home, ".claude", "shell-snapshots"), { recursive: true });
    writeFileSync(join(home, ".claude", "history.jsonl"), "{}\n");
    writeFileSync(join(home, ".claude", "sessions", "1.json"), "{}");
    writeFileSync(join(home, ".claude", "shell-snapshots", "snapshot-bash-1.sh"), "# snapshot\n");
    writeFileSync(join(ws, "ok.txt"), "own file\n");
    // A symlink planted INSIDE the workspace that points at a sibling-visible HOME file.
    symlinkSync(join(home, ".claude", "history.jsonl"), join(ws, "link-to-history"));
    realHook = createSandboxHook(ws);
  });

  afterAll(() => {
    rmSync(base, { recursive: true, force: true });
  });

  test("positive control: a file inside the workspace is allowed, so the denials below are not an everything-denied hook", async () => {
    expectExplicitAllow(await call("Read", { file_path: join(ws, "ok.txt") }));
  });

  test.each([
    ["Read history.jsonl", "Read", () => ({ file_path: join(home, ".claude", "history.jsonl") })],
    ["Read a session metadata file", "Read", () => ({ file_path: join(home, ".claude", "sessions", "1.json") })],
    ["Read a shell snapshot", "Read", () => ({ file_path: join(home, ".claude", "shell-snapshots", "snapshot-bash-1.sh") })],
    ["Grep the .claude directory", "Grep", () => ({ pattern: "x", path: join(home, ".claude") })],
    ["LS the sessions directory", "LS", () => ({ path: join(home, ".claude", "sessions") })],
    ["NotebookRead outside the workspace", "NotebookRead", () => ({ notebook_path: join(home, ".claude", "x.ipynb") })],
    ["Read through a relative escape", "Read", () => ({ file_path: join(ws, "..", "..", "home", ".claude", "history.jsonl") })],
    ["Read through a symlink planted in the workspace", "Read", () => ({ file_path: join(ws, "link-to-history") })],
    ["Glob with an absolute pattern into HOME", "Glob", () => ({ pattern: `${home}/.claude/**/*.json` })],
    ["Glob with a relative escape pattern", "Glob", () => ({ pattern: "../../home/.claude/*" })],
  ])("%s is refused", async (_label, tool, input) => {
    const result = await call(tool, input());
    expectDenied(result, "outside the workspace");
  });
});
