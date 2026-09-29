import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { act, fireEvent, render, waitFor } from "@testing-library/react";
import { StrictMode } from "react";

import { AgentEngineSettings } from "@/components/settings/agent-engine-settings";

const fetchMock = vi.fn();

beforeEach(() => {
  fetchMock.mockReset();
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
    fireEvent.change(await view.findByRole("combobox", { name: "Agent engine" }), { target: { value: "codex" } });
    await view.findByRole("alert");
    expect(view.getByRole("combobox", { name: "Agent engine" })).toHaveValue("claude-code");
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
    fireEvent.change(await view.findByRole("combobox", { name: "Agent engine" }), { target: { value: "codex" } });
    await waitFor(() => expect(view.getByRole("combobox", { name: "Agent engine" })).toHaveValue("codex"));
    await act(async () => {
      finishOldLoad({ ok: true, json: async () => availableSettings });
    });
    expect(view.getByRole("combobox", { name: "Agent engine" })).toHaveValue("codex");
    expect(view.getByLabelText("Authentication mode")).toHaveValue("api-key");
  });

  it("loads the workspace default and renders future engines as unavailable", async () => {
    const { findByLabelText } = render(<AgentEngineSettings isOwner />);
    const engine = await findByLabelText("Agent engine");
    await waitFor(() => expect(engine).toHaveValue("claude-code"));
    expect(viewOptionDisabled(engine, "codex")).toBe(true);
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
    const engine = await findByLabelText("Agent engine");
    expect(viewOptionDisabled(engine, "codex")).toBe(true);
  });

  it("lets an owner configure Codex while execution rollout remains disabled", async () => {
    fetchMock.mockResolvedValueOnce({
      ok: true,
      json: async () => ({
        defaultEngineId: "claude-code",
        engines: [
          { id: "claude-code", version: "claude-code-v1", transport: "local", authModes: ["managed"], enabledForNewRuns: true, rolloutEnabled: true },
          { id: "codex", version: "codex-v1", transport: "remote", authModes: ["managed", "api-key"], enabledForNewRuns: false, settingsSelectable: true, rolloutEnabled: false },
        ],
      }),
    });
    const view = render(<AgentEngineSettings isOwner />);
    const engine = await view.findByLabelText("Agent engine");
    expect(viewOptionDisabled(engine, "codex")).toBe(false);
    fireEvent.change(engine, { target: { value: "codex" } });
    expect(engine).toHaveValue("codex");
    expect(view.getByTestId("workspace-default-engine")).toHaveTextContent("Workspace default for new conversations: Claude Code");
    expect(fetchMock).toHaveBeenCalledTimes(1);
    expect(view.getByRole("status")).toHaveTextContent("Workspace default remains Claude Code");
  });

  it("restores the saved Codex mode when opening Codex settings", async () => {
    fetchMock.mockResolvedValueOnce({
      ok: true,
      json: async () => ({
        ...availableSettings,
        codexAuthMode: "api-key",
        engines: availableSettings.engines.map((engine) => engine.id === "codex"
          ? { ...engine, authModes: ["managed", "api-key"], enabledForNewRuns: false, settingsSelectable: true, rolloutEnabled: false }
          : engine),
      }),
    });
    const view = render(<AgentEngineSettings isOwner />);
    const engine = await view.findByLabelText("Agent engine");
    fireEvent.change(engine, { target: { value: "codex" } });
    expect(await view.findByLabelText("Authentication mode")).toHaveValue("api-key");
  });

  it("keeps each engine's saved auth mode when browsing Codex settings", async () => {
    fetchMock.mockResolvedValueOnce({
      ok: true,
      json: async () => ({
        ...availableSettings,
        defaultAuthMode: "api-key",
        codexAuthMode: "managed",
        engines: availableSettings.engines.map((engine) => engine.id === "codex"
          ? { ...engine, authModes: ["managed", "api-key"], enabledForNewRuns: false, settingsSelectable: true, rolloutEnabled: false }
          : engine),
      }),
    });
    fetchMock.mockResolvedValueOnce({ ok: true });

    const view = render(<AgentEngineSettings isOwner />);
    const engine = await view.findByLabelText("Agent engine");
    const mode = view.getByLabelText("Authentication mode");

    expect(mode).toHaveValue("api-key");
    fireEvent.change(engine, { target: { value: "codex" } });
    expect(mode).toHaveValue("managed");
    fireEvent.change(engine, { target: { value: "claude-code" } });

    await waitFor(() => expect(fetchMock).toHaveBeenCalledWith(
      "/api/dashboard/settings/agent-engine",
      expect.objectContaining({
        method: "PUT",
        body: JSON.stringify({ engineId: "claude-code", authMode: "api-key", applyToExistingCodexConversations: false }),
      }),
    ));
    expect(mode).toHaveValue("api-key");
    expect(fetchMock.mock.calls.filter(([, options]) => options?.method === "PUT").map(([, options]) => options?.body))
      .not.toContain(JSON.stringify({ engineId: "claude-code", authMode: "managed", applyToExistingCodexConversations: false }));
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
    const engine = await findByLabelText("Agent engine");
    expect(engine).not.toBeDisabled();
    expect(viewOptionDisabled(engine, "grok-build")).toBe(true);
  });

  it("allows owner auth settings for a persisted Codex default while execution rollout is off", async () => {
    fetchMock.mockResolvedValueOnce({
      ok: true,
      json: async () => ({
        defaultEngineId: "codex",
        defaultAuthMode: "managed",
        engines: [
          { id: "claude-code", version: "claude-code-v1", transport: "local", authModes: ["managed"], enabledForNewRuns: true, rolloutEnabled: true },
          { id: "codex", version: "codex-v1", transport: "remote", authModes: ["managed", "api-key"], enabledForNewRuns: false, settingsSelectable: true, rolloutEnabled: false },
        ],
      }),
    });
    const { findByLabelText } = render(<AgentEngineSettings isOwner />);
    expect(await findByLabelText("Authentication mode")).not.toBeDisabled();
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
    const engine = await findByLabelText("Agent engine");
    fireEvent.change(engine, { target: { value: "codex" } });
    await waitFor(() => expect(fetchMock).toHaveBeenCalledWith(
      "/api/dashboard/settings/agent-engine",
      expect.objectContaining({ method: "PUT", body: JSON.stringify({ engineId: "codex", authMode: "managed", applyToExistingCodexConversations: false }) }),
    ));
  });

  it("keeps the selector read-only for members", async () => {
    const { findByLabelText } = render(<AgentEngineSettings isOwner={false} />);
    expect(await findByLabelText("Agent engine")).toBeDisabled();
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
      expect.objectContaining({ method: "PUT", body: JSON.stringify({ engineId: "claude-code", authMode: "api-key", applyToExistingCodexConversations: false }) }),
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
    expect(await findByTestId("user-provider-disclosure")).toHaveTextContent(/history|retention/i);
  });

  it("marks only an explicit Codex auth-mode choice as applying to existing conversations", async () => {
    fetchMock.mockResolvedValueOnce({ ok: true, json: async () => ({
      ...availableSettings,
      defaultEngineId: "codex",
      defaultAuthMode: "managed",
      engines: availableSettings.engines.map((engine) => engine.id === "codex"
        ? { ...engine, authModes: ["managed", "api-key"] }
        : engine),
    }) });
    fetchMock.mockResolvedValueOnce({ ok: true, json: async () => ({ affectedConversationCount: 3 }) });
    const view = render(<AgentEngineSettings isOwner />);
    const mode = await view.findByLabelText("Authentication mode");
    fireEvent.change(mode, { target: { value: "api-key" } });
    const confirm = await view.findByRole("button", { name: "Apply to existing Codex conversations" });
    fireEvent.click(confirm);
    await waitFor(() => expect(fetchMock).toHaveBeenLastCalledWith(
      "/api/dashboard/settings/agent-engine",
      expect.objectContaining({
        method: "PUT",
        body: JSON.stringify({
          engineId: "codex",
          authMode: "api-key",
          applyToExistingCodexConversations: true,
          expectedAffectedConversationCount: 3,
        }),
      }),
    ));
  });
});

function viewOptionDisabled(select: HTMLElement, value: string): boolean {
  return (select.querySelector(`option[value="${value}"]`) as HTMLOptionElement | null)?.disabled ?? false;
}
