import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, screen, fireEvent } from "@testing-library/react";
import userEvent from "@testing-library/user-event";

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
      />,
    );
    const headings = screen.getAllByRole("heading", { level: 2 });
    const headingTexts = headings.map((h) => h.textContent);
    expect(headingTexts.indexOf("Project")).toBeLessThan(
      headingTexts.indexOf("API Key"),
    );
  });
});
