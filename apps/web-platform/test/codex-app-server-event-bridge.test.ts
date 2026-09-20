import { describe, expect, it, vi } from "vitest";
import { createCodexAppServerEventBridge } from "@/server/codex-app-server-event-bridge";
import { createCodexRpcClient } from "@/server/codex-app-server-rpc-client";

describe("Codex App Server notification bridge", () => {
  it("connects RPC notifications to the ordered event stream", async () => {
    const bridge = createCodexAppServerEventBridge({ maxSize: 2 });
    const client = createCodexRpcClient(
      { write: vi.fn(async () => undefined) },
      { onNotification: bridge.onNotification, onClose: bridge.onClose },
    );
    client.receive({ method: "turn/started", params: { turnId: "turn-1" } });
    client.receive({ method: "item/agentMessage/delta", params: { delta: "hello" } });
    bridge.close();

    const events: unknown[] = [];
    for await (const event of bridge.stream()) events.push(event);
    expect(events).toHaveLength(2);
    expect(bridge.size()).toBe(0);
  });

  it("propagates RPC channel closure to consumers", async () => {
    const bridge = createCodexAppServerEventBridge();
    const client = createCodexRpcClient(
      { write: vi.fn(async () => undefined) },
      { onNotification: bridge.onNotification, onClose: bridge.onClose },
    );
    const consume = (async () => {
      for await (const _event of bridge.stream()) { /* wait */ }
    })();
    client.close(Object.assign(new Error("provider exited"), { code: "codex_process_exit" }));
    await expect(consume).rejects.toMatchObject({ code: "codex_process_exit" });
  });
});
