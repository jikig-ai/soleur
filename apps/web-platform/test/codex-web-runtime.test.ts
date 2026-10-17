import { describe, expect, it, vi } from "vitest";
import { createCodexWebEngineFactories, createCodexWebEngineFactoriesForBinding } from "@/server/codex-web-runtime";
import { createCodexCodeAdapter } from "@/server/codex-code-adapter";
import type { EngineAdapter, EngineRunContext } from "@/server/agent-engine-contract";

const transport = {} as never;
const provider = {
  mode: "api-key" as const,
  acquire: async () => ({ accessToken: "token", expiresAt: Date.now() + 60_000 }),
  refresh: async () => ({ accessToken: "token", expiresAt: Date.now() + 60_000 }),
  logout: async () => undefined,
};

function guardedFixture() {
  const context = { runId: "synthetic-run", binding: {} as never, idempotencyKey: "synthetic-turn", signal: new AbortController().signal } satisfies EngineRunContext;
  const stream = async function* () {
    yield { runId: context.runId, eventId: "synthetic-end", sequence: 1, payload: { type: "status", status: "completed" } as const };
  };
  const transport = {
    start: vi.fn(stream), continue: vi.fn(stream), resumeFromCursor: vi.fn(stream),
    reconcile: vi.fn(async () => "running" as const), respondToApproval: vi.fn(async () => undefined),
    cancel: vi.fn(async () => "confirmed" as const), erase: vi.fn(async () => "confirmed" as const), dispose: vi.fn(async () => undefined),
  };
  const authorizeRequest = vi.fn(async () => { throw Object.assign(new Error("Synthetic stale generation"), { code: "codex_binding_stale" }); });
  const createCodex = vi.fn(createCodexCodeAdapter);
  const adapter = createCodexWebEngineFactories({
    userId: "synthetic-user", authMode: "api-key", apiKeyProvider: provider,
    transport, authorizeRequest, createCodex,
  }).codex!();
  return { context, transport, authorizeRequest, adapter, createCodex };
}

async function invoke(adapter: EngineAdapter, context: EngineRunContext, operation: keyof EngineAdapter) {
  const input = { text: "Synthetic request", attachmentIds: [] };
  const session = { resumeHandle: "synthetic-thread", sessionId: null };
  switch (operation) {
    case "start": for await (const _event of adapter.start(context, input)) { /* consume */ } return;
    case "continue": for await (const _event of adapter.continue(context, session, input)) { /* consume */ } return;
    case "resumeFromCursor": for await (const _event of adapter.resumeFromCursor(context, null)) { /* consume */ } return;
    case "reconcile": return adapter.reconcile(context, session);
    case "respondToApproval": return adapter.respondToApproval(context, "synthetic-approval", "deny");
    case "cancel": return adapter.cancel(context, session);
    case "erase": return adapter.erase(context, session);
    case "dispose": return adapter.dispose();
  }
}

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

  it.each(["start", "continue", "resumeFromCursor", "reconcile", "respondToApproval"] as const)("fences %s before provider invocation through a custom factory", async (operation) => {
    const { context, transport, authorizeRequest, adapter, createCodex } = guardedFixture();
    await expect(invoke(adapter, context, operation)).rejects.toMatchObject({ code: "codex_binding_stale" });
    expect(createCodex).toHaveBeenCalledOnce();
    expect(authorizeRequest).toHaveBeenCalledWith(context);
    expect(transport[operation]).not.toHaveBeenCalled();
  });

  it.each(["cancel", "erase", "dispose"] as const)("allows %s cleanup despite stale request admission", async (operation) => {
    const { context, transport, authorizeRequest, adapter } = guardedFixture();
    await invoke(adapter, context, operation);
    expect(authorizeRequest).not.toHaveBeenCalled();
    expect(transport[operation]).toHaveBeenCalledOnce();
  });
});
