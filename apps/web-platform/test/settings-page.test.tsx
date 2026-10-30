import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, screen, fireEvent, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describeCredentialBasis } from "@/lib/credential-basis";

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

vi.mock("next/navigation", () => ({
  useRouter: () => ({ push: vi.fn(), refresh: vi.fn() }),
  useSearchParams: () => new URLSearchParams(),
}));

// ---------------------------------------------------------------------------
// DeleteAccountDialog tests (client component)
// ---------------------------------------------------------------------------

describe("DeleteAccountDialog", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("renders the delete account button", async () => {
    const { DeleteAccountDialog } = await import(
      "@/components/settings/delete-account-dialog"
    );
    render(
      <DeleteAccountDialog userEmail="test@example.com" />,
    );
    expect(
      screen.getByRole("button", { name: /delete account/i }),
    ).toBeInTheDocument();
  });

  it("shows confirmation dialog when delete button is clicked", async () => {
    const { DeleteAccountDialog } = await import(
      "@/components/settings/delete-account-dialog"
    );
    render(
      <DeleteAccountDialog userEmail="test@example.com" />,
    );

    const deleteBtn = screen.getByRole("button", { name: /delete account/i });
    await userEvent.click(deleteBtn);

    expect(screen.getByText(/this action cannot be undone/i)).toBeInTheDocument();
  });

  it("disables confirm button until email is typed correctly", async () => {
    const { DeleteAccountDialog } = await import(
      "@/components/settings/delete-account-dialog"
    );
    render(
      <DeleteAccountDialog userEmail="test@example.com" />,
    );

    const deleteBtn = screen.getByRole("button", { name: /delete account/i });
    await userEvent.click(deleteBtn);

    const confirmBtn = screen.getByRole("button", { name: /confirm deletion/i });
    expect(confirmBtn).toBeDisabled();
  });

  it("enables confirm button when email matches", async () => {
    const { DeleteAccountDialog } = await import(
      "@/components/settings/delete-account-dialog"
    );
    render(
      <DeleteAccountDialog userEmail="test@example.com" />,
    );

    const deleteBtn = screen.getByRole("button", { name: /delete account/i });
    await userEvent.click(deleteBtn);

    const emailInput = screen.getByPlaceholderText(/test@example.com/i);
    await userEvent.type(emailInput, "test@example.com");

    const confirmBtn = screen.getByRole("button", { name: /confirm deletion/i });
    expect(confirmBtn).toBeEnabled();
  });

  it("does not enable confirm when email is partial", async () => {
    const { DeleteAccountDialog } = await import(
      "@/components/settings/delete-account-dialog"
    );
    render(
      <DeleteAccountDialog userEmail="test@example.com" />,
    );

    const deleteBtn = screen.getByRole("button", { name: /delete account/i });
    await userEvent.click(deleteBtn);

    const emailInput = screen.getByPlaceholderText(/test@example.com/i);
    await userEvent.type(emailInput, "test@exam");

    const confirmBtn = screen.getByRole("button", { name: /confirm deletion/i });
    expect(confirmBtn).toBeDisabled();
  });
});

// ---------------------------------------------------------------------------
// KeyRotationForm tests (client component)
// ---------------------------------------------------------------------------

describe("KeyRotationForm", () => {
  it("renders the API key input", async () => {
    const { KeyRotationForm } = await import(
      "@/components/settings/key-rotation-form"
    );
    render(<KeyRotationForm hasExistingKey={false} />);
    expect(
      screen.getByPlaceholderText(/sk-ant-/i),
    ).toBeInTheDocument();
  });

  it("shows 'Rotate Key' label when key exists", async () => {
    const { KeyRotationForm } = await import(
      "@/components/settings/key-rotation-form"
    );
    render(<KeyRotationForm hasExistingKey={true} />);
    expect(
      screen.getByRole("button", { name: /rotate key/i }),
    ).toBeInTheDocument();
  });

  it("shows 'Save Key' label when no key exists", async () => {
    const { KeyRotationForm } = await import(
      "@/components/settings/key-rotation-form"
    );
    render(<KeyRotationForm hasExistingKey={false} />);
    expect(
      screen.getByRole("button", { name: /save key/i }),
    ).toBeInTheDocument();
  });
});

// ---------------------------------------------------------------------------
// Settings page section headings (tests that the sections exist)
// ---------------------------------------------------------------------------

describe("Settings page sections", () => {
  it("renders 'API Key' section heading", async () => {
    const { SettingsContent } = await import(
      "@/components/settings/settings-content"
    );
    render(
      <SettingsContent
        userEmail="test@example.com"
        hasApiKey={false}
        apiKeyProvider={null}
        apiKeyLastValidated={null}
        repoUrl={null}
        repoStatus="not_connected"
        repoLastSyncedAt={null}
        needsReconnect={false}
      />,
    );
    expect(screen.getByText("API Key")).toBeInTheDocument();
  });

  it("renders 'Account' section heading with user email", async () => {
    const { SettingsContent } = await import(
      "@/components/settings/settings-content"
    );
    render(
      <SettingsContent
        userEmail="test@example.com"
        hasApiKey={false}
        apiKeyProvider={null}
        apiKeyLastValidated={null}
        repoUrl={null}
        repoStatus="not_connected"
        repoLastSyncedAt={null}
        needsReconnect={false}
      />,
    );
    expect(screen.getByText("Account")).toBeInTheDocument();
    expect(screen.getByText("test@example.com")).toBeInTheDocument();
  });

  it("renders 'Danger Zone' section heading instead of duplicate 'Account'", async () => {
    const { SettingsContent } = await import(
      "@/components/settings/settings-content"
    );
    render(
      <SettingsContent
        userEmail="test@example.com"
        hasApiKey={false}
        apiKeyProvider={null}
        apiKeyLastValidated={null}
        repoUrl={null}
        repoStatus="not_connected"
        repoLastSyncedAt={null}
        needsReconnect={false}
      />,
    );
    expect(screen.getByText("Danger Zone")).toBeInTheDocument();
  });

  it("renders Account section before Project section", async () => {
    const { SettingsContent } = await import(
      "@/components/settings/settings-content"
    );
    render(
      <SettingsContent
        userEmail="test@example.com"
        hasApiKey={false}
        apiKeyProvider={null}
        apiKeyLastValidated={null}
        repoUrl={null}
        repoStatus="not_connected"
        repoLastSyncedAt={null}
        needsReconnect={false}
      />,
    );
    const headings = screen.getAllByRole("heading", { level: 2 });
    const headingTexts = headings.map((h) => h.textContent);
    expect(headingTexts.indexOf("Account")).toBeLessThan(
      headingTexts.indexOf("Project"),
    );
  });

  it("shows key status as 'No key configured' when no key exists", async () => {
    const { SettingsContent } = await import(
      "@/components/settings/settings-content"
    );
    render(
      <SettingsContent
        userEmail="test@example.com"
        hasApiKey={false}
        apiKeyProvider={null}
        apiKeyLastValidated={null}
        repoUrl={null}
        repoStatus="not_connected"
        repoLastSyncedAt={null}
        needsReconnect={false}
      />,
    );
    expect(screen.getByText(/no key configured/i)).toBeInTheDocument();
  });

  it("shows provider name when key exists", async () => {
    const { SettingsContent } = await import(
      "@/components/settings/settings-content"
    );
    render(
      <SettingsContent
        userEmail="test@example.com"
        hasApiKey={true}
        apiKeyProvider="anthropic"
        apiKeyLastValidated="2026-04-01T00:00:00Z"
        repoUrl={null}
        repoStatus="not_connected"
        repoLastSyncedAt={null}
        needsReconnect={false}
      />,
    );
    expect(screen.getByText(/provider:/i)).toBeInTheDocument();
  });

  it("renders 'Project' section heading", async () => {
    const { SettingsContent } = await import(
      "@/components/settings/settings-content"
    );
    render(
      <SettingsContent
        userEmail="test@example.com"
        hasApiKey={false}
        apiKeyProvider={null}
        apiKeyLastValidated={null}
        repoUrl={null}
        repoStatus="not_connected"
        repoLastSyncedAt={null}
        needsReconnect={false}
      />,
    );
    // Project section should appear — look for heading rendered by ProjectSetupCard
    expect(screen.getByText("Project")).toBeInTheDocument();
  });

  it("renders Project section before API Key section", async () => {
    const { SettingsContent } = await import(
      "@/components/settings/settings-content"
    );
    render(
      <SettingsContent
        userEmail="test@example.com"
        hasApiKey={false}
        apiKeyProvider={null}
        apiKeyLastValidated={null}
        repoUrl={null}
        repoStatus="not_connected"
        repoLastSyncedAt={null}
        needsReconnect={false}
      />,
    );
    const headings = screen.getAllByRole("heading", { level: 2 });
    const headingTexts = headings.map((h) => h.textContent);
    expect(headingTexts.indexOf("Project")).toBeLessThan(
      headingTexts.indexOf("API Key"),
    );
  });
});

// ---------------------------------------------------------------------------
// #11524 — stored subscription token: status lines + removal control
// ---------------------------------------------------------------------------

const baseContentProps = {
  userEmail: "test@example.com",
  hasApiKey: false,
  apiKeyProvider: null,
  apiKeyLastValidated: null,
  repoUrl: null,
  repoStatus: "not_connected" as const,
  repoLastSyncedAt: null,
  needsReconnect: false,
};

describe("SettingsContent — stored subscription token (#11524)", () => {
  it("shows no token lines and no Remove control when no oauth row exists", async () => {
    const { SettingsContent } = await import(
      "@/components/settings/settings-content"
    );
    render(<SettingsContent {...baseContentProps} hasApiKey={true} apiKeyProvider="anthropic" />);
    expect(screen.queryByText(/Subscription token:/)).toBeNull();
    expect(screen.queryByText(/Conversations use:/)).toBeNull();
    expect(
      screen.queryByRole("button", { name: "Remove subscription token" }),
    ).toBeNull();
  });

  it("shows the saved date, the billing basis and the Remove control for any stored row, even when the toggle is not offered", async () => {
    const { SettingsContent } = await import(
      "@/components/settings/settings-content"
    );
    render(
      <SettingsContent
        {...baseContentProps}
        hasApiKey={true}
        apiKeyProvider="anthropic"
        hasOauthToken={true}
        oauthInEffect={true}
        oauthTokenSavedAt="2026-10-28T10:00:00Z"
        canUseOauthCredential={false}
      />,
    );
    expect(
      screen.getByText(
        "Subscription token: saved Oct 28, 2026",
      ),
    ).toBeInTheDocument();
    expect(
      screen.getByText("Conversations use: Claude subscription (API key also saved)"),
    ).toBeInTheDocument();
    expect(
      screen.getByRole("button", { name: "Remove subscription token" }),
    ).toBeInTheDocument();
  });

  it("an inert stored token (not in effect) stays removable and makes no subscription claim", async () => {
    const { SettingsContent } = await import(
      "@/components/settings/settings-content"
    );
    render(
      <SettingsContent
        {...baseContentProps}
        hasApiKey={true}
        apiKeyProvider="anthropic"
        hasOauthToken={true}
        oauthInEffect={false}
        oauthTokenSavedAt={null}
      />,
    );
    expect(screen.getByText("Conversations use: your Anthropic API key")).toBeInTheDocument();
    expect(
      screen.getByRole("button", { name: "Remove subscription token" }),
    ).toBeInTheDocument();
  });

  it("status line and confirm dialog derive from the same source (no API key, in effect)", async () => {
    const { SettingsContent } = await import(
      "@/components/settings/settings-content"
    );
    render(
      <SettingsContent
        {...baseContentProps}
        hasOauthToken={true}
        oauthInEffect={true}
        oauthTokenSavedAt="2026-10-28T10:00:00Z"
      />,
    );
    expect(screen.getByText("Conversations use: Claude subscription")).toBeInTheDocument();
    await userEvent.click(
      screen.getByRole("button", { name: "Remove subscription token" }),
    );
    expect(
      screen.getByRole("button", { name: "Add an API key first" }),
    ).toBeInTheDocument();
  });
});

describe("KeyRotationForm — subscription token removal flow (#11524)", () => {
  const fetchMock = vi.fn();
  // SettingsContent computes the basis once and passes it down.
  const basisOf = (oauthInEffect: boolean, hasApiKey: boolean) =>
    describeCredentialBasis({ hasOauthToken: true, oauthInEffect, hasApiKey });
  beforeEach(() => {
    fetchMock.mockReset();
    vi.stubGlobal("fetch", fetchMock);
  });

  async function loadForm() {
    const { KeyRotationForm } = await import(
      "@/components/settings/key-rotation-form"
    );
    return KeyRotationForm;
  }

  it("variant B success: notice (role=status) names the next step and focus lands on #api-key-input", async () => {
    fetchMock.mockResolvedValue({ ok: true, status: 200, json: async () => ({ deleted: true }) });
    const KeyRotationForm = await loadForm();
    const { rerender } = render(
      <KeyRotationForm hasExistingKey={false} basis={basisOf(true, false)} />,
    );
    await userEvent.click(
      screen.getByRole("button", { name: "Remove subscription token" }),
    );
    await userEvent.click(screen.getByRole("button", { name: "Remove token" }));
    const notice = await screen.findByRole("status");
    expect(notice).toHaveTextContent(
      "Subscription token removed. Add an API key to keep using chat.",
    );
    expect(document.getElementById("api-key-input")).toHaveFocus();

    // After router.refresh() flips the props the dialog unmounts; the notice stays.
    rerender(
      <KeyRotationForm hasExistingKey={false} basis={null} />,
    );
    expect(screen.getByRole("status")).toHaveTextContent(
      "Subscription token removed. Add an API key to keep using chat.",
    );
    expect(
      screen.queryByRole("button", { name: "Remove subscription token" }),
    ).toBeNull();
  });

  it("saving an API key afterwards clears the stale post-removal notice", async () => {
    fetchMock.mockImplementation(async (_url: string, init: { method: string }) =>
      init.method === "DELETE"
        ? { ok: true, status: 200, json: async () => ({ deleted: true }) }
        : { ok: true, status: 200, json: async () => ({ valid: true }) },
    );
    const KeyRotationForm = await loadForm();
    render(<KeyRotationForm hasExistingKey={false} basis={basisOf(true, false)} />);
    await userEvent.click(
      screen.getByRole("button", { name: "Remove subscription token" }),
    );
    await userEvent.click(screen.getByRole("button", { name: "Remove token" }));
    expect(await screen.findByRole("status")).toHaveTextContent(
      "Add an API key to keep using chat.",
    );
    await userEvent.type(
      document.getElementById("api-key-input") as HTMLInputElement,
      "sk-ant-fake-key",
    );
    await userEvent.click(screen.getByRole("button", { name: "Save Key" }));
    expect(await screen.findByText("Key saved successfully.")).toBeInTheDocument();
    expect(screen.queryByRole("status")).toBeNull();
    expect(screen.queryByText(/Add an API key to keep using chat/)).toBeNull();
  });

  it("variant A success: notice region takes focus (tabIndex -1)", async () => {
    fetchMock.mockResolvedValue({ ok: true, status: 200, json: async () => ({ deleted: true }) });
    const KeyRotationForm = await loadForm();
    render(<KeyRotationForm hasExistingKey basis={basisOf(true, true)} />);
    await userEvent.click(
      screen.getByRole("button", { name: "Remove subscription token" }),
    );
    await userEvent.click(screen.getByRole("button", { name: "Remove token" }));
    const notice = await screen.findByRole("status");
    expect(notice).toHaveTextContent(
      "Subscription token removed. New conversations will use your API key.",
    );
    expect(notice).toHaveAttribute("tabindex", "-1");
    await waitFor(() => expect(notice).toHaveFocus());
  });

  it("variant C success: neutral notice", async () => {
    fetchMock.mockResolvedValue({ ok: true, status: 200, json: async () => ({ deleted: true }) });
    const KeyRotationForm = await loadForm();
    render(<KeyRotationForm hasExistingKey basis={basisOf(false, true)} />);
    await userEvent.click(
      screen.getByRole("button", { name: "Remove subscription token" }),
    );
    await userEvent.click(screen.getByRole("button", { name: "Remove token" }));
    expect(await screen.findByRole("status")).toHaveTextContent(
      "Subscription token removed.",
    );
  });

  it("Add an API key first switches the credential radio to API key and focuses the input, keeping typed text", async () => {
    const KeyRotationForm = await loadForm();
    render(
      <KeyRotationForm
        hasExistingKey={false}
        basis={basisOf(true, false)}
        canUseOauthCredential
      />,
    );
    await userEvent.click(screen.getByRole("radio", { name: "Subscription token" }));
    const input = document.getElementById("api-key-input") as HTMLInputElement;
    await userEvent.type(input, "draft-text");
    await userEvent.click(
      screen.getByRole("button", { name: "Remove subscription token" }),
    );
    await userEvent.click(
      screen.getByRole("button", { name: "Add an API key first" }),
    );
    expect(screen.getByRole("radio", { name: "API key" })).toHaveAttribute(
      "aria-checked",
      "true",
    );
    expect(document.getElementById("api-key-input")).toHaveFocus();
    expect((document.getElementById("api-key-input") as HTMLInputElement).value).toBe(
      "draft-text",
    );
  });

  it("renders no Remove control when no oauth row is stored", async () => {
    const KeyRotationForm = await loadForm();
    render(<KeyRotationForm hasExistingKey />);
    expect(
      screen.queryByRole("button", { name: "Remove subscription token" }),
    ).toBeNull();
  });
});
