import { describe, it, expect, vi, beforeEach } from "vitest";

// #8211 quiet-window — the shared HTTP refusal used by POST /api/repo/setup and /api/repo/create.
// Contract: null (proceed) unless the kill-switch is on; then 503 + Retry-After + a stable `code` and the
// static maintenance message, nothing else (no ids, no internals); a throwing flag read fails OPEN.

const { mockIsPaused, mockLogInfo, mockInfoSilentFallback } = vi.hoisted(() => ({
  mockIsPaused: vi.fn(),
  mockInfoSilentFallback: vi.fn(),
  mockLogInfo: vi.fn(),
}));

vi.mock("@/lib/feature-flags/server", () => ({ isNewAgentSessionsPaused: mockIsPaused }));
vi.mock("@/server/observability", () => ({
  warnSilentFallback: vi.fn(),
  infoSilentFallback: mockInfoSilentFallback,
  reportSilentFallback: vi.fn(),
}));
vi.mock("@/server/userid-pseudonymize", () => ({
  hashUserIdValue: (id: string) => `h:${id}`,
}));
vi.mock("@/server/logger", () => ({
  default: { info: mockLogInfo, warn: vi.fn(), error: vi.fn(), debug: vi.fn() },
  createChildLogger: () => ({ info: vi.fn(), warn: vi.fn(), error: vi.fn(), debug: vi.fn() }),
}));

import { quietWindowRefusal } from "@/server/quiet-window-http";
import { QUIET_WINDOW_MESSAGE } from "@/server/quiet-window";
import { QUIET_WINDOW_CODE } from "@/lib/repo-connect-codes";

beforeEach(() => {
  vi.clearAllMocks();
});

describe("quietWindowRefusal", () => {
  it("flag off/absent -> null: the route proceeds", async () => {
    mockIsPaused.mockResolvedValue(false);
    await expect(quietWindowRefusal("repo-setup", "hash")).resolves.toBeNull();
    expect(mockLogInfo).not.toHaveBeenCalled();
  });

  it("flag on -> 503 with Retry-After, the stable code and the static message only", async () => {
    mockIsPaused.mockResolvedValue(true);
    const res = await quietWindowRefusal("repo-create", "hash");
    expect(res).not.toBeNull();
    expect(res!.status).toBe(503);
    expect(res!.headers.get("Retry-After")).toBe("300");
    expect(await res!.json()).toEqual({ error: QUIET_WINDOW_MESSAGE, code: QUIET_WINDOW_CODE });
  });

  it("logs an info breadcrumb with the surface and the pseudonymised id, never a raw id", async () => {
    mockIsPaused.mockResolvedValue(true);
    await quietWindowRefusal("repo-setup", "raw-user-1");
    expect(mockLogInfo).toHaveBeenCalledTimes(1);
    expect(mockLogInfo.mock.calls[0][0]).toMatchObject({
      feature: "quiet-window",
      surface: "repo-setup",
      userIdHash: "h:raw-user-1",
    });
  });

  it("the log breadcrumb never carries the raw id", async () => {
    mockIsPaused.mockResolvedValue(true);
    await quietWindowRefusal("repo-setup", "raw-user-1");
    expect(JSON.stringify(mockLogInfo.mock.calls[0][0])).not.toContain('"raw-user-1"');
  });

  it("the configured exempt account proceeds (null); another id is refused 503", async () => {
    const exempt = "0b8f6f1e-3c1d-4a53-9a55-5b6f7c8d9e01";
    const original = process.env.QUIET_WINDOW_EXEMPT_USER_ID;
    process.env.QUIET_WINDOW_EXEMPT_USER_ID = exempt;
    try {
      mockIsPaused.mockResolvedValue(true);
      await expect(quietWindowRefusal("repo-setup", exempt)).resolves.toBeNull();
      const res = await quietWindowRefusal("repo-setup", "1c9a7a2f-4d2e-4b64-8b66-6c7a8d9e0f12");
      expect(res!.status).toBe(503);
    } finally {
      if (original === undefined) delete process.env.QUIET_WINDOW_EXEMPT_USER_ID;
      else process.env.QUIET_WINDOW_EXEMPT_USER_ID = original;
    }
  });

  it("a throwing flag read fails OPEN (null)", async () => {
    mockIsPaused.mockRejectedValue(new Error("flagsmith down"));
    await expect(quietWindowRefusal("repo-setup", "hash")).resolves.toBeNull();
  });

  it("the code constant is the stable wire value the connect-repo page maps", () => {
    expect(QUIET_WINDOW_CODE).toBe("quiet_window");
  });
});
