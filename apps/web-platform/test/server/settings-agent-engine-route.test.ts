import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

const { getUser, getDefault, getAuthMode, setDefault, workspace, identity } = vi.hoisted(() => ({
  getUser: vi.fn(),
  getDefault: vi.fn(),
  getAuthMode: vi.fn(),
  setDefault: vi.fn(),
  workspace: vi.fn(),
  identity: vi.fn(),
}));

vi.mock("@/lib/supabase/server", () => ({
  createClient: async () => ({ auth: { getUser }, from: vi.fn() }),
}));
vi.mock("@/server/workspace-resolver", () => ({ readWorkspaceIdFromDb: workspace }));
vi.mock("@/lib/feature-flags/identity", () => ({ resolveIdentity: identity }));
vi.mock("@/server/agent-engine-persistence", () => ({
  AgentEnginePersistenceRepository: class {
    getDefaultEngine = getDefault;
    getDefaultAuthMode = getAuthMode;
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
  getAuthMode.mockReset();
  setDefault.mockReset();
  workspace.mockReset();
  identity.mockReset();
  getUser.mockResolvedValue({ data: { user: { id: "user-1" } } });
  workspace.mockResolvedValue("ws-1");
  identity.mockResolvedValue({ userId: "user-1", role: "prd", orgId: "org-1" });
  getDefault.mockResolvedValue("claude-code");
  getAuthMode.mockResolvedValue("managed");
  setDefault.mockResolvedValue({ id: "setting-1" });
});

afterEach(() => vi.restoreAllMocks());

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
      defaultAuthMode: "managed",
      engines: expect.arrayContaining([
        expect.objectContaining({ id: "claude-code", rolloutEnabled: true }),
        expect.objectContaining({ id: "codex", rolloutEnabled: false }),
      ]),
    }));
  });

  it("writes a validated auth mode with the owner default", async () => {
    const response = await PUT(request({ engineId: "claude-code", authMode: "api-key" }));
    expect(response!.status).toBe(200);
    expect(setDefault).toHaveBeenCalledWith("ws-1", "claude-code", "api-key");
  });

  it("rejects unsupported auth modes before the RPC", async () => {
    const response = await PUT(request({ engineId: "claude-code", authMode: "device-code" }));
    expect(response!.status).toBe(400);
    expect(setDefault).not.toHaveBeenCalled();
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

  it("keeps Codex blocked by the rollout flag when a reviewed definition is enabled", async () => {
    const { reviewedEngineRegistry } = await import("@/server/agent-engine-reviewed-definitions");
    const originalGet = reviewedEngineRegistry.get.bind(reviewedEngineRegistry);
    vi.spyOn(reviewedEngineRegistry, "get").mockImplementation((engineId) =>
      engineId === "codex"
        ? {
            id: "codex",
            version: "codex-v1",
            transport: "remote",
            enabledForNewRuns: true,
            enabledForExistingRuns: true,
            authModes: ["managed", "api-key"],
            qualifications: [],
          }
        : originalGet(engineId),
    );
    const response = await PUT(request({ engineId: "codex", authMode: "managed" }));
    expect(response!.status).toBe(409);
    await expect(response!.json()).resolves.toEqual({ error: "engine_rollout_disabled" });
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

  it("maps owner authorization failures to a forbidden response", async () => {
    setDefault.mockRejectedValue(Object.assign(new Error("workspace default engine requires owner"), { code: "workspace_owner_required" }));
    const response = await PUT(request({ engineId: "claude-code" }));
    expect(response!.status).toBe(403);
    await expect(response!.json()).resolves.toEqual({ error: "workspace_owner_required" });
  });
});
