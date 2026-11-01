import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { act, fireEvent, render, waitFor } from "@testing-library/react";
import { StrictMode } from "react";

import { AgentEngineSettings, authModeLabel } from "@/components/settings/agent-engine-settings";
import { authFailureCopy } from "@/server/agent-auth-user-message";

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

  describe("#11591 — option labels, helper and disclosure", () => {
    const claudeOnly = {
      defaultEngineId: "claude-code",
      defaultAuthMode: "managed",
      engines: [{ id: "claude-code", version: "v1", transport: "local", authModes: ["managed", "api-key"], enabledForNewRuns: true, rolloutEnabled: true }],
    };

    it("shows Automatic / My API key while the stored values stay managed / api-key", async () => {
      fetchMock.mockResolvedValueOnce({ ok: true, json: async () => claudeOnly });
      const { findByLabelText, getByRole, getByText } = render(<AgentEngineSettings isOwner />);
      const mode = (await findByLabelText("Authentication mode")) as HTMLSelectElement;
      expect(Array.from(mode.options).map((o) => [o.value, o.textContent])).toEqual([
        ["managed", "Automatic"],
        ["api-key", "My API key"],
      ]);
      // The radio sub-label tells the same story as the select (no raw "managed or api-key").
      expect(getByText("local · Automatic or My API key")).toBeTruthy();
      expect(getByRole("radio", { name: /Claude Code/ })).toBeTruthy();
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
      const { findByLabelText, queryByTestId } = render(<AgentEngineSettings isOwner />);
      const mode = (await findByLabelText("Authentication mode")) as HTMLSelectElement;
      expect(Array.from(mode.options).map((o) => o.textContent)).toEqual(["managed", "api-key"]);
      expect(queryByTestId("auth-mode-helper")).toBeNull();
      expect(queryByTestId("user-provider-disclosure")).toBeNull();
      expect(mode.getAttribute("aria-describedby")).toBeNull();
      fireEvent.change(mode, { target: { value: "api-key" } });
      expect(queryByTestId("user-provider-disclosure")).toBeTruthy();
      expect(mode.getAttribute("aria-describedby")).toBe("user-provider-disclosure");
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
      const { findByTestId, findByLabelText, getByRole } = render(<AgentEngineSettings isOwner={false} />);
      const all = text(await findByTestId("auth-mode-helper")) + text(await findByTestId("user-provider-disclosure"));
      expect(all).not.toMatch(/subscription/i);
      expect(all).not.toMatch(/your own provider account|your saved API key|saved to your account/i);
      expect(await findByLabelText("Authentication mode")).toBeDisabled();
      expect(getByRole("radio", { name: /Claude Code/ })).toBeDisabled();
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
      expect(text(await findByTestId("user-provider-disclosure"))).toBe(NON_OWNER_DISCLOSURE);
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
