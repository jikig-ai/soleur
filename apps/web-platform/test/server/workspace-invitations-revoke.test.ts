import { describe, test, expect, vi, beforeEach } from "vitest";

// Unit tests for revokeWorkspaceInvitation() service wrapper
// (feat-cancel-pending-invite, #4634, TR4). Mirrors declineWorkspaceInvitation:
// calls the revoke_workspace_invitation RPC on the SERVICE client, maps a
// transport error to {ok:false,reason:'rpc_failed'} + reportSilentFallback,
// passes {ok:false,reason} through, and returns {ok:true} on success.

const { mockRpc, mockReportSilentFallback } = vi.hoisted(() => ({
  mockRpc: vi.fn(),
  mockReportSilentFallback: vi.fn(),
}));

vi.mock("@/lib/supabase/service", () => ({
  createServiceClient: vi.fn(() => ({ rpc: mockRpc })),
}));

vi.mock("@/server/observability", () => ({
  reportSilentFallback: mockReportSilentFallback,
}));

import { revokeWorkspaceInvitation } from "@/server/workspace-invitations";

const INVITATION_ID = "11111111-1111-1111-1111-111111111111";
const CALLER_ID = "22222222-2222-2222-2222-222222222222";

beforeEach(() => {
  vi.clearAllMocks();
});

describe("revokeWorkspaceInvitation", () => {
  test("calls revoke_workspace_invitation RPC with invitation + caller", async () => {
    mockRpc.mockResolvedValue({ data: { ok: true }, error: null });
    const result = await revokeWorkspaceInvitation(INVITATION_ID, CALLER_ID);
    expect(result).toEqual({ ok: true });
    expect(mockRpc).toHaveBeenCalledWith("revoke_workspace_invitation", {
      p_invitation_id: INVITATION_ID,
      p_caller_user_id: CALLER_ID,
    });
  });

  test("transport error → {ok:false, reason:'rpc_failed'} + reportSilentFallback", async () => {
    mockRpc.mockResolvedValue({ data: null, error: { message: "boom" } });
    const result = await revokeWorkspaceInvitation(INVITATION_ID, CALLER_ID);
    expect(result).toEqual({ ok: false, reason: "rpc_failed" });
    expect(mockReportSilentFallback).toHaveBeenCalledTimes(1);
  });

  test("passes terminal-state reason through", async () => {
    mockRpc.mockResolvedValue({ data: { ok: false, reason: "already_accepted" }, error: null });
    const result = await revokeWorkspaceInvitation(INVITATION_ID, CALLER_ID);
    expect(result).toEqual({ ok: false, reason: "already_accepted" });
    expect(mockReportSilentFallback).not.toHaveBeenCalled();
  });
});
