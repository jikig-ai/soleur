import { describe, it, expect, vi } from "vitest";
import { render } from "@testing-library/react";

// AC6/AC8: the workspace-identity controls (logo + rename) were relocated from
// the Team page to the General page (SettingsContent). They render when a
// workspaceIdentity is provided, with the owner gate preserved. The heavy
// sibling cards (API key / project / delete) are stubbed so this test exercises
// only SettingsContent's composition + the REAL relocated controls.

vi.mock("next/navigation", () => ({
  useRouter: () => ({ push: vi.fn(), refresh: vi.fn() }),
  useSearchParams: () => new URLSearchParams(),
}));
vi.mock("@/components/settings/key-rotation-form", () => ({
  KeyRotationForm: () => <div data-testid="stub-key-form" />,
}));
vi.mock("@/components/settings/delete-account-dialog", () => ({
  DeleteAccountDialog: () => <div data-testid="stub-delete" />,
}));
vi.mock("@/components/settings/project-setup-card", () => ({
  ProjectSetupCard: () => <div data-testid="stub-project" />,
}));

import { SettingsContent } from "@/components/settings/settings-content";

const baseProps = {
  userEmail: "a@b.com",
  hasApiKey: false,
  apiKeyProvider: null,
  apiKeyLastValidated: null,
  repoUrl: null,
  repoStatus: "not_connected" as const,
  repoLastSyncedAt: null,
  needsReconnect: false,
};

const IDENTITY = {
  workspaceId: "11111111-1111-1111-1111-111111111111",
  organizationId: "22222222-2222-2222-2222-222222222222",
  organizationName: "Acme",
  isOwner: true,
  hasLogo: false,
};

describe("SettingsContent — relocated workspace-identity controls (AC6/AC8)", () => {
  it("renders logo + rename controls when a workspaceIdentity is provided", () => {
    const { getByTestId, getByText } = render(
      <SettingsContent {...baseProps} workspaceIdentity={IDENTITY} />,
    );
    expect(getByTestId("workspace-logo-settings")).toBeTruthy();
    expect(getByText("Acme")).toBeTruthy(); // rename action shows current name
  });

  it("preserves the owner gate: a non-owner sees the disabled logo control", () => {
    const { getByTestId } = render(
      <SettingsContent
        {...baseProps}
        workspaceIdentity={{ ...IDENTITY, isOwner: false }}
      />,
    );
    const btn = getByTestId("workspace-logo-upload-btn") as HTMLButtonElement;
    expect(btn.disabled).toBe(true);
    expect(btn.getAttribute("title")).toMatch(/owners can change the logo/i);
  });

  it("renders no identity controls when workspaceIdentity is absent", () => {
    const { queryByTestId } = render(<SettingsContent {...baseProps} />);
    expect(queryByTestId("workspace-logo-settings")).toBeNull();
  });
});
