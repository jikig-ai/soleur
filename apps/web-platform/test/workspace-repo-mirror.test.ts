import { describe, it, expect, vi, beforeEach } from "vitest";

vi.mock("@/server/observability", () => ({
  reportSilentFallback: vi.fn(),
}));

import { mirrorRepoColsToSoloWorkspace } from "@/server/workspace-repo-mirror";

function makeService(error: unknown = null) {
  const eq = vi.fn(async () => ({ error }));
  const update = vi.fn(() => ({ eq }));
  const from = vi.fn(() => ({ update }));
  return { client: { from }, from, update, eq };
}

describe("mirrorRepoColsToSoloWorkspace", () => {
  beforeEach(() => vi.clearAllMocks());

  it("writes the moved cols to workspaces WHERE id = userId (solo workspace)", async () => {
    const svc = makeService();
    await mirrorRepoColsToSoloWorkspace(svc.client, "user-1", {
      repo_url: "https://github.com/foo/bar",
      github_installation_id: 42,
      repo_status: "cloning",
    });
    expect(svc.from).toHaveBeenCalledWith("workspaces");
    expect(svc.update).toHaveBeenCalledWith({
      repo_url: "https://github.com/foo/bar",
      github_installation_id: 42,
      repo_status: "cloning",
    });
    expect(svc.eq).toHaveBeenCalledWith("id", "user-1");
  });

  it("mirrors a disconnect (all moved cols nulled)", async () => {
    const svc = makeService();
    await mirrorRepoColsToSoloWorkspace(svc.client, "user-1", {
      github_installation_id: null,
      repo_url: null,
      repo_status: "not_connected",
      repo_last_synced_at: null,
    });
    expect(svc.update).toHaveBeenCalledWith({
      github_installation_id: null,
      repo_url: null,
      repo_status: "not_connected",
      repo_last_synced_at: null,
    });
  });

  it("Sentry-mirrors on error without throwing (users write stays authoritative)", async () => {
    const { reportSilentFallback } = await import("@/server/observability");
    const svc = makeService({ message: "boom" });
    await expect(
      mirrorRepoColsToSoloWorkspace(svc.client, "user-1", { repo_status: "error" }),
    ).resolves.toBeUndefined();
    expect(reportSilentFallback).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({ feature: "workspace-repo-mirror" }),
    );
  });
});
