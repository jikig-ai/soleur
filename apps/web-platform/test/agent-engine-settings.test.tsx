import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { act, fireEvent, render, waitFor } from "@testing-library/react";
import { StrictMode } from "react";

import { AgentEngineSettings } from "@/components/settings/agent-engine-settings";

const fetchMock = vi.fn();

beforeEach(() => {
  vi.stubGlobal("fetch", fetchMock);
  fetchMock.mockResolvedValue({
    ok: true,
    json: async () => ({
      defaultEngineId: "claude-code",
      defaultAuthMode: "managed",
      engines: [
        { id: "claude-code", version: "claude-code-v1", transport: "local", authModes: ["managed"], enabledForNewRuns: true, rolloutEnabled: true },
        { id: "codex", version: "codex-v1", transport: "remote", authModes: ["managed"], enabledForNewRuns: false, rolloutEnabled: false },
      ],
    }),
  });
});

afterEach(() => vi.unstubAllGlobals());

describe("AgentEngineSettings", () => {
  const availableSettings = {
    defaultEngineId: "claude-code",
    defaultAuthMode: "managed",
    engines: [
      { id: "claude-code", version: "v1", transport: "local", authModes: ["managed", "api-key"], enabledForNewRuns: true, rolloutEnabled: true },
      { id: "codex", version: "v1", transport: "remote", authModes: ["api-key"], enabledForNewRuns: true, rolloutEnabled: true },
    ],
  };

  it("keeps the persisted engine and authentication mode when changing engines fails", async () => {
    fetchMock.mockResolvedValueOnce({ ok: true, json: async () => availableSettings });
    fetchMock.mockResolvedValueOnce({ ok: false });
    const view = render(<AgentEngineSettings isOwner />);
    fireEvent.click(await view.findByLabelText(/codex/));
    await view.findByRole("alert");
    expect(view.getByLabelText(/Claude Code/)).toBeChecked();
    expect(view.getByLabelText("Authentication mode")).toHaveValue("managed");
  });

  it("keeps the last successful auth mode after a later save rejects", async () => {
    fetchMock.mockResolvedValueOnce({ ok: true, json: async () => availableSettings });
    fetchMock.mockResolvedValueOnce({ ok: true });
    fetchMock.mockRejectedValueOnce(new Error("network unavailable"));
    const view = render(<AgentEngineSettings isOwner />);
    const mode = await view.findByLabelText("Authentication mode");
    fireEvent.change(mode, { target: { value: "api-key" } });
    await waitFor(() => expect(mode).not.toBeDisabled());
    expect(mode).toHaveValue("api-key");
    fireEvent.change(mode, { target: { value: "managed" } });
    await view.findByRole("alert");
    expect(mode).toHaveValue("api-key");
  });

  it("ignores an obsolete load response after newer settings have been saved", async () => {
    let finishOldLoad!: (response: unknown) => void;
    fetchMock.mockReturnValueOnce(new Promise((resolve) => { finishOldLoad = resolve; }));
    fetchMock.mockResolvedValueOnce({ ok: true, json: async () => availableSettings });
    fetchMock.mockResolvedValueOnce({ ok: true });
    const view = render(<StrictMode><AgentEngineSettings isOwner /></StrictMode>);
    fireEvent.click(await view.findByLabelText(/codex/));
    await waitFor(() => expect(view.getByLabelText(/codex/)).not.toBeDisabled());
    await act(async () => {
      finishOldLoad({ ok: true, json: async () => availableSettings });
    });
    expect(view.getByLabelText(/codex/)).toBeChecked();
    expect(view.getByLabelText("Authentication mode")).toHaveValue("api-key");
  });

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
          { id: "claude-code", version: "claude-code-v1", transport: "local", authModes: ["managed"], enabledForNewRuns: true, rolloutEnabled: true },
          { id: "codex", version: "codex-v1", transport: "remote", authModes: ["managed"], enabledForNewRuns: true, rolloutEnabled: false },
        ],
      }),
    });
    const { findByLabelText } = render(<AgentEngineSettings isOwner />);
    expect(await findByLabelText(/codex/)).toBeDisabled();
  });

  it("keeps legacy Claude payloads usable while missing rollout metadata stays fail-closed for future engines", async () => {
    fetchMock.mockResolvedValueOnce({
      ok: true,
      json: async () => ({
        defaultEngineId: "claude-code",
        engines: [
          { id: "claude-code", version: "claude-code-v1", transport: "local", authModes: ["managed"], enabledForNewRuns: true },
          { id: "grok-build", version: "grok-v1", transport: "remote", authModes: ["managed"], enabledForNewRuns: true },
        ],
      }),
    });
    const { findByLabelText } = render(<AgentEngineSettings isOwner />);
    expect(await findByLabelText(/Claude Code/)).not.toBeDisabled();
    expect(await findByLabelText(/grok-build/)).toBeDisabled();
  });

  it("keeps the auth selector disabled for a persisted Codex default while rollout is off", async () => {
    fetchMock.mockResolvedValueOnce({
      ok: true,
      json: async () => ({
        defaultEngineId: "codex",
        defaultAuthMode: "managed",
        engines: [
          { id: "claude-code", version: "claude-code-v1", transport: "local", authModes: ["managed"], enabledForNewRuns: true, rolloutEnabled: true },
          { id: "codex", version: "codex-v1", transport: "remote", authModes: ["managed", "api-key"], enabledForNewRuns: true, rolloutEnabled: false },
        ],
      }),
    });
    const { findByLabelText } = render(<AgentEngineSettings isOwner />);
    expect(await findByLabelText(/Authentication mode/)).toBeDisabled();
  });

  it("saves a changed default for an owner", async () => {
    fetchMock.mockResolvedValueOnce({
      ok: true,
      json: async () => ({
        defaultEngineId: "claude-code",
        engines: [
          { id: "claude-code", version: "claude-code-v1", transport: "local", authModes: ["managed"], enabledForNewRuns: true, rolloutEnabled: true },
          { id: "codex", version: "codex-v1", transport: "remote", authModes: ["managed"], enabledForNewRuns: true, rolloutEnabled: true },
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
        engines: [{ id: "claude-code", version: "v1", transport: "local", authModes: ["managed", "api-key"], enabledForNewRuns: true, rolloutEnabled: true }],
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

  it("discloses user-provider retention when api-key mode is selected", async () => {
    fetchMock.mockResolvedValueOnce({
      ok: true,
      json: async () => ({
        defaultEngineId: "claude-code",
        defaultAuthMode: "managed",
        engines: [{ id: "claude-code", version: "v1", transport: "local", authModes: ["managed", "api-key"], enabledForNewRuns: true, rolloutEnabled: true }],
      }),
    });
    const { findByLabelText, findByTestId } = render(<AgentEngineSettings isOwner />);
    const mode = await findByLabelText("Authentication mode");
    fireEvent.change(mode, { target: { value: "api-key" } });
    expect(await findByTestId("user-provider-disclosure")).toHaveTextContent("retention");
  });
});
