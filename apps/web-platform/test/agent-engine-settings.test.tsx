import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { act, fireEvent, render, waitFor } from "@testing-library/react";
import { StrictMode } from "react";

import { AgentEngineSettings, authModeLabel } from "@/components/settings/agent-engine-settings";
import { authFailureCopy } from "@/server/agent-auth-user-message";

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
    const engine = await view.findByRole("combobox", { name: "Agent engine" });
    await waitFor(() => expect(engine).not.toBeDisabled());
    fireEvent.change(engine, { target: { value: "codex" } });
    await view.findByRole("alert");
    expect(view.getByRole("combobox", { name: "Agent engine" })).toHaveValue("claude-code");
    expect(view.getByLabelText("Authentication mode")).toHaveValue("managed");
  });

  it("keeps the last successful auth mode after a later save rejects", async () => {
    fetchMock.mockResolvedValueOnce({ ok: true, json: async () => availableSettings });
    fetchMock.mockResolvedValueOnce({ ok: true });
    fetchMock.mockRejectedValueOnce(new Error("network unavailable"));
    fetchMock.mockResolvedValueOnce({ ok: true, json: async () => ({ ...availableSettings, defaultAuthMode: "api-key" }) });
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
        defaultEngineId: "codex",
        defaultAuthMode: "api-key",
        engines: [{ id: "codex", version: "v1", transport: "remote", authModes: ["managed", "api-key"], enabledForNewRuns: true, rolloutEnabled: true }],
      }),
    });
    const { findByLabelText, findByTestId } = render(<AgentEngineSettings isOwner />);
    await findByLabelText("Authentication mode");
    const disclosure = await findByTestId("user-provider-disclosure");
    expect(disclosure).toHaveTextContent(/history|retention/i);
    expect(disclosure).toHaveTextContent("Saved conversation history is not transferred");
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
    expect(view.getByRole("alertdialog")).toHaveTextContent("Requested authentication mode: API key.");
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

  it("rereads committed Codex settings after the save response is lost", async () => {
    const initial = {
      ...availableSettings, codexAuthMode: "managed",
      engines: availableSettings.engines.map((engine) => engine.id === "codex"
        ? { ...engine, authModes: ["managed", "api-key"], enabledForNewRuns: false, settingsSelectable: true }
        : engine),
    };
    fetchMock.mockResolvedValueOnce({ ok: true, json: async () => initial });
    fetchMock.mockResolvedValueOnce({ ok: true, json: async () => ({ affectedConversationCount: 2 }) });
    fetchMock.mockRejectedValueOnce(new Error("Synthetic committed response loss"));
    fetchMock.mockResolvedValueOnce({ ok: true, json: async () => ({ ...initial, codexAuthMode: "api-key" }) });
    const view = render(<AgentEngineSettings isOwner />);
    fireEvent.change(await view.findByLabelText("Agent engine"), { target: { value: "codex" } });
    fireEvent.change(view.getByLabelText("Authentication mode"), { target: { value: "api-key" } });
    fireEvent.click(await view.findByRole("button", { name: "Apply to existing Codex conversations" }));
    const alert = await view.findByRole("alert");
    expect(alert).toHaveTextContent("Current settings have been refreshed");
    expect(alert).not.toHaveTextContent("previous selection is still active");
    expect(view.getByLabelText("Agent engine")).toHaveValue("codex");
    expect(view.getByLabelText("Authentication mode")).toHaveValue("api-key");
    expect(view.getByTestId("workspace-default-engine")).toHaveTextContent("Claude Code");
    expect(fetchMock.mock.calls.filter(([, options]) => options?.method === "PUT")).toHaveLength(1);
  });

  it("blocks further changes when neither the save nor authoritative reread can be confirmed", async () => {
    fetchMock.mockResolvedValueOnce({ ok: true, json: async () => availableSettings });
    fetchMock.mockRejectedValueOnce(new Error("Synthetic lost save response"));
    fetchMock.mockRejectedValueOnce(new Error("Synthetic unavailable authoritative reread"));
    const view = render(<AgentEngineSettings isOwner />);
    fireEvent.change(await view.findByLabelText("Authentication mode"), { target: { value: "api-key" } });
    expect(await view.findByRole("alert")).toHaveTextContent("Reload settings before making another change");
    expect(view.getByLabelText("Agent engine")).toBeDisabled();
    expect(view.getByLabelText("Authentication mode")).toBeDisabled();
    expect(fetchMock.mock.calls.filter(([, options]) => options?.method === "PUT")).toHaveLength(1);
  });

  describe("#11591 — option labels, helper and disclosure", () => {
    const claudeOnly = {
      defaultEngineId: "claude-code",
      defaultAuthMode: "managed",
      engines: [{ id: "claude-code", version: "v1", transport: "local", authModes: ["managed", "api-key"], enabledForNewRuns: true, rolloutEnabled: true }],
    };

    it("shows Automatic / My API key while the stored values stay managed / api-key", async () => {
      fetchMock.mockResolvedValueOnce({ ok: true, json: async () => claudeOnly });
      const { findByLabelText } = render(<AgentEngineSettings isOwner />);
      const mode = (await findByLabelText("Authentication mode")) as HTMLSelectElement;
      expect(Array.from(mode.options).map((o) => [o.value, o.textContent])).toEqual([
        ["managed", "Automatic"],
        ["api-key", "My API key"],
      ]);
      expect(await findByLabelText("Agent engine")).toHaveValue("claude-code");
    });

    it("helper line for the Claude engine says new conversations and names no subscription", async () => {
      fetchMock.mockResolvedValueOnce({ ok: true, json: async () => claudeOnly });
      const { findByTestId } = render(<AgentEngineSettings isOwner />);
      const helper = await findByTestId("auth-mode-helper");
      expect(helper).toHaveTextContent("Applies to new conversations.");
      expect(helper.textContent ?? "").not.toMatch(/subscription/i);
    });

    it("the amber disclosure shows under BOTH modes for Claude, and the select is described by both notes", async () => {
      fetchMock.mockResolvedValueOnce({ ok: true, json: async () => claudeOnly });
      const { findByLabelText, findByTestId, queryByTestId } = render(<AgentEngineSettings isOwner />);
      const mode = await findByLabelText("Authentication mode");
      expect(await findByTestId("user-provider-disclosure")).toBeTruthy();
      expect(mode.getAttribute("aria-describedby")).toBe("auth-mode-helper user-provider-disclosure");
      fireEvent.change(mode, { target: { value: "api-key" } });
      expect(queryByTestId("user-provider-disclosure")).toBeTruthy();
    });

    it("the helper and disclosure sit OUTSIDE the label, so the select's accessible name stays just the title", async () => {
      fetchMock.mockResolvedValueOnce({ ok: true, json: async () => claudeOnly });
      const { findByLabelText, findByTestId } = render(<AgentEngineSettings isOwner />);
      await findByLabelText("Authentication mode");
      expect((await findByTestId("auth-mode-helper")).closest("label")).toBeNull();
      expect((await findByTestId("user-provider-disclosure")).closest("label")).toBeNull();
    });

    it("another engine keeps raw mode strings, no helper, and the disclosure only under api-key", async () => {
      fetchMock.mockResolvedValueOnce({
        ok: true,
        json: async () => ({
          defaultEngineId: "codex",
          defaultAuthMode: "managed",
          engines: [
            { id: "claude-code", version: "v1", transport: "local", authModes: ["managed", "api-key"], enabledForNewRuns: true, rolloutEnabled: true },
            { id: "codex", version: "v1", transport: "remote", authModes: ["managed", "api-key"], enabledForNewRuns: true, rolloutEnabled: true },
          ],
        }),
      });
      fetchMock.mockResolvedValueOnce({ ok: true, json: async () => ({ affectedConversationCount: 1 }) });
      const { findByLabelText, queryByTestId, findByRole } = render(<AgentEngineSettings isOwner />);
      const mode = (await findByLabelText("Authentication mode")) as HTMLSelectElement;
      expect(Array.from(mode.options).map((o) => o.textContent)).toEqual(["managed", "api-key"]);
      expect(queryByTestId("auth-mode-helper")).toBeNull();
      expect(queryByTestId("user-provider-disclosure")).toBeNull();
      expect(mode.getAttribute("aria-describedby")).toBeNull();
      fireEvent.change(mode, { target: { value: "api-key" } });
      expect(await findByRole("alertdialog")).toHaveTextContent("1 existing Codex conversation");
      expect(mode.value).toBe("managed");
      expect(queryByTestId("user-provider-disclosure")).toBeNull();
    });
  });

  // #11599 — the helper line and the amber disclosure are tuned for non-owner viewers (CLO-approved text, 2026-10-31):
  // the owner render is byte-identical, a non-owner is not told things that are false for them, and the disclosure is kept.
  describe("#11599 — non-owner copy", () => {
    const claudeOnly = {
      defaultEngineId: "claude-code",
      defaultAuthMode: "managed",
      engines: [{ id: "claude-code", version: "v1", transport: "local", authModes: ["managed", "api-key"], enabledForNewRuns: true, rolloutEnabled: true }],
    };
    const OWNER_HELPER =
      "Applies to new conversations. Existing conversations keep the mode they started with. Automatic uses the credential saved to your account; My API key uses your saved API key.";
    const OWNER_DISCLOSURE =
      "This uses your own provider account. Prompts, files, and outputs sent through this engine are subject to that provider's retention, region, and account terms. Soleur-managed provider access remains restricted. Only submit data you are authorized to share with the provider.";
    const NON_OWNER_HELPER =
      "This setting is chosen by the workspace owner. It applies to new conversations; existing conversations keep the mode they started with.";
    const NON_OWNER_DISCLOSURE =
      "Conversations in this workspace use a provider account saved by you or by another workspace member. Prompts, files, and outputs sent through this engine are subject to that provider's retention, region, and account terms, and to the account holder's own settings and access. Soleur-managed provider access remains restricted. Only submit data you are authorized to share with the provider.";
    const text = (el: HTMLElement) => (el.textContent ?? "").replace(/\s+/g, " ").trim();

    it("owner render is byte-identical: the original helper and disclosure text", async () => {
      fetchMock.mockResolvedValueOnce({ ok: true, json: async () => claudeOnly });
      const { findByTestId } = render(<AgentEngineSettings isOwner />);
      expect(text(await findByTestId("auth-mode-helper"))).toBe(OWNER_HELPER);
      expect(text(await findByTestId("user-provider-disclosure"))).toBe(OWNER_DISCLOSURE);
    });

    it("a non-owner sees the CLO-approved helper line and disclosure; ids, role and describedby are unchanged", async () => {
      fetchMock.mockResolvedValueOnce({ ok: true, json: async () => claudeOnly });
      const { findByTestId, findByLabelText } = render(<AgentEngineSettings isOwner={false} />);
      const helper = await findByTestId("auth-mode-helper");
      const disclosure = await findByTestId("user-provider-disclosure");
      expect(text(helper)).toBe(NON_OWNER_HELPER);
      expect(text(disclosure)).toBe(NON_OWNER_DISCLOSURE);
      expect(helper.id).toBe("auth-mode-helper");
      expect(disclosure.id).toBe("user-provider-disclosure");
      // Kept, not hidden: still the amber note.
      expect(disclosure.getAttribute("role")).toBe("note");
      const mode = await findByLabelText("Authentication mode");
      expect(mode.getAttribute("aria-describedby")).toBe("auth-mode-helper user-provider-disclosure");
    });

    it("no non-owner text names a subscription or claims the viewer's own account, and the controls stay disabled", async () => {
      fetchMock.mockResolvedValueOnce({ ok: true, json: async () => claudeOnly });
      const { findByTestId, findByLabelText } = render(<AgentEngineSettings isOwner={false} />);
      const all = text(await findByTestId("auth-mode-helper")) + text(await findByTestId("user-provider-disclosure"));
      expect(all).not.toMatch(/subscription/i);
      expect(all).not.toMatch(/your own provider account|your saved API key|saved to your account/i);
      expect(await findByLabelText("Authentication mode")).toBeDisabled();
      expect(await findByLabelText("Agent engine")).toBeDisabled();
    });

    it("another engine under api-key keeps the single disclosure element, with the non-owner text for a non-owner", async () => {
      fetchMock.mockResolvedValueOnce({
        ok: true,
        json: async () => ({
          defaultEngineId: "codex",
          defaultAuthMode: "api-key",
          engines: [
            { id: "claude-code", version: "v1", transport: "local", authModes: ["managed", "api-key"], enabledForNewRuns: true, rolloutEnabled: true },
            { id: "codex", version: "v1", transport: "remote", authModes: ["managed", "api-key"], enabledForNewRuns: true, rolloutEnabled: true },
          ],
        }),
      });
      const { findByTestId } = render(<AgentEngineSettings isOwner={false} />);
      const disclosure = text(await findByTestId("user-provider-disclosure"));
      expect(disclosure).toContain(NON_OWNER_DISCLOSURE);
      expect(disclosure).toContain("Saved conversation history is not transferred");
    });
  });
});

// #11599 — the operator recovery sentence quotes the Settings label in server copy that cannot import this component; this
// ties the two so a relabel here fails the copy test instead of silently sending the operator to a control that is gone.
describe("operator recovery copy names the Settings label", () => {
  it("quotes the label the api-key option renders", () => {
    const label = authModeLabel("claude-code", "api-key");
    expect(label).toBe("My API key");
    expect(authFailureCopy("not_logged_in", "oauth_token")).toContain(`"${label}"`);
    expect(authFailureCopy("not_logged_in", "api_key")).not.toContain(`"${label}"`);
  });
});

function viewOptionDisabled(select: HTMLElement, value: string): boolean {
  return (select.querySelector(`option[value="${value}"]`) as HTMLOptionElement | null)?.disabled ?? false;
}
