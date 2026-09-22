import { describe, expect, it } from "vitest";
import { createCodexWebEngineFactories } from "@/server/codex-web-runtime";

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
});
