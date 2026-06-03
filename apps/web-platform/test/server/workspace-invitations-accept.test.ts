import { describe, test, expect, vi, beforeEach } from "vitest";

// Unit tests for acceptWorkspaceInvitation() service wrapper. Guards the
// observability fix: an accept_workspace_invitation RPC transport error must
// be mirrored to Sentry via reportSilentFallback, AND the RPC `error` object
// (not null) must be passed as the FIRST arg so sqlStateFromError emits the
// `pg_code` tag (#4695). Mirrors workspace-invitations-revoke.test.ts.

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

import { acceptWorkspaceInvitation } from "@/server/workspace-invitations";

const INVITATION_ID = "11111111-1111-1111-1111-111111111111";
const ACCEPTER_ID = "22222222-2222-2222-2222-222222222222";

beforeEach(() => {
  vi.clearAllMocks();
});

describe("acceptWorkspaceInvitation", () => {
  test("calls accept_workspace_invitation RPC with invitation + accepter", async () => {
    mockRpc.mockResolvedValue({
      data: { ok: true, workspace_id: "ws", attestation_id: "att" },
      error: null,
    });
    const result = await acceptWorkspaceInvitation(INVITATION_ID, ACCEPTER_ID);
    expect(result).toEqual({ ok: true, workspaceId: "ws", attestationId: "att" });
    expect(mockRpc).toHaveBeenCalledWith("accept_workspace_invitation", {
      p_invitation_id: INVITATION_ID,
      p_accepter_user_id: ACCEPTER_ID,
    });
    expect(mockReportSilentFallback).not.toHaveBeenCalled();
  });

  test("transport error → {ok:false, reason:'rpc_failed'} + reportSilentFallback(error, ...)", async () => {
    const rpcError = { message: "boom", code: "P0001" };
    mockRpc.mockResolvedValue({ data: null, error: rpcError });
    const result = await acceptWorkspaceInvitation(INVITATION_ID, ACCEPTER_ID);
    expect(result).toEqual({ ok: false, reason: "rpc_failed" });
    expect(mockReportSilentFallback).toHaveBeenCalledTimes(1);
    // The RPC error object MUST be the first arg (not null) so sqlStateFromError
    // can emit the SQLSTATE as a `pg_code` Sentry tag.
    expect(mockReportSilentFallback).toHaveBeenCalledWith(
      rpcError,
      expect.objectContaining({ feature: "workspace-invitations", op: "accept" }),
    );
  });

  test("passes terminal-state reason through without paging", async () => {
    mockRpc.mockResolvedValue({ data: { ok: false, reason: "revoked" }, error: null });
    const result = await acceptWorkspaceInvitation(INVITATION_ID, ACCEPTER_ID);
    expect(result).toEqual({ ok: false, reason: "revoked" });
    expect(mockReportSilentFallback).not.toHaveBeenCalled();
  });

  test("reasonless ok=false → reason:'unknown' + reportSilentFallback(null, ...)", async () => {
    mockRpc.mockResolvedValue({ data: { ok: false }, error: null });
    const result = await acceptWorkspaceInvitation(INVITATION_ID, ACCEPTER_ID);
    expect(result).toEqual({ ok: false, reason: "unknown" });
    expect(mockReportSilentFallback).toHaveBeenCalledTimes(1);
    expect(mockReportSilentFallback).toHaveBeenCalledWith(
      null,
      expect.objectContaining({ feature: "workspace-invitations", op: "accept" }),
    );
  });
});
