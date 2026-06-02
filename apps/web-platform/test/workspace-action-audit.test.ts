import { describe, it, expect, vi, beforeEach } from "vitest";

vi.mock("@/server/logger", () => ({ default: { info: vi.fn() } }));

import logger from "@/server/logger";
import { emitWorkspaceActionContext } from "@/server/workspace-action-audit";

const infoMock = logger.info as unknown as ReturnType<typeof vi.fn>;

describe("emitWorkspaceActionContext — AC11 wrong-workspace detector", () => {
  beforeEach(() => vi.clearAllMocks());

  it("emits a structured action-context event with workspace + hashed (non-raw) actor", () => {
    emitWorkspaceActionContext({
      action: "invite-member",
      userId: "user-123",
      workspaceId: "ws-abc",
      organizationId: "org-xyz",
    });
    expect(infoMock).toHaveBeenCalledTimes(1);
    const [payload, msg] = infoMock.mock.calls[0];
    expect(payload.event).toBe("workspace_action_context");
    expect(payload.action).toBe("invite-member");
    expect(payload.workspaceId).toBe("ws-abc");
    expect(payload.organizationId).toBe("org-xyz");
    // PII-safe: the raw user id never appears; actor is a hash string.
    expect(payload.actor).not.toBe("user-123");
    expect(typeof payload.actor).toBe("string");
    expect(payload.actor.length).toBeGreaterThan(0);
    expect(msg).toContain("invite-member");
  });

  it("covers all three tenant-sensitive actions and defaults org to null", () => {
    for (const action of ["invite-member", "api-key-share", "scope-grant"] as const) {
      infoMock.mockClear();
      emitWorkspaceActionContext({ action, userId: "u", workspaceId: "ws" });
      const [payload] = infoMock.mock.calls[0];
      expect(payload.action).toBe(action);
      expect(payload.organizationId).toBeNull();
    }
  });
});
