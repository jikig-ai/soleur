import { describe, expect, it, vi } from "vitest";
import {
  CODEX_ENGINE_ID,
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
