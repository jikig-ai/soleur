/**
 * canUseTool Caching Verification Test (#876)
 *
 * Verifies that the Agent SDK does NOT cache canUseTool permission decisions
 * per tool name. The spike (spike/FINDINGS.md) observed "only 1 callback
 * invocation despite 5 tool uses," which investigation traced to two
 * independent root causes — neither of which is SDK-level caching:
 *
 * 1. Pre-approved tools in .claude/settings.json bypass canUseTool entirely
 *    (permission chain step 4 before step 5)
 * 2. Under Claude Code's bridge auth, the bridge handles ALL permissions
 *    internally and never invokes the canUseTool callback
 *
 * This test requires ANTHROPIC_API_KEY to run. Under bridge auth (no explicit
 * API key), the canUseTool callback is never invoked regardless of caching
 * behavior, making the test unable to verify its claim.
 *
 * @see https://github.com/jikig-ai/soleur/issues/876
 */
import { describe, test, expect, beforeAll, afterAll } from "vitest";
import { writeFileSync, mkdirSync, rmSync } from "fs";

const TEST_DIR = "/tmp/canusertool-caching-test";
const HAS_API_KEY = Boolean(process.env.ANTHROPIC_API_KEY);

// Skip when no API key (bridge auth cannot verify canUseTool behavior)
// or when explicitly disabled via SKIP_SDK_TESTS=1
const describeWithAuth =
  !HAS_API_KEY || process.env.SKIP_SDK_TESTS ? describe.skip : describe;

describeWithAuth("canUseTool caching behavior (#876)", () => {
  beforeAll(() => {
    mkdirSync(TEST_DIR, { recursive: true });
    writeFileSync(`${TEST_DIR}/file1.txt`, "Content of file 1: alpha");
    writeFileSync(`${TEST_DIR}/file2.txt`, "Content of file 2: bravo");
    writeFileSync(`${TEST_DIR}/file3.txt`, "Content of file 3: charlie");
  });

  afterAll(() => {
    rmSync(TEST_DIR, { recursive: true, force: true });
  });

  test("canUseTool fires per-invocation, not per-tool-name", async () => {
    const { query } = await import("@anthropic-ai/claude-agent-sdk");

    const invocations: Array<{
      toolName: string;
      filePath: string;
      toolUseID: string;
    }> = [];

    const q = query({
      prompt: `Read all three files in ${TEST_DIR}: file1.txt, file2.txt, and file3.txt. Report their contents.`,
      options: {
        cwd: TEST_DIR,
        model: "claude-sonnet-4-6",
        maxTurns: 5,
        maxBudgetUsd: 0.25,
        permissionMode: "default",
        settingSources: [],
        disallowedTools: ["Bash", "Write", "Edit"],
        canUseTool: async (toolName, input, options) => {
          const filePath = (input as { file_path?: string }).file_path || "";
          invocations.push({
            toolName,
            filePath,
            toolUseID: options.toolUseID,
          });
          return { behavior: "allow" as const, updatedInput: input };
        },
      },
    });

    for await (const _message of q) {
      // Consume stream to completion
    }

    // canUseTool must have been called (not bypassed)
    expect(invocations.length).toBeGreaterThan(0);

    // Verify callback fired for each Read invocation
    const readCalls = invocations.filter((i) => i.toolName === "Read");
    expect(readCalls.length).toBeGreaterThanOrEqual(2);

    // Verify different file paths triggered separate callbacks
    const uniquePaths = new Set(readCalls.map((r) => r.filePath));
    expect(uniquePaths.size).toBeGreaterThanOrEqual(2);

    // Strongest anti-caching signal: each invocation gets a unique toolUseID
    const uniqueIDs = new Set(readCalls.map((r) => r.toolUseID));
    expect(uniqueIDs.size).toBe(readCalls.length);
  }, 120_000);
});
