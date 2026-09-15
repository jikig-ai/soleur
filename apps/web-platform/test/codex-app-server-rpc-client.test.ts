import { describe, expect, it, vi } from "vitest";
import { createCodexInitializeRequest } from "@/server/codex-app-server-protocol";
import { createCodexRpcClient } from "@/server/codex-app-server-rpc-client";

describe("Codex App Server RPC client", () => {
  it("correlates a request with its JSON-RPC result", async () => {
    const channel = { write: vi.fn(async () => undefined) };
    const client = createCodexRpcClient(channel);
    const resultPromise = client.request(createCodexInitializeRequest("rpc-1"));
    expect(channel.write).toHaveBeenCalledWith(expect.stringContaining('"method":"initialize"'));
    client.receiveLine('{"id":"rpc-1","result":{"server":"codex"}}\n');
    await expect(resultPromise).resolves.toEqual({ server: "codex" });
  });

  it("routes notifications and server requests without consuming pending results", async () => {
    const channel = { write: vi.fn(async () => undefined) };
    const notification = vi.fn();
    const serverRequest = vi.fn();
    const client = createCodexRpcClient(channel, { onNotification: notification, onServerRequest: serverRequest });
    const resultPromise = client.request(createCodexInitializeRequest("rpc-2"));
    client.receive({ method: "turn/started", params: { turn: { id: "turn-1" } } });
    client.receive({ id: "approval-1", method: "item/commandExecution/requestApproval", params: { itemId: "item-1" } });
    expect(notification).toHaveBeenCalledWith(expect.objectContaining({ method: "turn/started" }));
    expect(serverRequest).toHaveBeenCalledWith(expect.objectContaining({ id: "approval-1" }));
    client.receive({ id: "rpc-2", result: {} });
    await expect(resultPromise).resolves.toEqual({});
  });

  it("responds to a server initiated request without adding a pending call", async () => {
    const channel = { write: vi.fn(async () => undefined) };
    const client = createCodexRpcClient(channel);
    await expect(client.respond("approval-1", { decision: "accept" })).resolves.toBeUndefined();
    expect(channel.write).toHaveBeenCalledWith(
      '{"jsonrpc":"2.0","id":"approval-1","result":{"decision":"accept"}}\n',
    );
    expect(client.pendingCount()).toBe(0);
  });

  it("rejects unsafe response identities and channel write failures", async () => {
    const client = createCodexRpcClient({ write: vi.fn(async () => { throw new Error("closed"); }) });
    await expect(client.respond("approval\n1", { decision: "decline" })).rejects.toMatchObject({ code: "codex_rpc_request_invalid" });
    await expect(client.respond("approval-2", { decision: "decline" })).rejects.toMatchObject({ code: "codex_rpc_channel_error" });
  });

  it("sanitizes correlated RPC errors", async () => {
    const client = createCodexRpcClient({ write: vi.fn(async () => undefined) });
    const resultPromise = client.request(createCodexInitializeRequest("rpc-3"));
    client.receive({ id: "rpc-3", error: { code: 401, message: "token=secret" } });
    await expect(resultPromise).rejects.toMatchObject({ code: "codex_rpc_error", message: "Codex RPC request failed" });
  });

  it("rejects duplicate in-flight IDs and closes pending requests", async () => {
    const client = createCodexRpcClient({ write: vi.fn(async () => undefined) });
    const first = client.request(createCodexInitializeRequest("rpc-4"));
    await expect(client.request(createCodexInitializeRequest("rpc-4"))).rejects.toMatchObject({ code: "codex_rpc_request_in_flight" });
    client.close();
    await expect(first).rejects.toMatchObject({ code: "codex_rpc_closed" });
    await expect(client.request(createCodexInitializeRequest("rpc-5"))).rejects.toMatchObject({ code: "codex_rpc_closed" });
  });
});
