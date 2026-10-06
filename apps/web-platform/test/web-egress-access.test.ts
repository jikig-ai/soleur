import { describe, it, expect, vi, beforeEach } from "vitest";

// feat-open-web-egress (#9534) — resolveWebEgress reads
// workspaces.web_egress ONLY via the membership-checked
// get_workspace_web_egress RPC and is FAIL-CLOSED: any error / null /
// RuntimeAuthError resolves false so a settings-read failure can never
// silently enable open-web egress. setWebEgress writes ONLY via the
// owner-only set_workspace_web_egress RPC; an error is mirrored and
// re-thrown (a write must not silently swallow). Shape cloned from
// resolve-bash-autonomous.test.ts / set-bash-autonomous.test.ts (the 097
// twins this pair is derived from).

const { mockRpc, mockEmitWorkspaceActionContext } = vi.hoisted(() => ({
  mockRpc: vi.fn(),
  mockEmitWorkspaceActionContext: vi.fn(),
}));

type RuntimeAuthCause = "jwt_mint" | "rotation" | "denied_jti";

vi.mock("@/lib/supabase/tenant", () => ({
  getFreshTenantClient: vi.fn(async () => ({ rpc: mockRpc })),
  // Faithful to the real class (`lib/supabase/tenant.ts:86`): `cause` is a
  // surfaced discriminant the catch site branches on. A bare
  // `class extends Error {}` would leave `err.cause` undefined and make the
  // per-cause severity split pass vacuously.
  RuntimeAuthError: class RuntimeAuthError extends Error {
    public readonly cause: RuntimeAuthCause;
    constructor(cause: RuntimeAuthCause, message: string) {
      super(message);
      this.name = "RuntimeAuthError";
      this.cause = cause;
    }
  },
  // Faithful to the real switch (`lib/supabase/tenant.ts:120`), including
  // the exhaustive `: never` rail so a future cause-widening breaks this
  // mock loudly instead of silently returning `undefined`.
  mapRuntimeAuthCauseToErrorCode: (cause: RuntimeAuthCause) => {
    switch (cause) {
      case "denied_jti":
        return "session_revoked";
      case "rotation":
        return "auth_throttled";
      case "jwt_mint":
        return "auth_unavailable";
      default: {
        const _exhaustive: never = cause;
        throw new Error(`unhandled RuntimeAuthError cause: ${_exhaustive}`);
      }
    }
  },
}));

vi.mock("@/server/observability", () => ({
  reportSilentFallback: vi.fn(),
  warnSilentFallback: vi.fn(),
}));

vi.mock("@/server/workspace-resolver", () => ({
  resolveCurrentWorkspaceId: vi.fn(async (userId: string) => userId),
}));

vi.mock("@/server/workspace-action-audit", () => ({
  emitWorkspaceActionContext: mockEmitWorkspaceActionContext,
}));

describe("resolveWebEgress (workspace-scoped, RPC-only, fail-closed)", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("returns true when the RPC returns true for the active workspace", async () => {
    mockRpc.mockResolvedValue({ data: true, error: null });
    const { resolveWebEgress } = await import("@/server/resolve-web-egress");
    const result = await resolveWebEgress("user-1", "ws-active");
    expect(result).toBe(true);
    expect(mockRpc).toHaveBeenCalledWith("get_workspace_web_egress", {
      p_workspace_id: "ws-active",
    });
  });

  it("returns false when the RPC returns false", async () => {
    mockRpc.mockResolvedValue({ data: false, error: null });
    const { resolveWebEgress } = await import("@/server/resolve-web-egress");
    expect(await resolveWebEgress("user-1", "ws-1")).toBe(false);
  });

  it("undefined claim defaults to the solo workspace (= userId)", async () => {
    mockRpc.mockResolvedValue({ data: true, error: null });
    const { resolveWebEgress } = await import("@/server/resolve-web-egress");
    await resolveWebEgress("user-solo");
    expect(mockRpc).toHaveBeenCalledWith("get_workspace_web_egress", {
      p_workspace_id: "user-solo",
    });
  });

  it("FAIL-CLOSED: RPC null (non-member deny path) → false", async () => {
    mockRpc.mockResolvedValue({ data: null, error: null });
    const { resolveWebEgress } = await import("@/server/resolve-web-egress");
    expect(await resolveWebEgress("user-1", "ws-not-mine")).toBe(false);
  });

  it("FAIL-CLOSED: RPC error → false AND mirrors to Sentry at error (not warning)", async () => {
    const { reportSilentFallback, warnSilentFallback } = await import(
      "@/server/observability"
    );
    mockRpc.mockResolvedValue({ data: null, error: { message: "boom" } });
    const { resolveWebEgress } = await import("@/server/resolve-web-egress");
    expect(await resolveWebEgress("user-1", "ws-1")).toBe(false);
    expect(reportSilentFallback).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({ feature: "resolve-web-egress" }),
    );
    // The in-`try` RPC-read fault is NOT a transient mint blip — it must
    // stay error-level. Guards against a future mis-route to the warning
    // channel.
    expect(warnSilentFallback).not.toHaveBeenCalled();
  });

  it("FAIL-CLOSED: transient jwt_mint blip → false AND mirrors at WARNING (not error)", async () => {
    const { RuntimeAuthError, getFreshTenantClient } = await import(
      "@/lib/supabase/tenant"
    );
    const { reportSilentFallback, warnSilentFallback } = await import(
      "@/server/observability"
    );
    vi.mocked(getFreshTenantClient).mockImplementationOnce(async () => {
      throw new RuntimeAuthError("jwt_mint", "token expired");
    });
    const { resolveWebEgress } = await import("@/server/resolve-web-egress");
    expect(await resolveWebEgress("user-1", "ws-1")).toBe(false);
    // A fully-recovered, fail-closed transient blip must NOT pollute the
    // error budget — it lands at warning with a queryable cause code.
    expect(warnSilentFallback).toHaveBeenCalledWith(
      expect.any(RuntimeAuthError),
      expect.objectContaining({
        feature: "resolve-web-egress",
        extra: expect.objectContaining({ code: "auth_unavailable" }),
      }),
    );
    expect(reportSilentFallback).not.toHaveBeenCalled();
  });
});

describe("setWebEgress (owner-only RPC write)", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("writes true via the RPC for the active workspace and returns the value", async () => {
    mockRpc.mockResolvedValue({ data: true, error: null });
    const { setWebEgress } = await import("@/server/set-web-egress");
    const result = await setWebEgress("user-1", true, "ws-active");
    expect(result).toBe(true);
    expect(mockRpc).toHaveBeenCalledWith("set_workspace_web_egress", {
      p_workspace_id: "ws-active",
      p_value: true,
    });
  });

  it("emits the workspace-action audit context on a successful flip", async () => {
    mockRpc.mockResolvedValue({ data: false, error: null });
    const { setWebEgress } = await import("@/server/set-web-egress");
    await setWebEgress("user-1", false, "ws-active");
    expect(mockEmitWorkspaceActionContext).toHaveBeenCalledWith({
      action: "scope-grant",
      userId: "user-1",
      workspaceId: "ws-active",
    });
  });

  it("undefined claim defaults to the solo workspace (= userId)", async () => {
    mockRpc.mockResolvedValue({ data: false, error: null });
    const { setWebEgress } = await import("@/server/set-web-egress");
    await setWebEgress("user-solo", false);
    expect(mockRpc).toHaveBeenCalledWith("set_workspace_web_egress", {
      p_workspace_id: "user-solo",
      p_value: false,
    });
  });

  it("owner-deny (P0001) throws WebEgressOwnerDeniedError (→ route 403)", async () => {
    const { reportSilentFallback } = await import("@/server/observability");
    mockRpc.mockResolvedValue({
      data: null,
      error: {
        code: "P0001",
        message: "not authorized: only a workspace owner may set web_egress",
      },
    });
    const { setWebEgress, WebEgressOwnerDeniedError } = await import(
      "@/server/set-web-egress"
    );
    await expect(setWebEgress("user-1", true, "ws-1")).rejects.toBeInstanceOf(
      WebEgressOwnerDeniedError,
    );
    expect(reportSilentFallback).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({ feature: "set-web-egress" }),
    );
    // A denied write must not emit a success audit context.
    expect(mockEmitWorkspaceActionContext).not.toHaveBeenCalled();
  });

  it("infra fault (no P0001) throws a generic error (→ route 500), NOT owner-denied", async () => {
    mockRpc.mockResolvedValue({
      data: null,
      error: { code: "57014", message: "statement timeout" },
    });
    const { setWebEgress, WebEgressOwnerDeniedError } = await import(
      "@/server/set-web-egress"
    );
    const err = await setWebEgress("user-1", true, "ws-1").catch((e) => e);
    expect(err).toBeInstanceOf(Error);
    expect(err).not.toBeInstanceOf(WebEgressOwnerDeniedError);
    expect(String(err.message)).toMatch(/failed to set web_egress/i);
    expect(mockEmitWorkspaceActionContext).not.toHaveBeenCalled();
  });
});
