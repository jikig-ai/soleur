import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";
import { render, screen, within } from "@testing-library/react";
import { RailSlotHarness } from "./helpers/rail-slot-harness";

let mockPathname = "/dashboard/settings";

vi.mock("next/navigation", () => ({
  usePathname: () => mockPathname,
}));

import { SettingsShell } from "@/components/settings/settings-shell";

// ADR-047: the Settings sub-nav is lifted into the single nav rail's slot via
// a portal. The per-shell collapse chrome and mobile bottom tab bar are gone —
// the unified rail owns collapse (⌘B, tested in dashboard-sidebar-collapse) and
// hosts the nav on every breakpoint. These tests assert the lifted nav lands in
// the slot with correct tabs + active state.
describe("Settings sub-nav lifts into the single nav rail slot (ADR-047)", () => {
  beforeEach(() => {
    mockPathname = "/dashboard/settings";
    localStorage.clear();
  });
  afterEach(() => {
    localStorage.clear();
  });

  it("portals the settings nav (with its tabs) into the rail slot", () => {
    render(
      <RailSlotHarness>
        <SettingsShell>
          <div>content</div>
        </SettingsShell>
      </RailSlotHarness>,
    );
    const slot = screen.getByTestId("rail-slot-harness");
    const nav = within(slot).getByRole("navigation", { name: "Settings" });
    expect(within(nav).getByRole("link", { name: "General" })).toBeInTheDocument();
    expect(
      within(nav).getByRole("link", { name: "Integrations" }),
    ).toBeInTheDocument();
    expect(
      within(nav).getByRole("link", { name: "Billing" }),
    ).toBeInTheDocument();
  });

  it("includes the flag-gated Members + Team Activity tabs when provided", () => {
    render(
      <RailSlotHarness>
        <SettingsShell
          membersTab={{ href: "/dashboard/settings/members", label: "Members" }}
          activityTab={{
            href: "/dashboard/settings/team-activity",
            label: "Team Activity",
          }}
        >
          <div>content</div>
        </SettingsShell>
      </RailSlotHarness>,
    );
    expect(screen.getByRole("link", { name: "Members" })).toBeInTheDocument();
    expect(
      screen.getByRole("link", { name: "Team Activity" }),
    ).toBeInTheDocument();
  });

  it("marks the active tab via aria-current on the matching route", () => {
    mockPathname = "/dashboard/settings/billing";
    render(
      <RailSlotHarness>
        <SettingsShell>
          <div>content</div>
        </SettingsShell>
      </RailSlotHarness>,
    );
    expect(screen.getByRole("link", { name: "Billing" })).toHaveAttribute(
      "aria-current",
      "page",
    );
    expect(screen.getByRole("link", { name: "General" })).not.toHaveAttribute(
      "aria-current",
    );
  });

  it("renders NO collapse button (collapse is owned by the unified rail)", () => {
    render(
      <RailSlotHarness>
        <SettingsShell>
          <div>content</div>
        </SettingsShell>
      </RailSlotHarness>,
    );
    expect(
      screen.queryByLabelText("Collapse settings nav"),
    ).not.toBeInTheDocument();
  });

  it("renders the page content regardless of the rail slot", () => {
    render(
      <RailSlotHarness>
        <SettingsShell>
          <div data-testid="settings-content">content</div>
        </SettingsShell>
      </RailSlotHarness>,
    );
    expect(screen.getByTestId("settings-content")).toBeInTheDocument();
  });
});
