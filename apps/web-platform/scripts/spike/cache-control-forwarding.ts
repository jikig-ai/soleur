// S1 spike for #3436: verify the agent SDK's `query()` forwards a
// user-supplied `cache_control: { type: "ephemeral" }` marker on a content
// block end-to-end to Anthropic's prompt-caching subsystem.
//
// Gates the `cache_control` attachment in Phase 3 of
// `2026-05-07-feat-chapter-chunking-pdf-resolver-plan.md`. Outcome edits
// AC #4 — keep ONLY the matching GREEN-S1 / RED-S1 branch.
//
// Probe: send the SAME large user message TWICE within the 5-minute cache
// TTL. On the first run, expect `usage.cache_creation_input_tokens > 0`
// (cache write). On the second run within TTL, expect
// `usage.cache_read_input_tokens > 0` (cache hit). If neither fires, the
// SDK is not forwarding the marker — RED-S1; ship without `cache_control`.
//
// Operator command:
//   doppler run -p soleur -c dev -- ./node_modules/.bin/tsx \
//     scripts/spike/cache-control-forwarding.ts
//
// Cost ceiling: ~$0.01-0.05 (one large input, two times). Document the
// emitted token counts verbatim in the PR body per AC #12.

import { query } from "@anthropic-ai/claude-agent-sdk";
import type {
  SDKUserMessage,
  SDKResultMessage,
} from "@anthropic-ai/claude-agent-sdk";

// Anthropic's prompt-cache eligibility threshold is ~1024 tokens for Sonnet.
// 8 KB of stable text is comfortably above that for ASCII-dense content.
const CACHE_ELIGIBLE_TEXT = ("Soleur cache-control forwarding spike. ".repeat(
  220,
) +
  "\n" +
  Array.from({ length: 200 }, (_, i) => `Line ${i}: stable spike content for cache eligibility.`).join("\n")).slice(
  0,
  8 * 1024,
);

async function runProbe(
  attempt: 1 | 2,
): Promise<SDKResultMessage | null> {
  // Stream a single user message carrying a `document` content block with
  // the `cache_control` marker. The agent SDK's `query()` accepts an
  // AsyncIterable<SDKUserMessage> via `prompt`; per the plan we use that
  // shape rather than a bare string so we can attach a `document` block
  // (the same shape Phase 3 will attach for chapter content).
  async function* userStream(): AsyncIterable<SDKUserMessage> {
    yield {
      type: "user",
      parent_tool_use_id: null,
      session_id: `spike-cache-control-${Date.now()}-${attempt}`,
      message: {
        role: "user",
        content: [
          {
            type: "document",
            source: {
              type: "text",
              media_type: "text/plain",
              data: CACHE_ELIGIBLE_TEXT,
            },
            // The hypothesis under test: SDK forwards this marker.
            cache_control: { type: "ephemeral" },
          },
          {
            type: "text",
            text: "Reply with the single word OK.",
          },
        ],
      },
    } as SDKUserMessage;
  }

  let resultMessage: SDKResultMessage | null = null;
  const q = query({
    prompt: userStream(),
    options: {
      // Pin Sonnet 4.6 / 200K to match the chapter-router plan.
      model: "claude-sonnet-4-6",
      // Empty system prompt — minimize cache-prefix invalidation noise.
      systemPrompt: "",
      // Disable tools so the result message arrives in one turn.
      allowedTools: [],
      maxTurns: 1,
    },
  });

  for await (const msg of q) {
    if (msg.type === "result") {
      resultMessage = msg;
    }
  }
  return resultMessage;
}

async function main(): Promise<void> {
  if (!process.env.ANTHROPIC_API_KEY) {
    console.error(
      "ANTHROPIC_API_KEY not set. Run via doppler: doppler run -p soleur -c dev -- ./node_modules/.bin/tsx scripts/spike/cache-control-forwarding.ts",
    );
    process.exit(2);
  }

  console.log(
    "S1: cache_control end-to-end forwarding probe (Sonnet 4.6 / 200K).",
  );
  console.log(
    `Body bytes: ${CACHE_ELIGIBLE_TEXT.length} (≥${(8 * 1024).toLocaleString()} req'd for cache eligibility).\n`,
  );

  const r1 = await runProbe(1);
  if (!r1) {
    console.error("Probe 1 produced no SDKResultMessage. Aborting.");
    process.exit(2);
  }
  const usage1 = r1.usage as Record<string, unknown>;
  console.log("Probe 1 usage:", JSON.stringify(usage1, null, 2));

  // Wait a brief moment so the cache write commits before the read probe.
  await new Promise((resolve) => setTimeout(resolve, 500));

  const r2 = await runProbe(2);
  if (!r2) {
    console.error("Probe 2 produced no SDKResultMessage. Aborting.");
    process.exit(2);
  }
  const usage2 = r2.usage as Record<string, unknown>;
  console.log("\nProbe 2 usage:", JSON.stringify(usage2, null, 2));

  const writeOk = Number(usage1.cache_creation_input_tokens ?? 0) > 0;
  const readOk = Number(usage2.cache_read_input_tokens ?? 0) > 0;

  console.log("\n--- S1 outcome ---");
  console.log(
    `  cache_creation_input_tokens (probe 1): ${usage1.cache_creation_input_tokens ?? 0} (>0 required)`,
  );
  console.log(
    `  cache_read_input_tokens     (probe 2): ${usage2.cache_read_input_tokens ?? 0} (>0 required)`,
  );

  if (writeOk && readOk) {
    console.log(
      "\nGREEN-S1: ship `cache_control` attachment. Keep AC #4 GREEN-S1 branch (10-turn cap).",
    );
    process.exit(0);
  }
  console.log(
    "\nRED-S1: drop `cache_control` for v1. Edit AC #4 to keep RED-S1 branch (5-turn cap). Side-channel via bare @anthropic-ai/sdk is NOT a v1 fallback (per plan).",
  );
  process.exit(1);
}

main().catch((err) => {
  console.error("Spike crashed:", err);
  process.exit(2);
});
