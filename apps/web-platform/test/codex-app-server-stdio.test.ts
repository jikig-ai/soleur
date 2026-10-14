import { describe, expect, it, vi } from "vitest";
import { createCodexAppServerStdio } from "@/server/codex-app-server-stdio";
import { createCodexInitializeRequest } from "@/server/codex-app-server-protocol";

describe("Codex App Server stdio bridge", () => {
  it("connects JSONL stdout to RPC responses and notification events", async () => {
    let onExit: (() => void) | undefined;
    let releaseOutput!: () => void;
    let finishOutput!: () => void;
    const outputReady = new Promise<void>((resolve) => { releaseOutput = resolve; });
    const outputFinished = new Promise<void>((resolve) => { finishOutput = resolve; });
    const process = {
      stdin: { write: vi.fn(async () => undefined) },
      stdout: (async function* () {
        await outputReady;
        yield '{"id":"rpc-1","result":{"server":"codex"}}\n';
        yield '{"method":"turn/started","params":{"turnId":"turn-1"}}\n';
        await outputFinished;
      })(),
      kill: vi.fn(async () => undefined),
      onExit: (handler: () => void) => { onExit = () => { handler(); finishOutput(); }; },
    };
    const bridge = createCodexAppServerStdio({ spawn: vi.fn(async () => process) });
    const opened = await bridge.open({ accessToken: "opaque", expiresAt: Date.now() + 60_000 });
    const resultPromise = opened.client.request(createCodexInitializeRequest("rpc-1"));
    releaseOutput();
    await expect(resultPromise).resolves.toEqual({ server: "codex" });
    opened.events.close();
    onExit?.();
    const events: unknown[] = [];
    for await (const event of opened.events.stream()) events.push(event);
    expect(events).toEqual([{ method: "turn/started", params: { turnId: "turn-1" } }]);
    expect(process.stdin.write).toHaveBeenCalled();
  });

  it("fails closed on malformed stdout and disposes the process", async () => {
    const process = {
      stdin: { write: vi.fn(async () => undefined) },
      stdout: (async function* () { yield "not-json\n"; })(),
      kill: vi.fn(async () => undefined),
      onExit: vi.fn(),
    };
    const bridge = createCodexAppServerStdio({ spawn: vi.fn(async () => process) });
    const opened = await bridge.open({ accessToken: "opaque", expiresAt: Date.now() + 60_000 });
    await expect((async () => {
      for await (const _event of opened.events.stream()) { /* wait */ }
    })()).rejects.toMatchObject({ code: "codex_rpc_frame_invalid" });
    await opened.dispose();
    expect(process.kill).toHaveBeenCalledOnce();
  });
});
