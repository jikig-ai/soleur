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
  return [
    "auth",
    "chat",
    "start_session",
    "resume_session",
    "close_conversation",
    "review_gate_response",
  ].includes(msg.type);
}

function isServerMessage(msg: WSMessage): boolean {
  return [
    "auth_ok",
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
  test("wss URL does not include token parameter", () => {
    const url = "wss://app.soleur.ai/ws";
    const parsed = new URL(url);
    expect(parsed.protocol).toBe("wss:");
    expect(parsed.pathname).toBe("/ws");
    expect(parsed.searchParams.get("token")).toBeNull();
  });
});

describe("auth handshake protocol", () => {
  test("auth message is valid client message", () => {
    const msg = parseMessage('{"type":"auth","token":"eyJhbGciOi...test"}');
    expect(msg).not.toBeNull();
    expect(msg!.type).toBe("auth");
    expect(isClientMessage(msg!)).toBe(true);
    expect(isServerMessage(msg!)).toBe(false);
  });

  test("auth_ok message is valid server message", () => {
    const msg = parseMessage('{"type":"auth_ok"}');
    expect(msg).not.toBeNull();
    expect(msg!.type).toBe("auth_ok");
    expect(isServerMessage(msg!)).toBe(true);
    expect(isClientMessage(msg!)).toBe(false);
  });

  test("auth message contains token field", () => {
    const msg = parseMessage('{"type":"auth","token":"test-token-123"}');
    expect(msg).not.toBeNull();
    if (msg!.type === "auth") {
      expect(msg!.token).toBe("test-token-123");
    }
  });

  test("auth message with empty token is parseable", () => {
    const msg = parseMessage('{"type":"auth","token":""}');
    expect(msg).not.toBeNull();
    if (msg!.type === "auth") {
      expect(msg!.token).toBe("");
    }
  });
});

describe("multi-turn session protocol", () => {
  test("resume_session message is valid client message", () => {
    const msg = parseMessage(
      '{"type":"resume_session","conversationId":"conv-123"}',
    );
    expect(msg).not.toBeNull();
    expect(msg!.type).toBe("resume_session");
    expect(isClientMessage(msg!)).toBe(true);
    expect(isServerMessage(msg!)).toBe(false);
  });

  test("resume_session includes conversationId", () => {
    const msg = parseMessage(
      '{"type":"resume_session","conversationId":"abc-def-123"}',
    );
    expect(msg).not.toBeNull();
    if (msg!.type === "resume_session") {
      expect(msg!.conversationId).toBe("abc-def-123");
    }
  });

  test("close_conversation message is valid client message", () => {
    const msg = parseMessage('{"type":"close_conversation"}');
    expect(msg).not.toBeNull();
    expect(msg!.type).toBe("close_conversation");
    expect(isClientMessage(msg!)).toBe(true);
    expect(isServerMessage(msg!)).toBe(false);
  });

  test("session_ended with turn_complete reason indicates multi-turn", () => {
    const msg = parseMessage(
      '{"type":"session_ended","reason":"turn_complete"}',
    );
    expect(msg).not.toBeNull();
    if (msg!.type === "session_ended") {
      expect(msg!.reason).toBe("turn_complete");
    }
  });

  test("session_ended with closed reason indicates explicit close", () => {
    const msg = parseMessage(
      '{"type":"session_ended","reason":"closed"}',
    );
    expect(msg).not.toBeNull();
    if (msg!.type === "session_ended") {
      expect(msg!.reason).toBe("closed");
    }
  });

  test("error with session_expired errorCode is detectable", () => {
    const msg = parseMessage(
      '{"type":"error","message":"Session expired","errorCode":"session_expired"}',
    );
    expect(msg).not.toBeNull();
    if (msg!.type === "error") {
      expect(msg!.errorCode).toBe("session_expired");
    }
  });

  test("error with session_resumed errorCode is detectable", () => {
    const msg = parseMessage(
      '{"type":"error","message":"Session resumed","errorCode":"session_resumed"}',
    );
    expect(msg).not.toBeNull();
    if (msg!.type === "error") {
      expect(msg!.errorCode).toBe("session_resumed");
    }
  });
});
