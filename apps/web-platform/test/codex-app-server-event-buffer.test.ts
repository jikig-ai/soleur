import { describe, expect, it } from "vitest";
import { createCodexAppServerEventBuffer } from "@/server/codex-app-server-event-buffer";

describe("Codex App Server event buffer", () => {
  it("delivers notifications in order and completes after close", async () => {
    const buffer = createCodexAppServerEventBuffer();
    buffer.push({ method: "turn/started", params: { turnId: "turn-1" } });
    buffer.push({ method: "item/agentMessage/delta", params: { delta: "hello" } });
    buffer.close();

    const events: unknown[] = [];
    for await (const event of buffer.stream()) events.push(event);
    expect(events).toEqual([
      { method: "turn/started", params: { turnId: "turn-1" } },
      { method: "item/agentMessage/delta", params: { delta: "hello" } },
    ]);
  });

  it("surfaces a terminal source error after queued events", async () => {
    const buffer = createCodexAppServerEventBuffer();
    buffer.push({ method: "turn/started" });
    buffer.close(Object.assign(new Error("source disconnected"), { code: "codex_source_closed" }));
    const consume = (async () => {
      const events: unknown[] = [];
      for await (const event of buffer.stream()) events.push(event);
      return events;
    })();
    await expect(consume).rejects.toMatchObject({ code: "codex_source_closed" });
  });

  it("fails closed when the bounded queue overflows", async () => {
    const buffer = createCodexAppServerEventBuffer({ maxSize: 1 });
    buffer.push({ method: "turn/started" });
    buffer.push({ method: "turn/completed" });
    await expect((async () => {
      for await (const _event of buffer.stream()) { /* drain */ }
    })()).rejects.toMatchObject({ code: "codex_event_backpressure" });
  });
});
