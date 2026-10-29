import { beforeEach, describe, expect, it, vi } from "vitest";

const getRuntimeFlag = vi.fn();
vi.mock("@/lib/feature-flags/server", () => ({ getRuntimeFlag: (...a: unknown[]) => getRuntimeFlag(...a) }));

import { isApprovalQueueEnabled } from "@/server/approval/flag";

describe("isApprovalQueueEnabled", () => {
  beforeEach(() => {
    getRuntimeFlag.mockReset();
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
});
