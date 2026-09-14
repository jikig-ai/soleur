import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { fireEvent, render, waitFor } from "@testing-library/react";

const useOptionalFeatureFlagMock = vi.hoisted(() => vi.fn(() => false));
vi.mock("@/components/feature-flags/provider", () => ({
  useOptionalFeatureFlag: useOptionalFeatureFlagMock,
}));

import { AgentEngineSettings } from "@/components/settings/agent-engine-settings";

const fetchMock = vi.fn();

beforeEach(() => {
  vi.stubGlobal("fetch", fetchMock);
  useOptionalFeatureFlagMock.mockReset();
  useOptionalFeatureFlagMock.mockReturnValue(false);
  fetchMock.mockResolvedValue({
    ok: true,
    json: async () => ({
      defaultEngineId: "claude-code",
      defaultAuthMode: "managed",
      engines: [
        { id: "claude-code", version: "claude-code-v1", transport: "local", authModes: ["managed"], enabledForNewRuns: true },
        { id: "codex", version: "codex-v1", transport: "remote", authModes: ["managed"], enabledForNewRuns: false },
      ],
    }),
  });
});

afterEach(() => vi.unstubAllGlobals());

describe("AgentEngineSettings", () => {
  it("loads the workspace default and renders future engines as unavailable", async () => {
    const { findByLabelText } = render(<AgentEngineSettings isOwner />);
    const claude = await findByLabelText(/Claude Code/);
    expect((claude as HTMLInputElement).checked).toBe(true);
    expect((await findByLabelText(/codex/)) as HTMLInputElement).toBeDisabled();
  });

  it("keeps Codex unavailable when the rollout flag is off", async () => {
    fetchMock.mockResolvedValueOnce({
      ok: true,
      json: async () => ({
        defaultEngineId: "claude-code",
        engines: [
          { id: "claude-code", version: "claude-code-v1", transport: "local", authModes: ["managed"], enabledForNewRuns: true },
          { id: "codex", version: "codex-v1", transport: "remote", authModes: ["managed"], enabledForNewRuns: true },
        ],
      }),
    });
    const { findByLabelText } = render(<AgentEngineSettings isOwner />);
    expect(await findByLabelText(/codex/)).toBeDisabled();
  });

  it("saves a changed default for an owner", async () => {
    useOptionalFeatureFlagMock.mockReturnValue(true);
    fetchMock.mockResolvedValueOnce({
      ok: true,
      json: async () => ({
        defaultEngineId: "claude-code",
        engines: [
          { id: "claude-code", version: "claude-code-v1", transport: "local", authModes: ["managed"], enabledForNewRuns: true },
          { id: "codex", version: "codex-v1", transport: "remote", authModes: ["managed"], enabledForNewRuns: true },
        ],
      }),
    });
    const { findByLabelText } = render(<AgentEngineSettings isOwner />);
    const codex = await findByLabelText(/codex/);
    fireEvent.click(codex);
    await waitFor(() => expect(fetchMock).toHaveBeenCalledWith(
      "/api/dashboard/settings/agent-engine",
      expect.objectContaining({ method: "PUT", body: JSON.stringify({ engineId: "codex", authMode: "managed" }) }),
    ));
  });

  it("keeps the selector read-only for members", async () => {
    const { findByLabelText } = render(<AgentEngineSettings isOwner={false} />);
    expect(await findByLabelText(/Claude Code/)).toBeDisabled();
  });

  it("saves an owner auth-mode choice for the selected engine", async () => {
    fetchMock.mockResolvedValueOnce({
      ok: true,
      json: async () => ({
        defaultEngineId: "claude-code",
        defaultAuthMode: "managed",
        engines: [{ id: "claude-code", version: "v1", transport: "local", authModes: ["managed", "api-key"], enabledForNewRuns: true }],
      }),
    });
    const { findByLabelText } = render(<AgentEngineSettings isOwner />);
    const mode = await findByLabelText(/Authentication mode/);
    fireEvent.change(mode, { target: { value: "api-key" } });
    await waitFor(() => expect(fetchMock).toHaveBeenCalledWith(
      "/api/dashboard/settings/agent-engine",
      expect.objectContaining({ method: "PUT", body: JSON.stringify({ engineId: "claude-code", authMode: "api-key" }) }),
    ));
  });
});
