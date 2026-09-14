import { describe, expect, it } from "vitest";
import {
  createCodexApprovalResponseRequest,
  createCodexInitializeRequest,
  createCodexInitializedNotification,
  createCodexThreadResumeRequest,
  createCodexThreadStartRequest,
  createCodexTurnStartRequest,
} from "@/server/codex-app-server-protocol";

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

  it("rejects malformed request identities and unbounded input", () => {
    expect(() => createCodexThreadResumeRequest("rpc\n1", "thread-1")).toThrowError(
      expect.objectContaining({ code: "codex_rpc_request_invalid" }),
    );
    expect(() => createCodexTurnStartRequest("rpc-1", "thread-1", "x".repeat(16_385))).toThrowError(
      expect.objectContaining({ code: "codex_rpc_input_invalid" }),
    );
  });
});
