// #9600 — the `.git` file-tool carrier guard. A write into any `.git` path plants a repo-local config that
// the auto-approved git reads would execute (measured: test/safe-bash-git-config-exec.test.ts). Both
// enforcement points (PreToolUse sandbox hook, canUseTool) must refuse it; reads and look-alike names pass.
import { afterAll, beforeAll, beforeEach, describe, expect, test, vi } from "vitest";
import { mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import type { PermissionResult, SyncHookJSONOutput } from "@anthropic-ai/claude-agent-sdk";

const { mockWarnSilentFallback } = vi.hoisted(() => ({ mockWarnSilentFallback: vi.fn() }));
vi.mock("../server/observability", async (importOriginal) => ({
  ...(await importOriginal<typeof import("../server/observability")>()),
  warnSilentFallback: mockWarnSilentFallback,
}));

import {
  GIT_CARRIER_DENY_MESSAGE,
  GIT_CARRIER_WRITE_TOOLS,
  createGitCarrierDenyReporter,
  gitCarrierMatch,
  gitCarrierTouched,
} from "../server/git-carrier-guard";
import { createSandboxHook } from "../server/sandbox-hook";
import { createCanUseTool, type CanUseToolContext } from "../server/permission-callback";
import { FILE_TOOLS } from "../server/tool-path-checker";

let ws: string;
let outside: string;

beforeAll(() => {
  const root = realpathSync(mkdtempSync(join(tmpdir(), "git-carrier-")));
  ws = join(root, "workspace");
  outside = join(root, "outside");
  mkdirSync(join(ws, ".git", "hooks"), { recursive: true });
  writeFileSync(join(ws, ".git", "config"), "[core]\n");
  mkdirSync(join(ws, "sub", ".git"), { recursive: true });
  mkdirSync(join(ws, "sub2"), { recursive: true });
  writeFileSync(join(ws, "sub2", ".git"), "gitdir: ../.git/modules/sub2\n"); // gitdir pointer FILE
  mkdirSync(join(ws, ".GIT"), { recursive: true });
  mkdirSync(join(ws, "src", ".github", "workflows"), { recursive: true });
  mkdirSync(join(ws, "docs"), { recursive: true });
  symlinkSync(join(ws, ".git"), join(ws, "g")); // g -> .git
  symlinkSync(join(ws, "sub", ".git"), join(ws, "docs", "link")); // nested symlink to a .git dir
  mkdirSync(outside, { recursive: true });
});
afterAll(() => rmSync(resolve(ws, ".."), { recursive: true, force: true }));

describe("gitCarrierMatch — the helper", () => {
  // Every row is a write-class tool addressing a `.git` path. `match` is the class the event carries.
  const DENIED: Array<[string, string, Record<string, unknown>, string]> = [
    ["direct config, relative", "Write", { file_path: ".git/config" }, "lexical"],
    ["direct config, absolute", "Write", { file_path: "<ws>/.git/config" }, "lexical"],
    ["hooks", "Edit", { file_path: ".git/hooks/pre-commit" }, "lexical"],
    ["nested repo", "Write", { file_path: "sub/.git/config" }, "lexical"],
    ["uppercase", "Write", { file_path: ".GIT/config" }, "lexical"],
    ["mixed case", "Write", { file_path: "a/.Git/hooks/x" }, "lexical"],
    ["gitdir pointer file", "Write", { file_path: "sub2/.git" }, "lexical"],
    ["dot-dot that lands inside", "Write", { file_path: "src/../.git/config" }, "lexical"],
    ["not-yet-existing .git dir", "Write", { file_path: "fresh/.git/config" }, "lexical"],
    ["notebook path", "NotebookEdit", { notebook_path: ".git/info/x.ipynb" }, "lexical"],
    ["path field", "Edit", { path: ".git/config" }, "lexical"],
    ["surrounding whitespace", "Write", { file_path: "  .git/config " }, "lexical"],
    ["backslash separator", "Write", { file_path: "sub\\.git\\config" }, "lexical"],
    ["symlink g -> .git", "Write", { file_path: "g/config" }, "resolved"],
    ["symlink to nested .git, not-yet-existing leaf", "Write", { file_path: "docs/link/newfile" }, "resolved"],
  ];
  test.each(DENIED)("denies: %s", (_name, tool, input, match) => {
    const resolved = Object.fromEntries(
      Object.entries(input).map(([k, v]) => [k, typeof v === "string" ? v.replace("<ws>", ws) : v]),
    );
    expect(gitCarrierMatch(tool, resolved, ws)).toBe(match);
    expect(gitCarrierTouched(tool, resolved, ws)).toBe(true);
  });

  const ALLOWED: Array<[string, string, Record<string, unknown>]> = [
    [".gitignore", "Write", { file_path: ".gitignore" }],
    [".github workflow", "Write", { file_path: "src/.github/workflows/x.yml" }],
    [".gitmodules", "Edit", { file_path: ".gitmodules" }],
    ["docs name containing git", "Write", { file_path: "docs/git-notes.md" }],
    ["a component that merely ends in .git", "Write", { file_path: "repo.git/notes.md" }],
    ["plain source", "Edit", { file_path: "src/index.ts" }],
    ["plain notebook", "NotebookEdit", { notebook_path: "docs/n.ipynb" }],
    ["no location at all", "Write", {}],
    ["read of .git is not the carrier", "Read", { file_path: ".git/config" }],
    ["grep of .git is not the carrier", "Grep", { path: ".git" }],
    ["glob of .git is not the carrier", "Glob", { path: ".git", pattern: "*" }],
    ["LS of .git is not the carrier", "LS", { path: ".git" }],
  ];
  test.each(ALLOWED)("does not match: %s", (_name, tool, input) => {
    expect(gitCarrierMatch(tool, input, ws)).toBeNull();
  });

  test("fails CLOSED on non-string and non-object input", () => {
    for (const bad of [{ file_path: 42 }, { file_path: ["a"] }, { notebook_path: {} }, { path: true }]) {
      expect(gitCarrierMatch("Write", bad, ws)).toBe("malformed");
    }
    for (const bad of [null, undefined, "x", 3]) {
      expect(gitCarrierMatch("Edit", bad, ws)).toBe("malformed");
    }
  });

  test("a .git component in the WORKSPACE root itself does not poison every write", () => {
    const odd = join(resolve(ws, ".."), "w", ".git-host", "ws");
    mkdirSync(odd, { recursive: true });
    expect(gitCarrierMatch("Write", { file_path: "src/a.ts" }, odd)).toBeNull();
    expect(gitCarrierMatch("Write", { file_path: ".git/config" }, odd)).toBe("lexical");
  });

  test("a path escaping the workspace is judged on its full form (fail closed)", () => {
    expect(gitCarrierMatch("Write", { file_path: join(outside, ".git", "config") }, ws)).toBe("lexical");
    expect(gitCarrierMatch("Write", { file_path: join(outside, "ok.txt") }, ws)).toBeNull();
  });

  test("the guarded tool set is exactly the write-class file tools, and a subset of FILE_TOOLS", () => {
    expect([...GIT_CARRIER_WRITE_TOOLS].sort()).toEqual(["Edit", "NotebookEdit", "Write"]);
    for (const t of GIT_CARRIER_WRITE_TOOLS) expect(FILE_TOOLS as readonly string[]).toContain(t);
    // write-class parity: every FILE_TOOLS member that can write must be guarded (read-class ones are not)
    const READ_CLASS = ["Read", "Glob", "Grep", "LS", "NotebookRead"];
    const writeClass = (FILE_TOOLS as readonly string[]).filter((t) => !READ_CLASS.includes(t)).sort();
    expect(writeClass).toEqual([...GIT_CARRIER_WRITE_TOOLS].sort());
  });
});

describe("deny reporter — budgeted, deduped, no path or content in the event", () => {
  beforeEach(() => mockWarnSilentFallback.mockClear());

  test("one event per (tool, enforcement, match); budget caps the total", () => {
    const report = createGitCarrierDenyReporter();
    report("Write", "sandbox-hook", "lexical");
    report("Write", "sandbox-hook", "lexical");
    report("Write", "canUseTool", "lexical");
    expect(mockWarnSilentFallback).toHaveBeenCalledTimes(2);
    const call = mockWarnSilentFallback.mock.calls[0];
    expect(call[1]).toMatchObject({ feature: "cc-permissions", op: "git-carrier-write-denied" });
    expect(Object.keys(call[1].extra).sort()).toEqual(["enforcement", "match", "toolName"]);
    for (let i = 0; i < 20; i++) report(`Tool${i}`, "canUseTool", "resolved");
    expect(mockWarnSilentFallback.mock.calls.length).toBeLessThanOrEqual(8);
  });
});

describe("enforcement point 1: PreToolUse sandbox hook", () => {
  const signal = new AbortController().signal;
  const run = async (tool: string, input: Record<string, unknown>) =>
    (await createSandboxHook(ws)(
      {
        hook_event_name: "PreToolUse" as const,
        session_id: "s",
        transcript_path: "/tmp/t",
        cwd: ws,
        tool_name: tool,
        tool_input: input,
        tool_use_id: "u",
      },
      "id",
      { signal },
    )) as SyncHookJSONOutput;

  beforeEach(() => mockWarnSilentFallback.mockClear());

  test("denies a .git write with the plain message and emits one event", async () => {
    const out = await run("Write", { file_path: ".git/config" });
    const hso = out.hookSpecificOutput as Record<string, unknown>;
    expect(hso.permissionDecision).toBe("deny");
    expect(out.systemMessage).toBe(GIT_CARRIER_DENY_MESSAGE);
    expect(GIT_CARRIER_DENY_MESSAGE).toContain("git config");
    expect(mockWarnSilentFallback).toHaveBeenCalledTimes(1);
    expect(mockWarnSilentFallback.mock.calls[0][1].extra).toMatchObject({ enforcement: "sandbox-hook" });
  });

  test("denies the symlink spelling", async () => {
    const out = await run("Edit", { file_path: "g/config" });
    expect((out.hookSpecificOutput as Record<string, unknown>).permissionDecision).toBe("deny");
  });

  test.each([
    ["Write", { file_path: "src/.github/workflows/x.yml" }],
    ["Write", { file_path: ".gitignore" }],
    ["Write", { file_path: "docs/git-notes.md" }],
    ["Read", { file_path: ".git/config" }],
  ])("allows %s %j", async (tool, input) => {
    const out = await run(tool, input as Record<string, unknown>);
    expect((out.hookSpecificOutput as Record<string, unknown>).permissionDecision).toBe("allow");
  });
});

describe("enforcement point 2: canUseTool file-tool branch", () => {
  function ctx(): CanUseToolContext {
    return {
      userId: "user-1",
      conversationId: "conv-1",
      leaderId: "cc_router",
      workspacePath: ws,
      platformToolNames: [],
      pluginMcpServerNames: [],
      repoOwner: "alice",
      repoName: "repo",
      session: { abort: new AbortController(), reviewGateResolvers: new Map(), sessionId: null },
      controllerSignal: new AbortController().signal,
      deps: {
        abortableReviewGate: vi.fn().mockResolvedValue("Approve"),
        sendToClient: vi.fn().mockReturnValue(true),
        notifyOfflineUser: vi.fn().mockResolvedValue(undefined),
        updateConversationStatus: vi.fn().mockResolvedValue(undefined),
      },
    } as unknown as CanUseToolContext;
  }
  const opts = () => ({ signal: new AbortController().signal, toolUseID: "tu", requestId: "r" });

  beforeEach(() => mockWarnSilentFallback.mockClear());

  test.each([
    ["Write", { file_path: ".git/config" }],
    ["Edit", { file_path: "sub/.git/hooks/pre-commit" }],
    ["NotebookEdit", { notebook_path: ".GIT/x.ipynb" }],
    ["Write", { file_path: "g/config" }],
  ])("denies %s %j with the plain message", async (tool, input) => {
    const can = createCanUseTool(ctx());
    const res = (await can(tool, input as Record<string, unknown>, opts())) as PermissionResult;
    expect(res.behavior).toBe("deny");
    if (res.behavior === "deny") expect(res.message).toContain(GIT_CARRIER_DENY_MESSAGE);
    expect(mockWarnSilentFallback.mock.calls.some((c) => c[1]?.op === "git-carrier-write-denied")).toBe(true);
  });

  test.each([
    ["Write", { file_path: "src/.github/workflows/x.yml" }],
    ["Write", { file_path: ".gitignore" }],
    ["Read", { file_path: ".git/config" }],
  ])("allows %s %j", async (tool, input) => {
    const can = createCanUseTool(ctx());
    const res = (await can(tool, input as Record<string, unknown>, opts())) as PermissionResult;
    expect(res.behavior).toBe("allow");
  });
});

describe("no file-tool enforcement path bypasses the guard", () => {
  const read = (rel: string) => readFileSync(resolve(__dirname, "..", rel), "utf8");

  test("the two enforcement points both call gitCarrierMatch", () => {
    expect(read("server/sandbox-hook.ts")).toMatch(/gitCarrierMatch\(toolName,/);
    expect(read("server/permission-callback.ts")).toMatch(/gitCarrierMatch\(toolName,/);
  });

  test("every server module that makes a file-tool path decision is one of the two guarded points", () => {
    const { readdirSync } = require("node:fs") as typeof import("node:fs");
    const serverDir = resolve(__dirname, "..", "server");
    const deciders = readdirSync(serverDir)
      .filter((f) => f.endsWith(".ts"))
      .filter((f) => /\bisFileTool\(/.test(readFileSync(join(serverDir, f), "utf8")))
      .filter((f) => f !== "tool-path-checker.ts") // the definition
      .sort();
    expect(deciders).toEqual(["permission-callback.ts", "sandbox-hook.ts"]);
  });

  test("the sandbox hook is attached to the SDK query through createSandboxHook", () => {
    expect(read("server/agent-runner-query-options.ts")).toMatch(/createSandboxHook\(args\.workspacePath\)/);
  });
});
