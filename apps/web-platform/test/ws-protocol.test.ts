import { describe, test, expect } from "vitest";
import type { WSMessage } from "../lib/types";
import { KeyInvalidError } from "../lib/types";

// Test the WebSocket message protocol types and routing logic.
// The actual WebSocket server requires HTTP infrastructure, so we test
// the message parsing and validation logic in isolation.

function parseMessage(raw: string): WSMessage | null {
  try {
    return JSON.parse(raw) as WSMessage;
  } catch {
    return null;
  }
}

function isClientMessage(msg: WSMessage): boolean {
  return ["chat", "start_session", "review_gate_response"].includes(msg.type);
}

function isServerMessage(msg: WSMessage): boolean {
  return [
    "stream",
    "review_gate",
    "session_started",
    "session_ended",
    "error",
  ].includes(msg.type);
}

describe("WebSocket protocol", () => {
  test("start_session message is valid client message", () => {
    const msg = parseMessage(
      '{"type":"start_session","leaderId":"cmo"}',
    );
    expect(msg).not.toBeNull();
    expect(msg!.type).toBe("start_session");
    expect(isClientMessage(msg!)).toBe(true);
    expect(isServerMessage(msg!)).toBe(false);
  });

  test("chat message is valid client message", () => {
    const msg = parseMessage('{"type":"chat","content":"hello"}');
    expect(msg).not.toBeNull();
    expect(isClientMessage(msg!)).toBe(true);
  });

  test("stream message is server-only", () => {
    const msg = parseMessage(
      '{"type":"stream","content":"hello","partial":true}',
    );
    expect(msg).not.toBeNull();
    expect(isServerMessage(msg!)).toBe(true);
    expect(isClientMessage(msg!)).toBe(false);
  });

  test("session_started includes conversationId", () => {
    const msg = parseMessage(
      '{"type":"session_started","conversationId":"abc-123"}',
    );
    expect(msg).not.toBeNull();
    if (msg!.type === "session_started") {
      expect(msg!.conversationId).toBe("abc-123");
    }
  });

  test("invalid JSON returns null", () => {
    expect(parseMessage("not json")).toBeNull();
    expect(parseMessage("")).toBeNull();
  });

  test("review_gate_response includes gateId and selection", () => {
    const msg = parseMessage(
      '{"type":"review_gate_response","gateId":"g1","selection":"Approve"}',
    );
    expect(msg).not.toBeNull();
    if (msg!.type === "review_gate_response") {
      expect(msg!.gateId).toBe("g1");
      expect(msg!.selection).toBe("Approve");
    }
  });

  test("all 8 domain leaders are valid leaderId values", () => {
    const leaders = ["cmo", "cto", "cfo", "cpo", "cro", "coo", "clo", "cco"];
    for (const id of leaders) {
      const msg = parseMessage(`{"type":"start_session","leaderId":"${id}"}`);
      expect(msg).not.toBeNull();
      if (msg!.type === "start_session") {
        expect(msg!.leaderId).toBe(id);
      }
    }
  });
});

describe("key invalidation error handling", () => {
  test("error message with errorCode key_invalid is detectable", () => {
    const msg = parseMessage(
      '{"type":"error","message":"No valid API key found.","errorCode":"key_invalid"}',
    );
    expect(msg).not.toBeNull();
    expect(msg!.type).toBe("error");
    if (msg!.type === "error") {
      expect(msg!.errorCode).toBe("key_invalid");
    }
  });

  test("error message without errorCode has undefined errorCode", () => {
    const msg = parseMessage('{"type":"error","message":"Something went wrong"}');
    expect(msg).not.toBeNull();
    expect(msg!.type).toBe("error");
    if (msg!.type === "error") {
      expect(msg!.errorCode).toBeUndefined();
    }
  });

  test("KeyInvalidError is instanceof Error and detectable", () => {
    const keyErr = new KeyInvalidError();
    const otherErr = new Error("Workspace not provisioned");

    expect(keyErr).toBeInstanceOf(Error);
    expect(keyErr).toBeInstanceOf(KeyInvalidError);
    expect(otherErr).not.toBeInstanceOf(KeyInvalidError);
    expect(keyErr.message).toContain("No valid API key");
  });
});

describe("WebSocket URL construction", () => {
  test("wss URL includes token parameter", () => {
    const token = "eyJhbGciOi...test";
    const url = `wss://app.soleur.ai/ws?token=${token}`;
    const parsed = new URL(url);
    expect(parsed.protocol).toBe("wss:");
    expect(parsed.pathname).toBe("/ws");
    expect(parsed.searchParams.get("token")).toBe(token);
  });

  test("URL without token has empty token param", () => {
    const url = "wss://app.soleur.ai/ws?token=";
    const parsed = new URL(url);
    expect(parsed.searchParams.get("token")).toBe("");
  });
});
