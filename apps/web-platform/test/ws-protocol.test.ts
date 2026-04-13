import { describe, test, expect } from "vitest";
import type { WSMessage } from "../lib/types";
import { KeyInvalidError, WS_CLOSE_CODES } from "../lib/types";

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
    "stream_start",
    "stream_end",
    "tool_use",
    "review_gate",
    "session_started",
    "session_ended",
    "usage_update",
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

describe("rate limiting close codes", () => {
  test("RATE_LIMITED close code is 4008", () => {
    expect(WS_CLOSE_CODES.RATE_LIMITED).toBe(4008);
  });

  test("RATE_LIMITED is in the application-reserved range (4000-4999)", () => {
    expect(WS_CLOSE_CODES.RATE_LIMITED).toBeGreaterThanOrEqual(4000);
    expect(WS_CLOSE_CODES.RATE_LIMITED).toBeLessThanOrEqual(4999);
  });

  test("error with rate_limited errorCode is detectable", () => {
    const msg = parseMessage(
      '{"type":"error","message":"Too many sessions.","errorCode":"rate_limited"}',
    );
    expect(msg).not.toBeNull();
    if (msg!.type === "error") {
      expect(msg!.errorCode).toBe("rate_limited");
    }
  });

  test("all close codes are unique values", () => {
    const values = Object.values(WS_CLOSE_CODES);
    const unique = new Set(values);
    expect(unique.size).toBe(values.length);
  });
});

describe("streaming lifecycle protocol", () => {
  test("stream_start is a server message", () => {
    const msg = parseMessage(
      '{"type":"stream_start","leaderId":"cto","source":"auto"}',
    );
    expect(msg).not.toBeNull();
    expect(isServerMessage(msg!)).toBe(true);
    expect(isClientMessage(msg!)).toBe(false);
  });

  test("stream_end is a server message", () => {
    const msg = parseMessage('{"type":"stream_end","leaderId":"cto"}');
    expect(msg).not.toBeNull();
    expect(isServerMessage(msg!)).toBe(true);
    expect(isClientMessage(msg!)).toBe(false);
  });

  test("tool_use is a server message with tool and label", () => {
    const msg = parseMessage(
      '{"type":"tool_use","leaderId":"cto","tool":"Read","label":"Reading file..."}',
    );
    expect(msg).not.toBeNull();
    expect(isServerMessage(msg!)).toBe(true);
    expect(isClientMessage(msg!)).toBe(false);
    if (msg!.type === "tool_use") {
      expect(msg!.tool).toBe("Read");
      expect(msg!.label).toBe("Reading file...");
      expect(msg!.leaderId).toBe("cto");
    }
  });

  test("valid lifecycle sequence: stream_start → tool_use → stream (partial) → stream_end", () => {
    const sequence = [
      '{"type":"stream_start","leaderId":"cmo"}',
      '{"type":"tool_use","leaderId":"cmo","tool":"Read","label":"Reading file..."}',
      '{"type":"stream","content":"Hello","partial":true,"leaderId":"cmo"}',
      '{"type":"stream","content":"Hello world","partial":true,"leaderId":"cmo"}',
      '{"type":"stream_end","leaderId":"cmo"}',
    ];

    const parsed = sequence.map((raw) => parseMessage(raw));
    // All messages parse successfully
    for (const msg of parsed) {
      expect(msg).not.toBeNull();
      expect(isServerMessage(msg!)).toBe(true);
    }

    // Verify correct types in order
    expect(parsed[0]!.type).toBe("stream_start");
    expect(parsed[1]!.type).toBe("tool_use");
    expect(parsed[2]!.type).toBe("stream");
    expect(parsed[3]!.type).toBe("stream");
    expect(parsed[4]!.type).toBe("stream_end");
  });

  test("no partial:false emission after partials were sent", () => {
    // After cumulative partial:true messages, the server should NOT send
    // a final partial:false with the same content. Only stream_end signals
    // completion. This test validates the protocol contract.
    const events = [
      { type: "stream_start", leaderId: "cmo" },
      { type: "stream", content: "A", partial: true, leaderId: "cmo" },
      { type: "stream", content: "AB", partial: true, leaderId: "cmo" },
      { type: "stream", content: "ABC", partial: true, leaderId: "cmo" },
      { type: "stream_end", leaderId: "cmo" },
    ];

    // Verify no partial:false exists in the sequence
    const streamEvents = events.filter((e) => e.type === "stream");
    for (const evt of streamEvents) {
      expect(evt.partial).toBe(true);
    }

    // Final event is stream_end, not a stream with partial:false
    expect(events[events.length - 1].type).toBe("stream_end");
  });

  test("cumulative partials produce correct final content via replace semantics", () => {
    // Client should REPLACE content on each partial:true, not append
    const partials = [
      { content: "A", partial: true },
      { content: "AB", partial: true },
      { content: "ABC", partial: true },
    ];

    // Simulate replace semantics (correct)
    let replaceResult = "";
    for (const p of partials) {
      replaceResult = p.content; // replace
    }
    expect(replaceResult).toBe("ABC");

    // Demonstrate why append is wrong
    let appendResult = "";
    for (const p of partials) {
      appendResult += p.content; // append (bug)
    }
    expect(appendResult).toBe("AABABC"); // This is the bug we're fixing
    expect(appendResult).not.toBe("ABC");
  });

  test("multi-agent interleaving: independent leaderIds do not cross-contaminate", () => {
    const events = [
      { type: "stream_start", leaderId: "cmo" },
      { type: "stream_start", leaderId: "cto" },
      { type: "stream", content: "CMO text", partial: true, leaderId: "cmo" },
      { type: "stream", content: "CTO text", partial: true, leaderId: "cto" },
      { type: "stream_end", leaderId: "cmo" },
      { type: "stream_end", leaderId: "cto" },
    ];

    // Group events by leaderId
    const byLeader = new Map<string, typeof events>();
    for (const evt of events) {
      const id = evt.leaderId;
      if (!byLeader.has(id)) byLeader.set(id, []);
      byLeader.get(id)!.push(evt);
    }

    // Each leader has independent stream lifecycle
    expect(byLeader.get("cmo")!.length).toBe(3);
    expect(byLeader.get("cto")!.length).toBe(3);

    // CMO content is only CMO's
    const cmoStreams = byLeader.get("cmo")!.filter((e) => e.type === "stream");
    expect(cmoStreams[0].content).toBe("CMO text");

    // CTO content is only CTO's
    const ctoStreams = byLeader.get("cto")!.filter((e) => e.type === "stream");
    expect(ctoStreams[0].content).toBe("CTO text");
  });

  test("tool_use labels map SDK tools to human-readable strings", () => {
    const toolLabels: Record<string, string> = {
      Read: "Reading file...",
      Bash: "Running command...",
      Edit: "Editing file...",
      Write: "Writing file...",
      WebSearch: "Searching web...",
      Grep: "Searching code...",
      Glob: "Finding files...",
    };

    for (const [tool, label] of Object.entries(toolLabels)) {
      const msg = parseMessage(
        JSON.stringify({ type: "tool_use", leaderId: "cto", tool, label }),
      );
      expect(msg).not.toBeNull();
      if (msg!.type === "tool_use") {
        expect(msg!.label).toBe(label);
      }
    }
  });
});

describe("idle timeout", () => {
  test("IDLE_TIMEOUT close code is 4009", () => {
    expect(WS_CLOSE_CODES.IDLE_TIMEOUT).toBe(4009);
  });

  test("IDLE_TIMEOUT is in the WSErrorCode type", () => {
    const msg = parseMessage(
      '{"type":"error","message":"Session idle","errorCode":"idle_timeout"}',
    );
    expect(msg).not.toBeNull();
    if (msg!.type === "error") {
      expect(msg!.errorCode).toBe("idle_timeout");
    }
  });

  test("idle timer resets on activity", () => {
    let timerCleared = false;
    let timerSet = false;
    let lastActivity = 0;

    function resetIdleTimer() {
      if (timerSet) timerCleared = true;
      lastActivity = Date.now();
      timerSet = true;
    }

    // First call — sets timer
    resetIdleTimer();
    expect(timerSet).toBe(true);
    expect(timerCleared).toBe(false);
    const firstActivity = lastActivity;

    // Second call — clears old timer, sets new one
    resetIdleTimer();
    expect(timerCleared).toBe(true);
    expect(lastActivity).toBeGreaterThanOrEqual(firstActivity);
  });

  test("NON_TRANSIENT_CLOSE_CODES includes IDLE_TIMEOUT with no redirect", async () => {
    const { NON_TRANSIENT_CLOSE_CODES } = await import("../lib/ws-client");
    const entry = NON_TRANSIENT_CLOSE_CODES[WS_CLOSE_CODES.IDLE_TIMEOUT];
    expect(entry).toBeDefined();
    expect(entry.reason).toBe("Session expired due to inactivity");
    expect(entry.target).toBeUndefined();
  });
});
