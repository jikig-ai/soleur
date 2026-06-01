import { describe, it, expect, vi, beforeEach } from "vitest";
import { resolveNeedsReconnect } from "@/lib/repo-status";
import { resolveInstallationId } from "@/server/resolve-installation-id";

// `resolveNeedsReconnect` resolves the workspace-scoped install credential via
// a dynamic `import("@/server/resolve-installation-id")`. vitest intercepts the
// dynamic import too, so mocking the module controls the credential read.
vi.mock("@/server/resolve-installation-id", () => ({
  resolveInstallationId: vi.fn(),
}));

const mockResolve = vi.mocked(resolveInstallationId);

describe("resolveNeedsReconnect", () => {
  beforeEach(() => {
    mockResolve.mockReset();
  });

  // AC1 — ready + NULL user column but a resolvable workspace install → the
  // workspace IS connected (org/workspace-shared install, ADR-044), so the
  // banner must NOT show. This is the bug: sync resumes via the workspace
  // credential while the old predicate read the always-NULL user column.
  it("is false for ready + null user install when workspace credential resolves", async () => {
    mockResolve.mockResolvedValue(987654);
    expect(await resolveNeedsReconnect("ready", null, "user-1")).toBe(false);
    expect(mockResolve).toHaveBeenCalledWith("user-1");
  });

  // AC2 — ready + NULL user column AND no resolvable workspace install → the
  // genuine #4706 silent-freeze class. The banner MUST still appear.
  // (verify-the-negative: the fix must not blind the alarm it backstops.)
  it("is true for ready + null user install when no workspace credential resolves", async () => {
    mockResolve.mockResolvedValue(null);
    expect(await resolveNeedsReconnect("ready", null, "user-1")).toBe(true);
    expect(mockResolve).toHaveBeenCalledWith("user-1");
  });

  it("is true for ready + undefined user install when no workspace credential resolves", async () => {
    mockResolve.mockResolvedValue(null);
    expect(await resolveNeedsReconnect("ready", undefined, "user-1")).toBe(true);
    // undefined must reach the RPC just like null — a regression that
    // short-circuits undefined before the RPC would skip the alarm check.
    expect(mockResolve).toHaveBeenCalledWith("user-1");
  });

  // Fail-loud contract: resolveInstallationId swallows the EXPECTED failures to
  // null itself (covered above), but a truly unexpected throw must propagate —
  // not be caught and swallowed to false (which would hide the #4706 freeze).
  it("propagates an unexpected credential-read rejection (fails loud, not swallowed to false)", async () => {
    mockResolve.mockRejectedValue(new Error("unexpected RPC failure"));
    await expect(resolveNeedsReconnect("ready", null, "user-1")).rejects.toThrow(
      "unexpected RPC failure",
    );
  });

  // AC3 — personal install set on the user column → connected, and the cheap
  // path short-circuits BEFORE the RPC (no redundant DB round-trip on the
  // common path).
  it("is false for ready + non-null user install WITHOUT resolving the workspace credential", async () => {
    expect(await resolveNeedsReconnect("ready", 12345, "user-1")).toBe(false);
    expect(mockResolve).not.toHaveBeenCalled();
  });

  it("is false for ready + bigint user install without resolving the workspace credential", async () => {
    expect(await resolveNeedsReconnect("ready", 12345n, "user-1")).toBe(false);
    expect(mockResolve).not.toHaveBeenCalled();
  });

  // AC4 — non-ready statuses short-circuit to false with no RPC, mirroring the
  // pure predicate's existing contract. it.each so a regression on a single
  // status reports the offending value rather than a bundled failure.
  it.each(["not_connected", "error", "cloning"])(
    "is false for non-ready status %s without resolving the workspace credential",
    async (status) => {
      expect(await resolveNeedsReconnect(status, null, "user-1")).toBe(false);
      expect(mockResolve).not.toHaveBeenCalled();
    },
  );

  it("is false for null repoStatus without resolving the workspace credential", async () => {
    expect(await resolveNeedsReconnect(null, null, "user-1")).toBe(false);
    expect(mockResolve).not.toHaveBeenCalled();
  });
});
