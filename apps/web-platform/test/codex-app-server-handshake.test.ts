import { describe, expect, it, vi } from "vitest";
import { createCodexAppServerHandshake } from "@/server/codex-app-server-handshake";

describe("Codex App Server handshake", () => {
  it("awaits initialize before emitting initialized", async () => {
    const calls: string[] = [];
    const client = {
      request: vi.fn(async () => {
        calls.push("request");
        return { serverInfo: { name: "codex" } };
      }),
      notify: vi.fn(async () => {
        calls.push("notify");
      }),
    };
    await expect(createCodexAppServerHandshake(client, "rpc-handshake")).resolves.toEqual({
      serverInfo: { name: "codex" },
    });
    expect(calls).toEqual(["request", "notify"]);
    expect(client.notify).toHaveBeenCalledOnce();
  });

  it("does not emit initialized when initialize fails", async () => {
    const client = {
      request: vi.fn(async () => { throw Object.assign(new Error("failed"), { code: "codex_rpc_error" }); }),
      notify: vi.fn(async () => undefined),
    };
    await expect(createCodexAppServerHandshake(client, "rpc-failed")).rejects.toMatchObject({ code: "codex_rpc_error" });
    expect(client.notify).not.toHaveBeenCalled();
  });
});
