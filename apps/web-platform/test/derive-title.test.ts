import { describe, it, expect } from "vitest";
import type { Message } from "@/lib/types";
import { deriveTitle } from "@/hooks/use-conversations";

function msg(
  overrides: Partial<Message> & { conversation_id: string; role: Message["role"]; content: string },
): Message {
  return {
    id: "msg-" + Math.random().toString(36).slice(2, 8),
    tool_calls: null,
    leader_id: null,
    created_at: new Date().toISOString(),
    ...overrides,
  };
}

describe("deriveTitle", () => {
  const convId = "conv-1";

  it("returns first user message content", () => {
    const messages: Message[] = [
      msg({ conversation_id: convId, role: "user", content: "Set up Stripe webhooks" }),
    ];
    expect(deriveTitle(messages, convId)).toBe("Set up Stripe webhooks");
  });

  it("strips @-mentions from user message", () => {
    const messages: Message[] = [
      msg({ conversation_id: convId, role: "user", content: "@cto Set up webhooks" }),
    ];
    expect(deriveTitle(messages, convId)).toBe("Set up webhooks");
  });

  it("truncates long titles to 60 chars", () => {
    const long = "A".repeat(80);
    const messages: Message[] = [
      msg({ conversation_id: convId, role: "user", content: long }),
    ];
    const result = deriveTitle(messages, convId);
    expect(result.length).toBeLessThanOrEqual(60);
    expect(result).toBe("A".repeat(57) + "...");
  });

  it("falls back to assistant message when user message is only @-mentions", () => {
    const messages: Message[] = [
      msg({ conversation_id: convId, role: "user", content: "@cto " }),
      msg({ conversation_id: convId, role: "assistant", content: "I'll review the architecture." }),
    ];
    expect(deriveTitle(messages, convId)).toBe("I'll review the architecture.");
  });

  it("falls back to raw @-mention when no assistant message exists", () => {
    const messages: Message[] = [
      msg({ conversation_id: convId, role: "user", content: "@cto" }),
    ];
    expect(deriveTitle(messages, convId)).toBe("@cto");
  });

  it("falls back to domain leader label when no messages exist", () => {
    expect(deriveTitle([], convId, "cto")).toBe("CTO conversation");
  });

  it("falls back to 'Untitled conversation' when no messages and no leader", () => {
    expect(deriveTitle([], convId)).toBe("Untitled conversation");
  });

  it("uses first user message over assistant message when both have content", () => {
    const messages: Message[] = [
      msg({ conversation_id: convId, role: "user", content: "Deploy docs site" }),
      msg({ conversation_id: convId, role: "assistant", content: "Starting deployment..." }),
    ];
    expect(deriveTitle(messages, convId)).toBe("Deploy docs site");
  });

  it("uses assistant message when only assistant messages exist", () => {
    const messages: Message[] = [
      msg({ conversation_id: convId, role: "assistant", content: "Analysis complete." }),
    ];
    expect(deriveTitle(messages, convId)).toBe("Analysis complete.");
  });

  it("filters messages to the given conversation", () => {
    const messages: Message[] = [
      msg({ conversation_id: "other", role: "user", content: "Other conv" }),
      msg({ conversation_id: convId, role: "user", content: "This conv" }),
    ];
    expect(deriveTitle(messages, convId)).toBe("This conv");
  });

  it("truncates assistant message fallback to 60 chars", () => {
    const long = "B".repeat(80);
    const messages: Message[] = [
      msg({ conversation_id: convId, role: "user", content: "@cto " }),
      msg({ conversation_id: convId, role: "assistant", content: long }),
    ];
    const result = deriveTitle(messages, convId);
    expect(result.length).toBeLessThanOrEqual(60);
    expect(result).toBe("B".repeat(57) + "...");
  });
});
