import { describe, it, expect, beforeEach, vi } from "vitest";

const { mockRemove, mockReport } = vi.hoisted(() => ({
  mockRemove: vi.fn(),
  mockReport: vi.fn(),
}));

vi.mock("@/server/observability", async () => {
  const actual = await vi.importActual<typeof import("@/server/observability")>(
    "@/server/observability",
  );
  return { ...actual, reportSilentFallback: mockReport };
});

import { purgeWorkspaceLogoObjects } from "@/server/workspace";

const WS = "66666666-6666-6666-6666-666666666666";

function service() {
  return { storage: { from: () => ({ remove: mockRemove }) } };
}

beforeEach(() => {
  vi.clearAllMocks();
  mockRemove.mockResolvedValue({ error: null });
});

describe("purgeWorkspaceLogoObjects (#4916 — sole-owned account-delete teardown)", () => {
  it("removes the deterministic logo object key via the Storage API", async () => {
    await purgeWorkspaceLogoObjects(WS, service() as never);
    expect(mockRemove).toHaveBeenCalledWith([`${WS}/logo.webp`]);
  });

  it("reports (does not throw) when the remove fails", async () => {
    mockRemove.mockResolvedValue({ error: { message: "remove failed" } });
    await expect(purgeWorkspaceLogoObjects(WS, service() as never)).resolves.toBeUndefined();
    expect(mockReport).toHaveBeenCalled();
  });
});
