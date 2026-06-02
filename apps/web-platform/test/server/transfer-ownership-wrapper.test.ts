import { describe, test, expect, vi, beforeEach } from "vitest";

// Wrapper-level test for transferWorkspaceOwnership (#4765).
//
// The RPC owner-gate runs under createServiceClient() (service-role key,
// persistSession:false), where auth.uid() is NULL. Migration 092 widens the
// RPC to accept p_caller_user_id and resolves the caller via
// COALESCE(p_caller_user_id, auth.uid()); the wrapper MUST forward the
// route-verified callerUserId as p_caller_user_id or every call raises 28000
// → rpc_failed → HTTP 500. This test mocks createServiceClient().rpc and
// asserts the payload carries p_caller_user_id. Mirrors the rename_organization
// fix (PR #4762 / migration 091).

const { mockRpc, mockCreateServiceClient, mockAbortSessions, mockSessionsGet } =
  vi.hoisted(() => ({
    mockRpc: vi.fn(),
    mockCreateServiceClient: vi.fn(),
    mockAbortSessions: vi.fn(),
    mockSessionsGet: vi.fn(() => undefined),
  }));

vi.mock("@/lib/supabase/service", () => ({
  createServiceClient: mockCreateServiceClient,
}));

vi.mock("@/server/agent-session-registry", () => ({
  abortAllWorkspaceMemberSessions: mockAbortSessions,
}));

vi.mock("@/server/session-registry", () => ({
  sessions: { get: mockSessionsGet },
}));

vi.mock("@/lib/ws-close-helper", () => ({
  closeWithPreamble: vi.fn(),
}));

vi.mock("@/server/observability", () => ({
  reportSilentFallback: vi.fn(),
}));

import { transferWorkspaceOwnership } from "@/server/workspace-membership";

const CALLER_ID = "caller-owner-uuid";
const NEW_OWNER_ID = "new-owner-uuid";
const WORKSPACE_ID = "ws-uuid";
const ATTESTATION = "I authorize this ownership transfer.";

beforeEach(() => {
  vi.clearAllMocks();
  mockSessionsGet.mockReturnValue(undefined);
  mockRpc.mockResolvedValue({ data: "attestation-uuid", error: null });
  mockCreateServiceClient.mockReturnValue({ rpc: mockRpc });
});

describe("transferWorkspaceOwnership wrapper", () => {
  test("forwards p_caller_user_id to the RPC payload (service-role auth.uid() is NULL)", async () => {
    const result = await transferWorkspaceOwnership({
      callerUserId: CALLER_ID,
      workspaceId: WORKSPACE_ID,
      newOwnerUserId: NEW_OWNER_ID,
      attestationText: ATTESTATION,
    });

    expect(result).toEqual({ ok: true, attestationId: "attestation-uuid" });
    expect(mockRpc).toHaveBeenCalledTimes(1);
    expect(mockRpc).toHaveBeenCalledWith("transfer_workspace_ownership", {
      p_workspace_id: WORKSPACE_ID,
      p_new_owner_user_id: NEW_OWNER_ID,
      p_attestation_text: ATTESTATION,
      p_caller_user_id: CALLER_ID,
    });
  });

  test("short-circuits self-transfer before reaching the RPC", async () => {
    const result = await transferWorkspaceOwnership({
      callerUserId: CALLER_ID,
      workspaceId: WORKSPACE_ID,
      newOwnerUserId: CALLER_ID,
      attestationText: ATTESTATION,
    });

    expect(result).toEqual({ ok: false, reason: "self_transfer" });
    expect(mockRpc).not.toHaveBeenCalled();
  });

  test("maps an unmatched RPC error to rpc_failed (the broken-auth symptom)", async () => {
    mockRpc.mockResolvedValue({
      data: null,
      error: { message: "auth.uid() is NULL — caller must be authenticated" },
    });

    const result = await transferWorkspaceOwnership({
      callerUserId: CALLER_ID,
      workspaceId: WORKSPACE_ID,
      newOwnerUserId: NEW_OWNER_ID,
      attestationText: ATTESTATION,
    });

    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.reason).toBe("rpc_failed");
    }
  });

  test("maps caller_not_owner RPC error to the typed reason", async () => {
    mockRpc.mockResolvedValue({
      data: null,
      error: { message: "caller is not an owner of workspace x" },
    });

    const result = await transferWorkspaceOwnership({
      callerUserId: CALLER_ID,
      workspaceId: WORKSPACE_ID,
      newOwnerUserId: NEW_OWNER_ID,
      attestationText: ATTESTATION,
    });

    expect(result).toEqual({ ok: false, reason: "caller_not_owner" });
  });
});
