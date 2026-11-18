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
// The stub records the props SettingsContent hands the card (V10: the held notice's audience).
const cardProps = vi.hoisted(() => ({ last: null as Record<string, unknown> | null }));
vi.mock("@/components/settings/project-setup-card", () => ({
  ProjectSetupCard: (p: Record<string, unknown>) => {
    cardProps.last = p;
    return <div data-testid="stub-project" />;
  },
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
  ownerCheck: "owner" as const,
  hasLogo: false,
  canRename: true,
};

describe("SettingsContent — the held notice's audience (#12704 V10)", () => {
  it.each([
    ["no identity (the workspace read failed)", null, "unknown", true],
    ["the owner check failed", { ...IDENTITY, isOwner: false, ownerCheck: "unknown" as const }, "unknown", false],
    ["the owner", IDENTITY, "owner", true],
    ["a member", { ...IDENTITY, isOwner: false, ownerCheck: "member" as const }, "member", false],
  ])("%s -> audience %s; the controls flag is unchanged", (_n, identity, audience, isOwner) => {
    render(<SettingsContent {...baseProps} workspaceIdentity={identity} heldFiles={3} heldRoute="available" />);
    expect(cardProps.last).toMatchObject({ heldAudience: audience, isOwner, heldFiles: 3, heldRoute: "available" });
  });
});

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

  it("hides rename but keeps the logo when canRename is false (flag-off; rename route would 404)", () => {
    const { getByTestId, queryByText } = render(
      <SettingsContent
        {...baseProps}
        workspaceIdentity={{ ...IDENTITY, canRename: false }}
      />,
    );
    // Logo stays reachable regardless of the team flag (the reachability fix)...
    expect(getByTestId("workspace-logo-settings")).toBeTruthy();
    // ...but the rename control (whose API is flag-gated) is not rendered.
    expect(queryByText("Acme")).toBeNull();
  });
});
