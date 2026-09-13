import { describe, expect, it, vi } from "vitest";
import {
  CODEX_ENGINE_ID,
  createCodexCodeAdapter,
  createCodexAuthBoundary,
  type CodexAuthProvider,
  type CodexAuthMode,
} from "@/server/codex-code-adapter";

describe("Codex auth boundary", () => {
  it("keeps API-key and managed auth modes explicit and isolated", async () => {
    const modes: CodexAuthMode[] = ["api-key", "managed"];
    for (const mode of modes) {
      const provider = {
        mode,
        acquire: vi.fn().mockResolvedValue({ accessToken: `secret-${mode}`, expiresAt: Date.now() + 60_000 }),
        refresh: vi.fn().mockResolvedValue({ accessToken: `refreshed-${mode}`, expiresAt: Date.now() + 60_000 }),
        logout: vi.fn().mockResolvedValue(undefined),
      };
      const boundary = createCodexAuthBoundary(provider);
      expect(CODEX_ENGINE_ID).toBe("codex");
      expect(boundary.mode).toBe(mode);
      await expect(boundary.acquire()).resolves.toEqual(expect.objectContaining({ accessToken: `secret-${mode}` }));
      await expect(boundary.refresh()).resolves.toEqual(expect.objectContaining({ accessToken: `refreshed-${mode}` }));
      await boundary.logout();
      expect(provider.acquire).toHaveBeenCalledOnce();
      expect(provider.refresh).toHaveBeenCalledOnce();
      expect(provider.logout).toHaveBeenCalledOnce();
    }
  });

  it("rejects a provider whose declared mode changes", async () => {
    const provider: CodexAuthProvider = {
      mode: "api-key",
      acquire: vi.fn(async () => ({ accessToken: "secret", expiresAt: Date.now() + 60_000 })),
      refresh: vi.fn(async () => ({ accessToken: "refreshed", expiresAt: Date.now() + 60_000 })),
      logout: vi.fn(async () => undefined),
    };
    const boundary = createCodexAuthBoundary(provider);
    provider.mode = "managed";
    await expect(boundary.acquire()).rejects.toMatchObject({ code: "codex_auth_mode_changed" });
    expect(provider.acquire).not.toHaveBeenCalled();
  });
});

describe("Codex neutral adapter boundary", () => {
  it("acquires an isolated lease before lifecycle transport calls", async () => {
    const auth = createCodexAuthBoundary({
      mode: "managed",
      acquire: vi.fn(async () => ({ accessToken: "opaque", expiresAt: Date.now() + 60_000 })),
      refresh: vi.fn(async () => ({ accessToken: "refreshed", expiresAt: Date.now() + 60_000 })),
      logout: vi.fn(async () => undefined),
    });
    const transport = {
      start: vi.fn(async function* (_context: never, _input: never, lease: never) {
        expect(lease).toEqual(expect.objectContaining({ accessToken: "opaque" }));
        yield { runId: "run-1", eventId: "evt-1", sequence: 1, payload: { type: "text", text: "ok" } as const };
      }),
      continue: vi.fn(async function* () { yield* []; }),
      cancel: vi.fn().mockResolvedValue("requested" as const),
      reconcile: vi.fn().mockResolvedValue("running" as const),
      resumeFromCursor: vi.fn(async function* () { yield* []; }),
      respondToApproval: vi.fn().mockResolvedValue(undefined),
      erase: vi.fn().mockResolvedValue("confirmed" as const),
      dispose: vi.fn().mockResolvedValue(undefined),
    };
    const adapter = createCodexCodeAdapter(transport, auth);
    const events = [];
    for await (const event of adapter.start({} as never, { text: "hi", attachmentIds: [] })) events.push(event);
    expect(events).toHaveLength(1);
    expect(transport.start).toHaveBeenCalledOnce();
  });
});
