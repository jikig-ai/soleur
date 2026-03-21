/**
 * Agent SDK Spike Test
 *
 * Validates that the Claude Agent SDK works with Soleur agents.
 * Tests: streaming, file tools, plugin loading, canUseTool callback.
 *
 * Run: npx tsx agent-sdk-test.ts
 */

import { query } from "@anthropic-ai/claude-agent-sdk";

const WORKSPACE_PATH = new URL("./test-workspace", import.meta.url).pathname;

// Track what we observe during the query
const observations = {
  messagesReceived: 0,
  partialMessages: 0,
  toolUses: [] as string[],
  canUseToolCalls: [] as string[],
  fileReads: [] as string[],
  errors: [] as string[],
  resultType: "",
  sessionId: "",
  textContent: "",
};

async function runSpike() {
  console.log("=== Agent SDK Spike Test ===\n");
  console.log(`Workspace: ${WORKSPACE_PATH}`);
  console.log(`ANTHROPIC_API_KEY: ${process.env.ANTHROPIC_API_KEY ? "set via env" : "using Claude Code auth"}\n`);

  // Test 1: Basic query with canUseTool callback
  console.log("--- Test 1: Basic query with CMO-like prompt ---\n");

  try {
    const q = query({
      prompt: "Read the file at knowledge-base/project/brainstorms/test-brainstorm.md and summarize the key decisions. Then list all files in the knowledge-base directory.",
      options: {
        cwd: WORKSPACE_PATH,
        model: "claude-sonnet-4-6",
        permissionMode: "default",
        // No allowedTools — rely entirely on canUseTool callback
        includePartialMessages: true,
        persistSession: false,
        maxTurns: 5,
        maxBudgetUsd: 0.50,
        // Test canUseTool callback (the review gate mechanism)
        canUseTool: async (toolName: string, toolInput: Record<string, unknown>) => {
          observations.canUseToolCalls.push(toolName);
          console.log(`  [canUseTool] ${toolName} called with:`, JSON.stringify(toolInput).slice(0, 200));

          // Track file reads
          if (toolName === "Read") {
            const filePath = (toolInput as { file_path?: string }).file_path || "";
            observations.fileReads.push(filePath);
          }

          // Allow everything for this test
          return { allow: true } as const;
        },
        // Try loading Soleur plugin
        plugins: [
          { type: "local" as const, path: `${WORKSPACE_PATH}/plugins/soleur` },
        ],
      },
    });

    for await (const message of q) {
      observations.messagesReceived++;

      if (message.type === "assistant") {
        // Full assistant message
        const content = message.message?.content;
        if (Array.isArray(content)) {
          for (const block of content) {
            if (block.type === "text") {
              observations.textContent += block.text;
              console.log(`  [assistant] ${block.text.slice(0, 200)}${block.text.length > 200 ? "..." : ""}`);
            }
            if (block.type === "tool_use") {
              observations.toolUses.push(block.name);
              console.log(`  [tool_use] ${block.name}`);
            }
          }
        }
      } else if (message.type === "result") {
        observations.resultType = (message as { subtype?: string }).subtype || "unknown";
        observations.sessionId = message.session_id || "";
        console.log(`  [result] type=${observations.resultType} session=${observations.sessionId}`);
      } else if (message.type === "system") {
        const subtype = (message as { subtype?: string }).subtype || "";
        console.log(`  [system] subtype=${subtype}`);
        if (subtype === "init") {
          console.log("  [system] SDK initialized successfully");
        }
      } else {
        // Partial messages or other types
        observations.partialMessages++;
      }
    }
  } catch (error) {
    const errMsg = error instanceof Error ? error.message : String(error);
    observations.errors.push(errMsg);
    console.error(`  [ERROR] ${errMsg}`);
  }

  // Print summary
  console.log("\n=== Spike Results ===\n");
  console.log(`Messages received:    ${observations.messagesReceived}`);
  console.log(`Partial messages:     ${observations.partialMessages}`);
  console.log(`Tool uses:            ${observations.toolUses.join(", ") || "none"}`);
  console.log(`canUseTool calls:     ${observations.canUseToolCalls.join(", ") || "none"}`);
  console.log(`File reads:           ${observations.fileReads.join(", ") || "none"}`);
  console.log(`Result type:          ${observations.resultType}`);
  console.log(`Session ID:           ${observations.sessionId}`);
  console.log(`Errors:               ${observations.errors.join(", ") || "none"}`);
  console.log(`Text content length:  ${observations.textContent.length} chars`);

  // Pass/fail assessment
  console.log("\n=== Pass/Fail Assessment ===\n");

  const checks = [
    { name: "SDK initialized", pass: observations.messagesReceived > 0 },
    { name: "Agent responded with text", pass: observations.textContent.length > 0 },
    { name: "canUseTool callback fired", pass: observations.canUseToolCalls.length > 0 },
    { name: "File tools worked", pass: observations.fileReads.length > 0 || observations.toolUses.includes("Read") || observations.toolUses.includes("Glob") },
    { name: "No critical errors", pass: observations.errors.length === 0 },
    { name: "Got result message", pass: observations.resultType !== "" },
  ];

  let allPass = true;
  for (const check of checks) {
    const icon = check.pass ? "PASS" : "FAIL";
    console.log(`  [${icon}] ${check.name}`);
    if (!check.pass) allPass = false;
  }

  console.log(`\nOverall: ${allPass ? "PASS - Agent SDK works with Soleur" : "FAIL - See details above"}`);

  return allPass;
}

runSpike()
  .then((pass) => process.exit(pass ? 0 : 1))
  .catch((err) => {
    console.error("Unhandled error:", err);
    process.exit(1);
  });
