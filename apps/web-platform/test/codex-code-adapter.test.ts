import { describe, expect, it, vi } from "vitest";
import {
  CODEX_ENGINE_ID,
  createCodexCodeAdapter,
  createCodexAuthBoundary,
  normalizeCodexUsageEvent,
  runWithCodexRecovery,
  sanitizeCodexError,
  validateCodexEvent,
  assertCodexEndpoint,
  codexAuthMetadata,
  normalizeCodexCancellation,
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

  it("fails closed for expired or empty leases", async () => {
    const provider: CodexAuthProvider = {
      mode: "api-key",
      acquire: vi.fn(async () => ({ accessToken: "", expiresAt: Date.now() - 1 })),
      refresh: vi.fn(),
      logout: vi.fn(),
    };
    const boundary = createCodexAuthBoundary(provider);
    await expect(boundary.acquire()).rejects.toMatchObject({ code: "codex_credential_expired" });
  });

  it("normalizes revoked managed credentials without exposing provider details", async () => {
    const provider: CodexAuthProvider = {
      mode: "managed",
      acquire: vi.fn(async () => { throw Object.assign(new Error("refresh token abc revoked"), { code: "invalid_grant" }); }),
      refresh: vi.fn(),
      logout: vi.fn(),
    };
    const boundary = createCodexAuthBoundary(provider);
    await expect(boundary.acquire()).rejects.toMatchObject({ code: "codex_credentials_revoked" });
    await expect(boundary.acquire()).rejects.not.toThrow("refresh token abc");
  });

  it("does not reacquire credentials after logout", async () => {
    const provider: CodexAuthProvider = {
      mode: "managed",
      acquire: vi.fn(async () => ({ accessToken: "secret", expiresAt: Date.now() + 60_000 })),
      refresh: vi.fn(async () => ({ accessToken: "refreshed", expiresAt: Date.now() + 60_000 })),
      logout: vi.fn(async () => undefined),
    };
    const boundary = createCodexAuthBoundary(provider);
    await boundary.logout();
    await expect(boundary.acquire()).rejects.toMatchObject({ code: "codex_credentials_logged_out" });
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
    for await (const event of adapter.start({ runId: "run-1" } as never, { text: "hi", attachmentIds: [] })) events.push(event);
    expect(events).toHaveLength(1);
    expect(transport.start).toHaveBeenCalledOnce();
  });

  it("rejects stale or duplicate sequence numbers within one provider stream", async () => {
    const auth = createCodexAuthBoundary({
      mode: "api-key",
      acquire: vi.fn(async () => ({ accessToken: "opaque", expiresAt: Date.now() + 60_000 })),
      refresh: vi.fn(async () => ({ accessToken: "refreshed", expiresAt: Date.now() + 60_000 })),
      logout: vi.fn(async () => undefined),
    });
    const transport = {
      start: vi.fn(async function* () {
        yield { runId: "run-1", eventId: "evt-1", sequence: 2, payload: { type: "text", text: "first" } as const };
        yield { runId: "run-1", eventId: "evt-2", sequence: 2, payload: { type: "text", text: "duplicate" } as const };
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
    const events = adapter.start({ runId: "run-1" } as never, { text: "hi", attachmentIds: [] });
    await expect((async () => {
      const collected = [];
      for await (const event of events) collected.push(event);
      return collected;
    })()).rejects.toMatchObject({ code: "codex_event_sequence_invalid" });
  });

  it("refreshes once when a promise lifecycle call reports an expired lease", async () => {
    const auth = createCodexAuthBoundary({
      mode: "managed",
      acquire: vi.fn(async () => ({ accessToken: "first", expiresAt: Date.now() + 60_000 })),
      refresh: vi.fn(async () => ({ accessToken: "second", expiresAt: Date.now() + 60_000 })),
      logout: vi.fn(async () => undefined),
    });
    const transport = {
      start: vi.fn(async function* () { yield* []; }),
      continue: vi.fn(async function* () { yield* []; }),
      cancel: vi.fn()
        .mockRejectedValueOnce(Object.assign(new Error("expired"), { code: "codex_credential_expired" }))
        .mockResolvedValue("confirmed" as const),
      reconcile: vi.fn().mockResolvedValue("running" as const),
      resumeFromCursor: vi.fn(async function* () { yield* []; }),
      respondToApproval: vi.fn().mockResolvedValue(undefined),
      erase: vi.fn().mockResolvedValue("confirmed" as const),
      dispose: vi.fn().mockResolvedValue(undefined),
    };
    const adapter = createCodexCodeAdapter(transport, auth);
    await expect(adapter.cancel({ runId: "run-1" } as never, { resumeHandle: "opaque", sessionId: null }))
      .resolves.toBe("confirmed");
    expect(transport.cancel).toHaveBeenCalledTimes(2);
    expect(transport.cancel.mock.calls[1][2]).toEqual(expect.objectContaining({ accessToken: "second" }));
  });
});

describe("Codex usage normalization", () => {
  it("preserves native token units and marks absent pricing unavailable", () => {
    expect(normalizeCodexUsageEvent("run-1", "usage-1", 2, {
      inputTokens: 12,
      outputTokens: 8,
    })).toEqual({
      runId: "run-1",
      eventId: "usage-1",
      sequence: 2,
      payload: {
        type: "usage",
        usage: {
          native: [{ unit: "input_tokens", value: 12 }, { unit: "output_tokens", value: 8 }],
          cost: { provenance: "unavailable" },
        },
      },
    });
  });

  it("retains provider-reported cost provenance", () => {
    const event = normalizeCodexUsageEvent("run-1", "usage-2", 3, {
      inputTokens: 1,
      outputTokens: 2,
      cost: { amount: 0.04, currency: "USD" },
    });
    expect(event.payload.type).toBe("usage");
    if (event.payload.type === "usage") expect(event.payload.usage.cost).toEqual({ provenance: "reported", amount: 0.04, currency: "USD" });
  });
});

describe("Codex credential recovery", () => {
  it("refreshes once after an authorization failure", async () => {
    const auth = createCodexAuthBoundary({
      mode: "managed",
      acquire: vi.fn(async () => ({ accessToken: "first", expiresAt: Date.now() + 60_000 })),
      refresh: vi.fn(async () => ({ accessToken: "second", expiresAt: Date.now() + 60_000 })),
      logout: vi.fn(async () => undefined),
    });
    const operation = vi.fn()
      .mockRejectedValueOnce(Object.assign(new Error("expired"), { code: "codex_credential_expired" }))
      .mockResolvedValue("ok");
    await expect(runWithCodexRecovery(auth, operation)).resolves.toBe("ok");
    expect(operation).toHaveBeenCalledTimes(2);
    expect(operation.mock.calls[1][0]).toEqual(expect.objectContaining({ accessToken: "second" }));
  });

  it("does not retry non-auth failures", async () => {
    const auth = createCodexAuthBoundary({
      mode: "api-key",
      acquire: vi.fn(async () => ({ accessToken: "key", expiresAt: Date.now() + 60_000 })),
      refresh: vi.fn(),
      logout: vi.fn(async () => undefined),
    });
    const failure = new Error("provider unavailable");
    const operation = vi.fn().mockRejectedValue(failure);
    await expect(runWithCodexRecovery(auth, operation)).rejects.toBe(failure);
    expect(operation).toHaveBeenCalledOnce();
  });
});

describe("Codex error sanitization", () => {
  it("removes credential-shaped details while retaining a stable code", () => {
    const error = sanitizeCodexError(Object.assign(
      new Error("request failed with sk-live-abcdef1234567890 at https://api.example.test"),
      { code: "provider_timeout" },
    ));
    expect(error).toMatchObject({ code: "provider_timeout", message: "Codex provider request failed" });
    expect(error.message).not.toContain("sk-live");
    expect(error.message).not.toContain("api.example");
  });

  it("maps unknown thrown values to a generic provider error", () => {
    expect(sanitizeCodexError("token=secret")).toMatchObject({ code: "codex_provider_error", message: "Codex provider request failed" });
  });
});

describe("Codex event boundary", () => {
  it("accepts only events for the bound run with a positive sequence", () => {
    const event = { runId: "run-1", eventId: "evt-1", sequence: 1, payload: { type: "text", text: "ok" } as const };
    expect(validateCodexEvent(event, "run-1")).toEqual(event);
  });

  it("rejects cross-run and stale sequence events", () => {
    const event = { runId: "run-2", eventId: "evt-1", sequence: 0, payload: { type: "text", text: "replay" } as const };
    expect(() => validateCodexEvent(event, "run-1")).toThrowError(expect.objectContaining({ code: "codex_event_invalid" }));
  });
});

describe("Codex egress boundary", () => {
  it("accepts only HTTPS endpoints on the configured host allowlist", () => {
    expect(assertCodexEndpoint("https://api.openai.com/v1/responses", ["api.openai.com"])).toBe("https://api.openai.com/v1/responses");
  });

  it("rejects insecure, unparseable, and unallowlisted endpoints", () => {
    for (const endpoint of ["http://api.openai.com", "https://evil.example.test", "not-a-url"]) {
      expect(() => assertCodexEndpoint(endpoint, ["api.openai.com"])).toThrowError(expect.objectContaining({ code: "codex_egress_denied" }));
    }
  });
});

describe("Codex DSAR metadata", () => {
  it("exports auth mode and expiry without credential material", () => {
    expect(codexAuthMetadata("managed", { accessToken: "secret-token", expiresAt: 123 })).toEqual({
      mode: "managed",
      expiresAt: 123,
    });
    expect(codexAuthMetadata("managed", { accessToken: "secret-token", expiresAt: 123 })).not.toHaveProperty("accessToken");
  });
});

describe("Codex cancellation normalization", () => {
  it("confirms only an explicit terminal acknowledgement", () => {
    expect(normalizeCodexCancellation("cancelled")).toBe("confirmed");
    expect(normalizeCodexCancellation("accepted")).toBe("requested");
    expect(normalizeCodexCancellation("unknown")).toBe("requested");
  });
});
