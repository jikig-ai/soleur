import { describe, expect, it } from "vitest";
import { encryptKey } from "@/server/byok";
import { createCodexApiKeyProvider } from "@/server/codex-credential-provider";

describe("Codex API-key credential provider", () => {
  it("loads an encrypted Web-settings credential into a short-lived lease", async () => {
    const encrypted = encryptKey("sk-openai-test", "user-1");
    const provider = createCodexApiKeyProvider({
      load: async () => ({
        encrypted_key: encrypted.encrypted.toString("base64"),
        iv: encrypted.iv.toString("base64"),
        auth_tag: encrypted.tag.toString("base64"),
        key_version: 2,
      }),
      userId: "user-1",
      now: () => 1_000,
      leaseTtlMs: 60_000,
    });

    const lease = await provider.acquire();
    expect(lease.accessToken).toBe("sk-openai-test");
    expect(lease.expiresAt).toBe(61_000);
  });

  it("fails closed when the workspace user has no OpenAI credential", async () => {
    const provider = createCodexApiKeyProvider({
      load: async () => null,
      userId: "user-1",
      now: () => 1_000,
    });
    await expect(provider.acquire()).rejects.toMatchObject({ code: "codex_credentials_missing" });
  });

  it("does not acquire after logout", async () => {
    const provider = createCodexApiKeyProvider({
      load: async () => null,
      userId: "user-1",
    });
    await provider.logout();
    await expect(provider.acquire()).rejects.toMatchObject({ code: "codex_credentials_logged_out" });
  });
});
