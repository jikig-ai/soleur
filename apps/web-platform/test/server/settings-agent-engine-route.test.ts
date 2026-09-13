import { beforeEach, describe, expect, it, vi } from "vitest";

const { getUser, getDefault, setDefault, workspace } = vi.hoisted(() => ({
  getUser: vi.fn(),
  getDefault: vi.fn(),
  setDefault: vi.fn(),
  workspace: vi.fn(),
}));

vi.mock("@/lib/supabase/server", () => ({
  createClient: async () => ({ auth: { getUser }, from: vi.fn() }),
}));
vi.mock("@/server/workspace-resolver", () => ({ readWorkspaceIdFromDb: workspace }));
vi.mock("@/server/agent-engine-persistence", () => ({
  AgentEnginePersistenceRepository: class {
    getDefaultEngine = getDefault;
    setDefaultEngine = setDefault;
  },
}));

import { GET, PUT } from "@/app/api/dashboard/settings/agent-engine/route";

function request(body?: unknown, origin?: string) {
  return new Request("https://soleur.ai/api/dashboard/settings/agent-engine", {
    method: "PUT",
    headers: { ...(origin ? { origin } : {}), "content-type": "application/json" },
    body: JSON.stringify(body ?? {}),
  });
}

beforeEach(() => {
  getUser.mockReset();
  getDefault.mockReset();
  setDefault.mockReset();
  workspace.mockReset();
  getUser.mockResolvedValue({ data: { user: { id: "user-1" } } });
  workspace.mockResolvedValue("ws-1");
  getDefault.mockResolvedValue("claude-code");
  setDefault.mockResolvedValue({ id: "setting-1" });
});

describe("agent engine settings route", () => {
  it("requires authentication", async () => {
    getUser.mockResolvedValue({ data: { user: null } });
    expect((await GET())!.status).toBe(401);
  });

  it("returns the workspace default and reviewed engines", async () => {
    const response = await GET();
    expect(response!.status).toBe(200);
    await expect(response!.json()).resolves.toEqual(expect.objectContaining({
      workspaceId: "ws-1", defaultEngineId: "claude-code",
    }));
  });

  it("writes a validated owner default", async () => {
    const response = await PUT(request({ engineId: "claude-code" }));
    expect(response!.status).toBe(200);
    expect(setDefault).toHaveBeenCalledWith("ws-1", "claude-code");
  });

  it("rejects unknown engines before the RPC", async () => {
    const response = await PUT(request({ engineId: "grok-build" }));
    expect(response!.status).toBe(400);
    expect(setDefault).not.toHaveBeenCalled();
  });

  it("rejects disabled engines before the RPC", async () => {
    const response = await PUT(request({ engineId: "codex" }));
    expect(response!.status).toBe(409);
    expect(setDefault).not.toHaveBeenCalled();
  });

  it("fails closed when the workspace binding is unavailable", async () => {
    workspace.mockResolvedValue(null);
    const response = await PUT(request({ engineId: "claude-code" }));
    expect(response!.status).toBe(503);
    expect(setDefault).not.toHaveBeenCalled();
  });

  it("sanitizes workspace resolver failures", async () => {
    workspace.mockRejectedValue(new Error("database unavailable"));
    const response = await GET();
    expect(response!.status).toBe(503);
    await expect(response!.json()).resolves.toEqual({ error: "settings_unavailable" });
  });

  it("maps owner RPC failures to a retryable settings error", async () => {
    setDefault.mockRejectedValue(new Error("permission denied"));
    const response = await PUT(request({ engineId: "claude-code" }));
    expect(response!.status).toBe(503);
    await expect(response!.json()).resolves.toEqual({ error: "settings_update_failed" });
  });
});
