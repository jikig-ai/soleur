import { beforeEach, describe, expect, it, vi } from "vitest";

const getRuntimeFlag = vi.fn();
const warn = vi.fn();
vi.mock("@/lib/feature-flags/server", () => ({ getRuntimeFlag: (...a: unknown[]) => getRuntimeFlag(...a) }));
vi.mock("@/server/observability", () => ({ warnSilentFallback: (...a: unknown[]) => warn(...a), reportSilentFallback: vi.fn() }));
vi.mock("@/server/logger", () => {
  const log = { info: vi.fn(), warn: vi.fn(), error: vi.fn(), debug: vi.fn() };
  return { default: log, createChildLogger: () => log };
});

import { isApprovalQueueEnabled, resetFlagReadFailureReport } from "@/server/approval/flag";

describe("isApprovalQueueEnabled", () => {
  beforeEach(() => {
    getRuntimeFlag.mockReset();
    warn.mockReset();
    resetFlagReadFailureReport();
  });

  it("reads the approval-queue flag with the workspace as the segment identity", async () => {
    getRuntimeFlag.mockResolvedValue(true);
    await expect(isApprovalQueueEnabled({ userId: "u1", workspaceId: "w1" })).resolves.toBe(true);
    expect(getRuntimeFlag).toHaveBeenCalledWith("approval-queue", expect.objectContaining({ userId: "u1", orgId: "w1" }));
  });

  it("is OFF when the flag read says off", async () => {
    getRuntimeFlag.mockResolvedValue(false);
    await expect(isApprovalQueueEnabled({ userId: "u1", workspaceId: null })).resolves.toBe(false);
  });

  it("fails closed when the flag read throws", async () => {
    getRuntimeFlag.mockImplementation(async () => {
      throw new Error("flagsmith down");
    });
    const result = await isApprovalQueueEnabled({ userId: "u1", workspaceId: "w1" });
    expect(result).toBe(false);
  });

  it("a read failure is mirrored to Sentry ONCE per debounce window, tagged, with the static message; later failures in the window stay quiet", async () => {
    getRuntimeFlag.mockImplementation(async () => {
      throw new Error("flagsmith down");
    });
    for (let i = 0; i < 3; i++) await expect(isApprovalQueueEnabled({ userId: "u1", workspaceId: "w1" })).resolves.toBe(false);
    expect(warn).toHaveBeenCalledTimes(1);
    expect(warn.mock.calls[0][1]).toMatchObject({ feature: "approval-queue", op: "approval-flag-read-failed" });
    expect(warn.mock.calls[0][0]).toBeNull(); // never the Error object
  });

  it("a clean read reports nothing", async () => {
    getRuntimeFlag.mockResolvedValue(false);
    await isApprovalQueueEnabled({ userId: "u1", workspaceId: "w1" });
    expect(warn).not.toHaveBeenCalled();
  });
});
