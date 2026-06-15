import { describe, it, expect, vi } from "vitest";
import { z } from "zod/v4";

// feat-reasoning-chat-boxes (#5370) — narrate/summarize are PURE
// validate-and-return tools with a hard length cap at the tool boundary
// (security C-2) and an explicit auto-approve tier.

vi.mock("@anthropic-ai/claude-agent-sdk", () => ({
  tool: vi.fn(
    (name: string, description: string, schema: unknown, handler: unknown) => ({
      name,
      description,
      schema,
      handler,
    }),
  ),
}));

import {
  buildNarrationTools,
  NARRATE_MESSAGE_MAX_CHARS,
  SUMMARIZE_SUMMARY_MAX_CHARS,
  NARRATE_TOOL_FQN,
  SUMMARIZE_TOOL_FQN,
} from "@/server/narrate-tool";
import { getToolTier } from "@/server/tool-tiers";

type ToolStub = {
  name: string;
  schema: Record<string, z.ZodType>;
  handler: (args: Record<string, unknown>) => Promise<{ isError?: true }>;
};

function tools() {
  return buildNarrationTools({ userId: "u1" }) as unknown as ToolStub[];
}

describe("buildNarrationTools — factory", () => {
  it("returns exactly narrate + summarize", () => {
    expect(tools().map((t) => t.name).sort()).toEqual(["narrate", "summarize"]);
  });

  it("handlers are pure: return an ok ack, never an error", async () => {
    for (const t of tools()) {
      const field = t.name === "narrate" ? "message" : "summary";
      const res = await t.handler({ [field]: "hello" });
      expect(res.isError).toBeUndefined();
    }
  });
});

describe("length cap at the tool boundary (security C-2)", () => {
  it("narrate.message rejects over the char cap and accepts within it", () => {
    const schema = tools().find((t) => t.name === "narrate")!.schema.message;
    expect(schema.safeParse("x".repeat(NARRATE_MESSAGE_MAX_CHARS)).success).toBe(true);
    expect(schema.safeParse("x".repeat(NARRATE_MESSAGE_MAX_CHARS + 1)).success).toBe(false);
    expect(schema.safeParse("").success).toBe(false); // min(1)
  });

  it("summarize.summary rejects over the char cap and accepts within it", () => {
    const schema = tools().find((t) => t.name === "summarize")!.schema.summary;
    expect(schema.safeParse("x".repeat(SUMMARIZE_SUMMARY_MAX_CHARS)).success).toBe(true);
    expect(schema.safeParse("x".repeat(SUMMARIZE_SUMMARY_MAX_CHARS + 1)).success).toBe(false);
  });
});

describe("explicit auto-approve tier", () => {
  it("narrate + summarize are auto-approve (NOT the gated fail-closed default)", () => {
    expect(getToolTier(NARRATE_TOOL_FQN)).toBe("auto-approve");
    expect(getToolTier(SUMMARIZE_TOOL_FQN)).toBe("auto-approve");
  });
});
