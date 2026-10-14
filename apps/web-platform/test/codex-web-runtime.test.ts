import { describe, expect, it } from "vitest";
import { createCodexWebEngineFactories, createCodexWebEngineFactoriesForBinding } from "@/server/codex-web-runtime";

const transport = {} as never;
const provider = {
  mode: "api-key" as const,
  acquire: async () => ({ accessToken: "token", expiresAt: Date.now() + 60_000 }),
  refresh: async () => ({ accessToken: "token", expiresAt: Date.now() + 60_000 }),
  logout: async () => undefined,
};

describe("Codex Web runtime composition", () => {
  it("selects the per-user API-key provider for api-key mode", () => {
    const factories = createCodexWebEngineFactories({
      userId: "user-1",
      authMode: "api-key",
      transport,
      apiKeyProvider: provider,
    });
    expect(factories.codex).toBeTypeOf("function");
  });

  it("requires a managed provider for managed mode", () => {
    expect(() => createCodexWebEngineFactories({
      userId: "user-1",
      authMode: "managed",
      transport,
      apiKeyProvider: provider,
    })).toThrowError(expect.objectContaining({ code: "codex_managed_credentials_unconfigured" }));
  });

  it("does not silently substitute API-key credentials for managed mode", () => {
    const managed = { ...provider, mode: "managed" as const };
    const factories = createCodexWebEngineFactories({
      userId: "user-1",
      authMode: "managed",
      transport,
      managedProvider: managed,
    });
    expect(factories.codex).toBeTypeOf("function");
  });

  it("fails closed when neither a transport nor approved launcher is configured", () => {
    expect(() => createCodexWebEngineFactories({
      userId: "user-1",
      authMode: "api-key",
      apiKeyProvider: provider,
    })).toThrowError(expect.objectContaining({ code: "codex_transport_unconfigured" }));
  });

  it("derives auth mode from the persisted Codex binding", () => {
    const factories = createCodexWebEngineFactoriesForBinding({
      userId: "user-1",
      binding: { engineId: "codex", authMode: "api-key" },
      transport,
      apiKeyProvider: provider,
    });
    expect(factories.codex).toBeTypeOf("function");
  });

  it("rejects non-Codex or invalid persisted bindings", () => {
    expect(() => createCodexWebEngineFactoriesForBinding({
      userId: "user-1",
      binding: { engineId: "claude-code", authMode: "managed" },
      transport,
      managedProvider: { ...provider, mode: "managed" },
    })).toThrowError(expect.objectContaining({ code: "codex_binding_mismatch" }));
    expect(() => createCodexWebEngineFactoriesForBinding({
      userId: "user-1",
      binding: { engineId: "codex", authMode: "unknown" },
      transport,
    })).toThrowError(expect.objectContaining({ code: "codex_auth_mode_invalid" }));
  });
});
