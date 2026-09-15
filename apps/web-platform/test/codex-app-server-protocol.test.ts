import { describe, expect, it } from "vitest";
import {
  createCodexApprovalResponseRequest,
  createCodexInitializeRequest,
  createCodexInitializedNotification,
  createCodexThreadResumeRequest,
  createCodexThreadReadRequest,
  createCodexThreadStartRequest,
  createCodexTurnInterruptRequest,
  createCodexTurnStartRequest,
} from "@/server/codex-app-server-protocol";
import {
  decodeCodexJsonlLine,
  decodeCodexJsonlStream,
  encodeCodexJsonl,
} from "@/server/codex-app-server-jsonl";

describe("Codex App Server protocol requests", () => {
  it("constructs the initialize handshake without credential material", () => {
    expect(createCodexInitializeRequest("rpc-1")).toEqual({
      jsonrpc: "2.0",
      id: "rpc-1",
      method: "initialize",
      params: { clientInfo: { name: "soleur-web", version: "1" } },
    });
    expect(createCodexInitializeRequest("rpc-1")).not.toHaveProperty("params.accessToken");
  });

  it("constructs the initialized notification", () => {
    expect(createCodexInitializedNotification()).toEqual({
      jsonrpc: "2.0",
      method: "initialized",
      params: {},
    });
  });

  it("keeps thread start and resume as distinct operations", () => {
    expect(createCodexThreadStartRequest("rpc-2", { cwd: "/workspaces/ws-1" })).toEqual({
      jsonrpc: "2.0",
      id: "rpc-2",
      method: "thread/start",
      params: { cwd: "/workspaces/ws-1" },
    });
    expect(createCodexThreadResumeRequest("rpc-3", "thread-1")).toEqual({
      jsonrpc: "2.0",
      id: "rpc-3",
      method: "thread/resume",
      params: { threadId: "thread-1" },
    });
  });

  it("starts a turn and encodes approval responses as JSON-RPC results", () => {
    expect(createCodexTurnStartRequest("rpc-4", "thread-1", "Review the change")).toEqual({
      jsonrpc: "2.0",
      id: "rpc-4",
      method: "turn/start",
      params: { threadId: "thread-1", input: [{ type: "text", text: "Review the change" }] },
    });
    expect(createCodexApprovalResponseRequest("rpc-5", "deny")).toEqual({
      jsonrpc: "2.0",
      id: "rpc-5",
      result: { decision: "decline" },
    });
  });

  it("builds bounded interrupt and thread-read requests", () => {
    expect(createCodexTurnInterruptRequest("rpc-6", "thread-1", "turn-1")).toEqual({
      jsonrpc: "2.0",
      id: "rpc-6",
      method: "turn/interrupt",
      params: { threadId: "thread-1", turnId: "turn-1" },
    });
    expect(createCodexThreadReadRequest("rpc-7", "thread-1", true)).toEqual({
      jsonrpc: "2.0",
      id: "rpc-7",
      method: "thread/read",
      params: { threadId: "thread-1", includeTurns: true },
    });
    expect(() => createCodexTurnInterruptRequest("rpc-8", "thread-1", "turn\n1")).toThrowError(
      expect.objectContaining({ code: "codex_thread_invalid" }),
    );
  });

  it("rejects malformed request identities and unbounded input", () => {
    expect(() => createCodexThreadResumeRequest("rpc\n1", "thread-1")).toThrowError(
      expect.objectContaining({ code: "codex_rpc_request_invalid" }),
    );
    expect(() => createCodexTurnStartRequest("rpc-1", "thread-1", "x".repeat(16_385))).toThrowError(
      expect.objectContaining({ code: "codex_rpc_input_invalid" }),
    );
  });

  it("encodes one JSON-RPC message per newline-delimited frame", () => {
    const request = createCodexInitializeRequest("rpc-6");
    const frame = encodeCodexJsonl(request);
    expect(frame.endsWith("\n")).toBe(true);
    expect(decodeCodexJsonlLine(frame)).toEqual(request);
  });

  it("reassembles chunked stdio input into ordered messages", async () => {
    const first = encodeCodexJsonl(createCodexInitializeRequest("rpc-7"));
    const second = encodeCodexJsonl(createCodexInitializedNotification());
    const chunks = (async function* () {
      yield first.slice(0, 10);
      yield first.slice(10) + second.slice(0, 4);
      yield second.slice(4);
    })();
    const messages = [];
    for await (const message of decodeCodexJsonlStream(chunks)) messages.push(message);
    expect(messages).toEqual([createCodexInitializeRequest("rpc-7"), createCodexInitializedNotification()]);
  });

  it("rejects blank, malformed, and oversized frames", () => {
    expect(() => decodeCodexJsonlLine("\n")).toThrowError(
      expect.objectContaining({ code: "codex_rpc_frame_invalid" }),
    );
    expect(() => decodeCodexJsonlLine("{not-json}\n")).toThrowError(
      expect.objectContaining({ code: "codex_rpc_frame_invalid" }),
    );
    expect(() => encodeCodexJsonl({ payload: "x".repeat(1_048_577) })).toThrowError(
      expect.objectContaining({ code: "codex_rpc_frame_too_large" }),
    );
  });
});
