import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import type { SupabaseClient } from "@supabase/supabase-js";
import {
  getMyRevocationStatus,
  _setRevocationStatusTenantFnForTest,
} from "@/lib/supabase/tenant";

// Unit tests for `getMyRevocationStatus` — shape-mapping + fail-open
// semantics. The DB-substrate shape is pinned in
// `test/server/tenant-jwt-rls-deny.tenant-isolation.test.ts` under
// TENANT_INTEGRATION_TEST=1.
//
// We inject a fake tenant client via the `_setRevocationStatusTenantFnForTest`
// hook (sibling pattern to `_setMintFnForTest`); the inner `tenant.rpc(...)`
// call returns whatever shape the test stages.
//
// References:
// - Plan: knowledge-base/project/plans/2026-05-25-feat-jti-revoke-rls-3930-3932-plan.md §Phase 3.1
// - Integration coverage in test/server/tenant-jwt-rls-deny.tenant-isolation.test.ts

const mockMirror = vi.fn();

vi.mock("@/server/observability", () => ({
  mirrorWithDebounce: (...args: unknown[]) => mockMirror(...args),
  reportSilentFallback: vi.fn(),
  warnSilentFallback: vi.fn(),
}));

function fakeTenant(rpcReturn: unknown, throwInstead = false): SupabaseClient {
  return {
    rpc: async () => {
      if (throwInstead) throw rpcReturn;
      return rpcReturn;
    },
  } as unknown as SupabaseClient;
}

describe("getMyRevocationStatus", () => {
  beforeEach(() => {
    mockMirror.mockReset();
  });

  afterEach(() => {
    _setRevocationStatusTenantFnForTest(null);
    vi.restoreAllMocks();
  });

  it("returns {revoked: false, deniedAt: null, reason: null} for un-denied caller", async () => {
    _setRevocationStatusTenantFnForTest(async () =>
      fakeTenant({
        data: [{ revoked: false, denied_at: null, reason: null }],
        error: null,
      }),
    );
    const result = await getMyRevocationStatus("user-id-A");
    expect(result).toEqual({ revoked: false, deniedAt: null, reason: null });
    expect(mockMirror).not.toHaveBeenCalled();
  });

  it("returns {revoked: true, deniedAt, reason} for denied caller", async () => {
    _setRevocationStatusTenantFnForTest(async () =>
      fakeTenant({
        data: [
          {
            revoked: true,
            denied_at: "2026-05-25T10:00:00.000Z",
            reason: "test-revocation",
          },
        ],
        error: null,
      }),
    );
    const result = await getMyRevocationStatus("user-id-A");
    expect(result).toEqual({
      revoked: true,
      deniedAt: "2026-05-25T10:00:00.000Z",
      reason: "test-revocation",
    });
  });

  it("returns null AND mirrors to Sentry when RPC errors", async () => {
    _setRevocationStatusTenantFnForTest(async () =>
      fakeTenant({
        data: null,
        error: { code: "42501", message: "permission denied" },
      }),
    );
    const result = await getMyRevocationStatus("user-id-A");
    expect(result).toBeNull();
    expect(mockMirror).toHaveBeenCalledTimes(1);
    const callArgs = mockMirror.mock.calls[0] as unknown[];
    const ctx = callArgs[1] as { feature: string; op: string };
    expect(ctx.feature).toBe("tenant-jwt");
    expect(ctx.op).toBe("my_revocation_status.error");
  });

  it("returns null AND mirrors when tenant fn throws", async () => {
    _setRevocationStatusTenantFnForTest(async () => {
      throw new Error("network blip");
    });
    const result = await getMyRevocationStatus("user-id-A");
    expect(result).toBeNull();
    expect(mockMirror).toHaveBeenCalledTimes(1);
  });

  it("returns null when data is empty array (defensive)", async () => {
    _setRevocationStatusTenantFnForTest(async () =>
      fakeTenant({ data: [], error: null }),
    );
    const result = await getMyRevocationStatus("user-id-A");
    expect(result).toBeNull();
  });
});
