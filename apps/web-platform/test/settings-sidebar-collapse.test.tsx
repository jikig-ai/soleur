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

  // AC4.4 (Sidebar-UX Issue 4) — when the unified rail is collapsed, the Settings
  // sub-nav renders an ICON-ONLY column (one icon button per tab) instead of being
  // DOM-removed (which left the collapsed rail empty). The single-glyph buttons fit
  // the 56px rail by construction. The accessible name moves to aria-label (no
  // visible text), so each tab is still reachable + tooltip-recoverable. This
  // intentionally REVERSES the prior "DOM-removed when collapsed" invariant.
  it("renders an icon-only Settings nav when collapsed (AC4.4), keeping the stable wrapper", () => {
    render(
      <RailSlotHarness collapsed>
        <SettingsShell>
          <div>content</div>
        </SettingsShell>
      </RailSlotHarness>,
    );
    const slot = screen.getByTestId("rail-slot-harness");
    // Stable wrapper always renders.
    expect(within(slot).getByTestId("settings-rail-nav")).toBeInTheDocument();
    // The nav is PRESENT (not DOM-removed) and tagged as the icon-only variant.
    const nav = within(slot).getByRole("navigation", { name: "Settings" });
    expect(nav).toHaveAttribute("data-testid", "settings-rail-icons");
    // Each tab is still a reachable link (accessible name via aria-label) ...
    const general = within(nav).getByRole("link", { name: "General" });
    expect(general).toBeInTheDocument();
    // ... but renders NO visible text label (icon-only — 56px safe).
    expect(general).toHaveTextContent("");
  });

  // AC4 — the SAME wrapper has the nav PRESENT when expanded (so AC2 is not
  // satisfied vacuously by an always-empty rail).
  it("keeps the settings nav present when expanded (AC4)", () => {
    render(
      <RailSlotHarness collapsed={false}>
        <SettingsShell>
          <div>content</div>
        </SettingsShell>
      </RailSlotHarness>,
    );
    const wrapper = screen.getByTestId("settings-rail-nav");
    expect(
      within(wrapper).getByRole("navigation", { name: "Settings" }),
    ).toBeInTheDocument();
    expect(
      within(wrapper).getByRole("link", { name: "General" }),
    ).toBeInTheDocument();
  });
});
