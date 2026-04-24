import { describe, it, expect, vi } from "vitest";

import {
  PRE_DISPATCH_NARRATION_DIRECTIVE,
  buildSoleurGoSystemPrompt,
  createSoleurGoRunner,
  type QueryFactory,
} from "@/server/soleur-go-runner";

// RED test for Stage 2.23 of plan 2026-04-23-feat-cc-route-via-soleur-go-plan.md.
//
// Pre-dispatch narration is load-bearing for perceived latency: without a
// one-line "Routing to <skill>…" text block before the Skill tool_use,
// users see 5-6s of silence (see plan RERUN §"Perceived-latency derivation").
// The runner's systemPrompt MUST instruct the model to emit that text
// block BEFORE invoking the Skill tool.
//
// Invariants under test:
//   (a) `PRE_DISPATCH_NARRATION_DIRECTIVE` is a non-empty exported string.
//   (b) `buildSoleurGoSystemPrompt()` includes the directive verbatim.
//   (c) The directive names the Skill tool and mandates a text block
//       BEFORE the tool_use (the literal contract the test is pinning).
//   (d) The runner passes a systemPrompt containing the directive to
//       the injected QueryFactory (integration with dispatch).

describe("soleur-go-runner pre-dispatch narration (Stage 2.23)", () => {
  it("exports a non-empty PRE_DISPATCH_NARRATION_DIRECTIVE string", () => {
    expect(typeof PRE_DISPATCH_NARRATION_DIRECTIVE).toBe("string");
    expect(PRE_DISPATCH_NARRATION_DIRECTIVE.length).toBeGreaterThan(50);
  });

  it("directive references the Skill tool and mandates a text block before invoking it", () => {
    // Literal-string contract — any rewording must still retain these
    // anchors so downstream grep-based audits remain stable.
    expect(PRE_DISPATCH_NARRATION_DIRECTIVE).toContain("Skill tool");
    expect(PRE_DISPATCH_NARRATION_DIRECTIVE).toMatch(/before invoking/i);
    expect(PRE_DISPATCH_NARRATION_DIRECTIVE).toMatch(/one-line text block/i);
  });

  it("directive gives a concrete routing example so the model's first content block is text, not tool_use", () => {
    // The RERUN analysis showed the example phrasing is load-bearing —
    // without it, the model frequently skips the narration and calls
    // Skill directly. Pin the example so a future edit doesn't drop it.
    expect(PRE_DISPATCH_NARRATION_DIRECTIVE).toContain("Routing to");
  });

  it("buildSoleurGoSystemPrompt() embeds the narration directive", () => {
    const prompt = buildSoleurGoSystemPrompt();
    expect(prompt).toContain(PRE_DISPATCH_NARRATION_DIRECTIVE);
  });

  it("dispatch passes a systemPrompt containing the narration directive to the QueryFactory", async () => {
    const captured: string[] = [];
    const factory: QueryFactory = (args) => {
      captured.push(args.systemPrompt);
      // Return a closed-immediately Query stub (iteration won't be tested here).
      const iter: AsyncGenerator<never, void> = {
        async next() {
          return { value: undefined, done: true };
        },
        async return() {
          return { value: undefined, done: true };
        },
        async throw(e) {
          throw e;
        },
        async [Symbol.asyncDispose]() {},
        [Symbol.asyncIterator]() {
          return iter;
        },
      };
      // biome-ignore lint/suspicious/noExplicitAny: test stub
      return {
        ...(iter as any),
        close: vi.fn(),
        interrupt: vi.fn(),
        setPermissionMode: vi.fn(),
        setModel: vi.fn(),
        setMaxThinkingTokens: vi.fn(),
        applyFlagSettings: vi.fn(),
        initializationResult: vi.fn(async () => ({}) as any),
        supportedCommands: vi.fn(async () => []),
        supportedModels: vi.fn(async () => []),
        streamInput: vi.fn(),
        stopTask: vi.fn(),
      } as any;
    };

    const runner = createSoleurGoRunner({
      queryFactory: factory,
      now: () => Date.now(),
    });
    await runner.dispatch({
      conversationId: "c-narr",
      userId: "u1",
      userMessage: "hi",
      currentRouting: { kind: "soleur_go_pending" },
      events: {
        onText: vi.fn(),
        onToolUse: vi.fn(),
        onWorkflowDetected: vi.fn(),
        onWorkflowEnded: vi.fn(),
        onResult: vi.fn(),
      },
      persistActiveWorkflow: vi.fn().mockResolvedValue(undefined),
    });

    expect(captured).toHaveLength(1);
    expect(captured[0]).toContain(PRE_DISPATCH_NARRATION_DIRECTIVE);
  });
});
