import { describe, it, expect, vi, beforeEach } from "vitest";

// Issue B part 2 (AC15) — resolveBashAutonomous reads workspaces.bash_autonomous
// ONLY via the membership-checked get_workspace_bash_autonomous RPC, and is
// FAIL-CLOSED: any error / null / RuntimeAuthError resolves false so a
// settings-read failure can never silently enable the approval-bypass.

const { mockRpc } = vi.hoisted(() => ({ mockRpc: vi.fn() }));

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
  // Faithful to the real switch (`lib/supabase/tenant.ts:120`), including the
  // exhaustive `: never` rail so a future cause-widening breaks this mock
  // loudly instead of silently returning `undefined`.
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

describe("resolveBashAutonomous (workspace-scoped, RPC-only, fail-closed)", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("returns true when the RPC returns true for the active workspace", async () => {
    mockRpc.mockResolvedValue({ data: true, error: null });
    const { resolveBashAutonomous } = await import(
      "@/server/resolve-bash-autonomous"
    );
    const result = await resolveBashAutonomous("user-1", "ws-active");
    expect(result).toBe(true);
    expect(mockRpc).toHaveBeenCalledWith("get_workspace_bash_autonomous", {
      p_workspace_id: "ws-active",
    });
  });

  it("returns false when the RPC returns false", async () => {
    mockRpc.mockResolvedValue({ data: false, error: null });
    const { resolveBashAutonomous } = await import(
      "@/server/resolve-bash-autonomous"
    );
    expect(await resolveBashAutonomous("user-1", "ws-1")).toBe(false);
  });

  it("undefined claim defaults to the solo workspace (= userId)", async () => {
    mockRpc.mockResolvedValue({ data: true, error: null });
    const { resolveBashAutonomous } = await import(
      "@/server/resolve-bash-autonomous"
    );
    await resolveBashAutonomous("user-solo");
    expect(mockRpc).toHaveBeenCalledWith("get_workspace_bash_autonomous", {
      p_workspace_id: "user-solo",
    });
  });

  it("FAIL-CLOSED: RPC null (non-member deny path) → false", async () => {
    mockRpc.mockResolvedValue({ data: null, error: null });
    const { resolveBashAutonomous } = await import(
      "@/server/resolve-bash-autonomous"
    );
    expect(await resolveBashAutonomous("user-1", "ws-not-mine")).toBe(false);
  });

  it("FAIL-CLOSED: RPC error → false AND mirrors to Sentry at error (not warning)", async () => {
    const { reportSilentFallback, warnSilentFallback } = await import(
      "@/server/observability"
    );
    mockRpc.mockResolvedValue({ data: null, error: { message: "boom" } });
    const { resolveBashAutonomous } = await import(
      "@/server/resolve-bash-autonomous"
    );
    expect(await resolveBashAutonomous("user-1", "ws-1")).toBe(false);
    expect(reportSilentFallback).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({ feature: "resolve-bash-autonomous" }),
    );
    // The in-`try` RPC-read fault is NOT a transient mint blip — it must stay
    // error-level. Guards against a future mis-route to the warning channel.
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
    const { resolveBashAutonomous } = await import(
      "@/server/resolve-bash-autonomous"
    );
    expect(await resolveBashAutonomous("user-1", "ws-1")).toBe(false);
    // A fully-recovered, fail-closed transient blip must NOT pollute the
    // error budget — it lands at warning with a queryable cause code.
    expect(warnSilentFallback).toHaveBeenCalledWith(
      expect.any(RuntimeAuthError),
      expect.objectContaining({
        feature: "resolve-bash-autonomous",
        extra: expect.objectContaining({ code: "auth_unavailable" }),
      }),
    );
    expect(reportSilentFallback).not.toHaveBeenCalled();
  });

  it("FAIL-CLOSED: denied_jti (session revoked) → false AND mirrors at ERROR", async () => {
    const { RuntimeAuthError, getFreshTenantClient } = await import(
      "@/lib/supabase/tenant"
    );
    const { reportSilentFallback, warnSilentFallback } = await import(
      "@/server/observability"
    );
    vi.mocked(getFreshTenantClient).mockImplementationOnce(async () => {
      throw new RuntimeAuthError("denied_jti", "session revoked");
    });
    const { resolveBashAutonomous } = await import(
      "@/server/resolve-bash-autonomous"
    );
    expect(await resolveBashAutonomous("user-1", "ws-1")).toBe(false);
    // Session revocation is on-call-actionable — keep it at error level.
    expect(reportSilentFallback).toHaveBeenCalledWith(
      expect.any(RuntimeAuthError),
      expect.objectContaining({
        feature: "resolve-bash-autonomous",
        extra: expect.objectContaining({ code: "session_revoked" }),
      }),
    );
    expect(warnSilentFallback).not.toHaveBeenCalled();
  });

  it("FAIL-CLOSED: rotation (rate-ceiling exhausted) → false AND mirrors at ERROR", async () => {
    const { RuntimeAuthError, getFreshTenantClient } = await import(
      "@/lib/supabase/tenant"
    );
    const { reportSilentFallback, warnSilentFallback } = await import(
      "@/server/observability"
    );
    vi.mocked(getFreshTenantClient).mockImplementationOnce(async () => {
      throw new RuntimeAuthError("rotation", "mint ceiling tripped");
    });
    const { resolveBashAutonomous } = await import(
      "@/server/resolve-bash-autonomous"
    );
    expect(await resolveBashAutonomous("user-1", "ws-1")).toBe(false);
    expect(reportSilentFallback).toHaveBeenCalledWith(
      expect.any(RuntimeAuthError),
      expect.objectContaining({
        feature: "resolve-bash-autonomous",
        extra: expect.objectContaining({ code: "auth_throttled" }),
      }),
    );
    expect(warnSilentFallback).not.toHaveBeenCalled();
  });

  it("re-throws non-RuntimeAuthError errors (not swallowed as false)", async () => {
    const { getFreshTenantClient } = await import("@/lib/supabase/tenant");
    vi.mocked(getFreshTenantClient).mockImplementationOnce(async () => {
      throw new Error("unexpected failure");
    });
    const { resolveBashAutonomous } = await import(
      "@/server/resolve-bash-autonomous"
    );
    await expect(resolveBashAutonomous("user-1", "ws-1")).rejects.toThrow(
      "unexpected failure",
    );
  });
});
