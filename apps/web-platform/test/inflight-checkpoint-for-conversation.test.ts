/**
 * #5356 — shared checkpoint helper `checkpointInflightWorkForConversation` (RED).
 *
 * Plan: knowledge-base/project/plans/2026-06-15-feat-cc-soleur-go-checkpoint-parity-plan.md
 *
 * Extracts the conversation-bound resolve + checkpoint + Sentry-mirror block
 * (currently inline in `agent-runner.ts`'s disconnect branch) into one helper
 * called by BOTH the legacy path and the cc dispatcher hook. The load-bearing
 * invariant (AC3): the checkpoint clone is resolved from the CONVERSATION's
 * bound `workspace_id` via `workspacePathForWorkspaceId`, never the mutable
 * active-workspace resolver. And it must never throw onto the close path (AC5).
 *
 * RED before GREEN per AGENTS.md `cq-write-failing-tests-before`.
 */
import { describe, it, expect, vi, beforeEach } from "vitest";

const { mockGetFreshTenantClient, mockWorkspacePathForWorkspaceId, mockReport } =
  vi.hoisted(() => ({
    mockGetFreshTenantClient: vi.fn(),
    mockWorkspacePathForWorkspaceId: vi.fn((id: string) => `/clones/${id}`),
    mockReport: vi.fn(),
  }));

vi.mock("@/lib/supabase/tenant", () => ({
  getFreshTenantClient: mockGetFreshTenantClient,
  RuntimeAuthError: class RuntimeAuthError extends Error {},
}));

vi.mock("@/server/workspace-resolver", () => ({
  workspacePathForWorkspaceId: mockWorkspacePathForWorkspaceId,
}));

vi.mock("@/server/observability", () => ({
  reportSilentFallback: mockReport,
}));

// Run the lock body inline; the real lock has no bearing on resolution wiring.
vi.mock("@/server/workspace-permission-lock", () => ({
  withWorkspacePermissionLock: (_path: string, fn: () => Promise<unknown>) =>
    fn(),
}));

vi.mock("@/server/logger", () => ({
  createChildLogger: () => ({
    info: vi.fn(),
    debug: vi.fn(),
    warn: vi.fn(),
    error: vi.fn(),
  }),
}));

import { checkpointInflightWorkForConversation } from "@/server/inflight-checkpoint";

/** A tenant client whose conversations SELECT returns `workspace_id`. */
function tenantReturning(workspaceId: string | null, error?: { message: string }) {
  return {
    from: vi.fn(() => ({
      select: vi.fn(() => ({
        eq: vi.fn(() => ({
          single: vi.fn(async () => ({
            data: workspaceId === null ? null : { workspace_id: workspaceId },
            error: error ?? null,
          })),
        })),
      })),
    })),
  };
}

describe("#5356 checkpointInflightWorkForConversation", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockWorkspacePathForWorkspaceId.mockImplementation((id: string) => `/clones/${id}`);
  });

  it("T4: resolves the clone from conversations.workspace_id (NOT the active resolver)", async () => {
    mockGetFreshTenantClient.mockResolvedValue(tenantReturning("ws-bound"));

    await checkpointInflightWorkForConversation("u-1", "conv-1");

    expect(mockGetFreshTenantClient).toHaveBeenCalledWith("u-1");
    // The conversation-bound workspace_id flows into the path resolver.
    expect(mockWorkspacePathForWorkspaceId).toHaveBeenCalledWith("ws-bound");
  });

  it("T5(resolve-throws): a getFreshTenantClient rejection never throws and mirrors to Sentry", async () => {
    mockGetFreshTenantClient.mockRejectedValue(new Error("RuntimeAuthError"));

    await expect(
      checkpointInflightWorkForConversation("u-2", "conv-2"),
    ).resolves.toBeUndefined();

    expect(mockReport).toHaveBeenCalledTimes(1);
    const [, ctx] = mockReport.mock.calls[0];
    expect(ctx).toMatchObject({
      feature: "inflight-checkpoint",
      op: "checkpoint-on-abort",
      // Legacy call site uses the default stage; a swap would silently
      // fragment the shared Sentry monitor.
      extra: { stage: "resolve-workspace-path" },
    });
  });

  it("T5(null-workspace): an unresolvable workspace_id never throws and mirrors to Sentry", async () => {
    mockGetFreshTenantClient.mockResolvedValue(tenantReturning(null));

    await expect(
      checkpointInflightWorkForConversation("u-3", "conv-3"),
    ).resolves.toBeUndefined();

    expect(mockReport).toHaveBeenCalledTimes(1);
    // Never resolved a path — the active resolver is never consulted.
    expect(mockWorkspacePathForWorkspaceId).not.toHaveBeenCalled();
  });
});
