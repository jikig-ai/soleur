import { describe, test, expect, vi, beforeEach } from "vitest";

// Wrapper-level test for removeWorkspaceMember + updateWorkspaceMemberRole
// (#4779-followup).
//
// Both RPCs run under createServiceClient() (service-role key,
// persistSession:false) where auth.uid() is NULL. Migration 094 widens them to
// accept p_caller_user_id and resolves the caller via
// COALESCE(p_caller_user_id, auth.uid()); the wrappers MUST forward the
// route-verified callerUserId as p_caller_user_id or every call raises 28000 →
// rpc_failed → HTTP 500 (the "Failed to remove member" toast). Mirrors
// transfer-ownership-wrapper.test.ts (migration 092).

const {
  mockRpc,
  mockCreateServiceClient,
  mockAbortSessions,
  mockSessionsGet,
  mockReportSilentFallback,
} = vi.hoisted(() => ({
  mockRpc: vi.fn(),
  mockCreateServiceClient: vi.fn(),
  mockAbortSessions: vi.fn(),
  mockSessionsGet: vi.fn(() => undefined),
  mockReportSilentFallback: vi.fn(),
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
  reportSilentFallback: mockReportSilentFallback,
}));

import {
  removeWorkspaceMember,
  updateWorkspaceMemberRole,
} from "@/server/workspace-membership";

const CALLER_ID = "caller-owner-uuid";
const TARGET_ID = "target-member-uuid";
const WORKSPACE_ID = "ws-uuid";

beforeEach(() => {
  vi.clearAllMocks();
  mockSessionsGet.mockReturnValue(undefined);
  mockRpc.mockResolvedValue({ data: null, error: null });
  mockCreateServiceClient.mockReturnValue({ rpc: mockRpc });
});

describe("removeWorkspaceMember wrapper", () => {
  test("forwards p_caller_user_id to the remove_workspace_member RPC payload", async () => {
    const result = await removeWorkspaceMember({
      callerUserId: CALLER_ID,
      workspaceId: WORKSPACE_ID,
      inviteeUserId: TARGET_ID,
    });

    expect(result).toEqual({ ok: true });
    expect(mockRpc).toHaveBeenCalledWith("remove_workspace_member", {
      p_workspace_id: WORKSPACE_ID,
      p_user_id: TARGET_ID,
      p_caller_user_id: CALLER_ID,
    });
  });

  test("short-circuits owner-removes-self before reaching the RPC", async () => {
    const result = await removeWorkspaceMember({
      callerUserId: CALLER_ID,
      workspaceId: WORKSPACE_ID,
      inviteeUserId: CALLER_ID,
    });
    expect(result).toEqual({ ok: false, reason: "owner_cannot_remove_self" });
    expect(mockRpc).not.toHaveBeenCalled();
  });
});

describe("updateWorkspaceMemberRole wrapper", () => {
  test("forwards p_caller_user_id to the update_workspace_member_role RPC payload", async () => {
    const result = await updateWorkspaceMemberRole({
      callerUserId: CALLER_ID,
      workspaceId: WORKSPACE_ID,
      targetUserId: TARGET_ID,
      newRole: "member",
    });

    expect(result).toEqual({ ok: true });
    expect(mockRpc).toHaveBeenCalledWith("update_workspace_member_role", {
      p_workspace_id: WORKSPACE_ID,
      p_user_id: TARGET_ID,
      p_new_role: "member",
      p_caller_user_id: CALLER_ID,
    });
  });
});
