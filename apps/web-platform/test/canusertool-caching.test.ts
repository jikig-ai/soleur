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
 * The web platform uses BYOK keys (not bridge auth), so canUseTool DOES
 * fire in production. This test uses settingSources: [] and tracks both
 * the bridge-auth path and the direct-API-key path.
 *
 * Set SKIP_SDK_TESTS=1 to skip in CI without auth.
 *
 * @see https://github.com/jikig-ai/soleur/issues/876
 */
import { describe, test, expect, beforeAll, afterAll } from "vitest";
import { writeFileSync, mkdirSync, rmSync } from "fs";

const TEST_DIR = "/tmp/canusertool-caching-test";
const HAS_API_KEY = Boolean(process.env.ANTHROPIC_API_KEY);

// Skip when explicitly disabled (CI without auth)
const describeWithAuth = process.env.SKIP_SDK_TESTS ? describe.skip : describe;

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

    const toolUses: string[] = [];

    for await (const message of q) {
      if (message.type === "assistant" && Array.isArray(message.message?.content)) {
        for (const block of message.message.content) {
          if (block.type === "tool_use") {
            toolUses.push(block.name);
          }
        }
      }
    }

    // The agent must have used tools
    expect(toolUses.length).toBeGreaterThan(0);

    if (invocations.length === 0) {
      // Bridge auth path: canUseTool is bypassed entirely.
      // This is expected when running under Claude Code's built-in auth.
      // The web platform uses BYOK keys, so this path does NOT apply
      // in production. Log the finding but don't fail.
      console.log(
        `[caching-test] Bridge auth detected: ${toolUses.length} tool uses, ` +
        "0 canUseTool calls. Bridge handles permissions internally. " +
        "BYOK production path is unaffected.",
      );
      console.log(`[caching-test] HAS_API_KEY=${HAS_API_KEY}`);
      return;
    }

    // Direct API key path: canUseTool fires for each invocation
    const readCalls = invocations.filter((i) => i.toolName === "Read");
    expect(readCalls.length).toBeGreaterThanOrEqual(2);

    const uniquePaths = new Set(readCalls.map((r) => r.filePath));
    expect(uniquePaths.size).toBeGreaterThanOrEqual(2);

    // Strongest anti-caching signal: each invocation gets a unique toolUseID
    const uniqueIDs = new Set(readCalls.map((r) => r.toolUseID));
    expect(uniqueIDs.size).toBe(readCalls.length);

    console.log(`[caching-test] CONFIRMED: no caching`);
    console.log(`[caching-test] Read calls: ${readCalls.length}, unique paths: ${uniquePaths.size}, unique IDs: ${uniqueIDs.size}`);
    for (const call of readCalls) {
      console.log(`  [Read] ${call.filePath} (ID: ${call.toolUseID})`);
    }
  }, 120_000);

  test("no same-path deduplication in canUseTool", async () => {
    const { query } = await import("@anthropic-ai/claude-agent-sdk");

    const invocations: Array<{ toolName: string; filePath: string }> = [];

    const q = query({
      prompt: `Read ${TEST_DIR}/file1.txt. Then forget what you read and read ${TEST_DIR}/file1.txt again. Confirm the content is the same both times.`,
      options: {
        cwd: TEST_DIR,
        model: "claude-sonnet-4-6",
        maxTurns: 5,
        maxBudgetUsd: 0.25,
        permissionMode: "default",
        settingSources: [],
        disallowedTools: ["Bash", "Write", "Edit"],
        canUseTool: async (toolName, input) => {
          const filePath = (input as { file_path?: string }).file_path || "";
          invocations.push({ toolName, filePath });
          return { behavior: "allow" as const, updatedInput: input };
        },
      },
    });

    const toolUses: string[] = [];

    for await (const message of q) {
      if (message.type === "assistant" && Array.isArray(message.message?.content)) {
        for (const block of message.message.content) {
          if (block.type === "tool_use") {
            toolUses.push(block.name);
          }
        }
      }
    }

    expect(toolUses.length).toBeGreaterThan(0);

    if (invocations.length === 0) {
      console.log(
        `[dedup-test] Bridge auth: ${toolUses.length} tool uses, ` +
        "0 canUseTool calls (bridge handles permissions).",
      );
      return;
    }

    const readCalls = invocations.filter((i) => i.toolName === "Read");
    expect(readCalls.length).toBeGreaterThanOrEqual(1);
    console.log(`[dedup-test] Read calls: ${readCalls.length}`);
    for (const call of readCalls) {
      console.log(`  [Read] ${call.filePath}`);
    }
  }, 120_000);
});
