// @vitest-environment happy-dom
import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { ReactNode } from "react";

// #9545 PR2 — the Agent web access card: the audit-log link, the "Last recorded request" hint, the
// retention sentence, the non-owner recording line and the enable-dialog notice. The recording notice
// is tri-state on the collection flag so an outage can never HIDE the disclosure from an owner.

vi.mock("@/components/ui/nav-link", () => ({
  NavLink: ({ href, children, ...rest }: { href: string; children: ReactNode }) => (
    <a href={href} {...rest}>
      {children}
    </a>
  ),
}));

import { WebEgressToggle } from "@/components/settings/web-egress-toggle";

const LINK = "/dashboard/settings/scope-grants/egress-audit";
const NOTICE_START = "Hosts your agents contact are recorded as best-effort summary counts";
const GENERIC = "Activity may be recorded and visible to members of this workspace.";

beforeEach(() => {
  vi.useFakeTimers({ toFake: ["Date"] });
  vi.setSystemTime(new Date("2026-10-26T12:10:00Z"));
});
afterEach(() => {
  cleanup();
  vi.useRealTimers();
});

const card = (over: Partial<Parameters<typeof WebEgressToggle>[0]> = {}) =>
  render(<WebEgressToggle initialWebEgress={false} isOwner lastRequestAt={null} collection={false} {...over} />);

describe("WebEgressToggle — audit link and hint", () => {
  it("links to the egress audit log in both toggle states, for owners and non-owners", () => {
    for (const webEgress of [false, true]) {
      for (const isOwner of [true, false]) {
        const { unmount } = card({ initialWebEgress: webEgress, isOwner });
        expect(screen.getByRole("link", { name: /View egress audit log/ }).getAttribute("href")).toBe(LINK);
        unmount();
      }
    }
  });

  it("shows 'Last recorded request: X ago' (client-rendered, clamped at zero) and nothing when there is no request", () => {
    card({ lastRequestAt: "2026-10-26T12:06:00Z" });
    expect(screen.getByText("Last recorded request: 4 minutes ago")).toBeTruthy();
    cleanup();
    card({ lastRequestAt: "2026-10-26T12:40:00Z" });
    expect(screen.getByText("Last recorded request: just now")).toBeTruthy();
    cleanup();
    card({ lastRequestAt: null });
    expect(screen.queryByText(/Last recorded request/)).toBeNull();
    expect(screen.getByRole("link", { name: /View egress audit log/ })).toBeTruthy();
  });

  it("the Off card states the retention fact only when a record exists; the On card does not", () => {
    const sentence = "Existing records stay visible to members until deleted about 30 days after they were recorded.";
    card({ initialWebEgress: false, lastRequestAt: "2026-10-26T12:06:00Z" });
    expect(screen.getByText(sentence)).toBeTruthy();
    cleanup();
    card({ initialWebEgress: false, lastRequestAt: null });
    expect(screen.queryByText(sentence)).toBeNull();
    cleanup();
    card({ initialWebEgress: true, lastRequestAt: "2026-10-26T12:06:00Z" });
    expect(screen.queryByText(sentence)).toBeNull();
  });

  it("a non-owner sees the one-line recording notice only while collection is on", () => {
    const line = "Egress is recorded and visible to members of this workspace.";
    card({ isOwner: false, collection: true });
    expect(screen.getByText(line)).toBeTruthy();
    cleanup();
    card({ isOwner: true, collection: true });
    expect(screen.queryByText(line)).toBeNull();
    cleanup();
    for (const collection of [false, "unknown"] as const) {
      card({ isOwner: false, collection });
      expect(screen.queryByText(line)).toBeNull();
      cleanup();
    }
  });
});

describe("WebEgressToggle — enable dialog copy", () => {
  const open = (collection: boolean | "unknown") => {
    card({ collection });
    fireEvent.click(screen.getByRole("switch", { name: "Agent web access" }));
    return screen.getByRole("alertdialog");
  };

  it("never says every outbound request is logged", () => {
    for (const c of [true, false, "unknown"] as const) {
      const dlg = open(c);
      expect(dlg.textContent).not.toMatch(/Every outbound request is logged/i);
      cleanup();
    }
  });

  it("collection on: shows the ruled best-effort notice (members, pre-join, no member or session, minimums, off keeps records)", () => {
    const text = open(true).textContent ?? "";
    expect(text).toContain(NOTICE_START);
    expect(text).toContain("Every current member of this workspace can view them, including activity from before they joined.");
    expect(text).toContain("No member or session is recorded, some entries may be missing, and counts are minimums.");
    expect(text).toContain("Turning web access off stops new records but does not delete existing ones.");
    expect(text).not.toMatch(/\bcomplete\b|every connection|tamper-proof|\bsessions\b/i);
  });

  it("collection unknown: shows the generic sentence so an outage cannot hide the disclosure", () => {
    const text = open("unknown").textContent ?? "";
    expect(text).toContain(GENERIC);
    expect(text).not.toContain(NOTICE_START);
  });

  it("collection off: no recording sentence at all", () => {
    const text = open(false).textContent ?? "";
    expect(text).not.toContain(NOTICE_START);
    expect(text).not.toContain(GENERIC);
    expect(text).not.toMatch(/recorded/i);
  });
});
