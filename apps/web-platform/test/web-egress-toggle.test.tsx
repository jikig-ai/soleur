// @vitest-environment happy-dom
import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, expectTypeOf, it, vi } from "vitest";
import type { ReactNode } from "react";

// #9545 PR2 — the Agent web access card: the audit-log link, the "Last recorded request" hint, the
// retention sentence, the recording note and the enable-dialog notice. The recording notice
// is tri-state on the collection flag so an outage can never HIDE the disclosure from an owner.

vi.mock("@/components/ui/nav-link", () => ({
  NavLink: ({ href, children, ...rest }: { href: string; children: ReactNode }) => (
    <a href={href} {...rest}>
      {children}
    </a>
  ),
}));

import { WebEgressToggle } from "@/components/settings/web-egress-toggle";
import type { CollectionState } from "@/lib/egress-audit/summary";

const LINK = "/dashboard/settings/scope-grants/egress-audit";
const NOTICE_START = "Hosts your agents contact are recorded as best-effort summary counts: the host, whether the request was allowed, blocked or ended another way, and the number of requests.";
const UNKNOWN_LEAD = "We couldn't check whether recording is on for this workspace. If it is, the following applies.";
const CARD_TRUE = "Activity through web access is recorded for this workspace and visible to every current member.";
const CARD_UNKNOWN = "Activity through web access may be recorded for this workspace and visible to every current member.";
const FORBIDDEN = /\bcomplete\b|every connection|tamper-proof|\bsessions\b/i;

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

describe("WebEgressToggle — props contract", () => {
  it("collection and lastRequestAt are required (no fail-open default); collection is the lib's CollectionState", () => {
    type P = Parameters<typeof WebEgressToggle>[0];
    expectTypeOf<P["collection"]>().toEqualTypeOf<CollectionState>();
    expectTypeOf<P["lastRequestAt"]>().toEqualTypeOf<string | null>();
    // @ts-expect-error collection must be passed: omitting it would silently hide the recording disclosure
    const missingCollection: P = { initialWebEgress: false, isOwner: true, lastRequestAt: null };
    // @ts-expect-error lastRequestAt must be passed
    const missingLast: P = { initialWebEgress: false, isOwner: true, collection: false };
    expect([missingCollection, missingLast]).toHaveLength(2);
  });
});

describe("WebEgressToggle — audit link and hint", () => {
  it("links to the egress audit log in both toggle states, for owners and non-owners", () => {
    let seen = 0;
    for (const webEgress of [false, true]) {
      for (const isOwner of [true, false]) {
        const { unmount } = card({ initialWebEgress: webEgress, isOwner });
        expect(screen.getByRole("link", { name: /View egress audit log/ }).getAttribute("href")).toBe(LINK);
        seen += 1;
        unmount();
      }
    }
    expect(seen).toBe(4);
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

  it("every role sees the card note while collection is on or unknown, and nothing while it is off", () => {
    let seen = 0;
    for (const isOwner of [true, false]) {
      card({ isOwner, collection: true });
      expect(screen.getByText(CARD_TRUE)).toBeTruthy();
      expect(screen.queryByText(CARD_UNKNOWN)).toBeNull();
      cleanup();
      card({ isOwner, collection: "unknown" });
      expect(screen.getByText(CARD_UNKNOWN)).toBeTruthy();
      expect(screen.queryByText(CARD_TRUE)).toBeNull();
      cleanup();
      card({ isOwner, collection: false });
      expect(screen.queryByText(CARD_TRUE)).toBeNull();
      expect(screen.queryByText(CARD_UNKNOWN)).toBeNull();
      expect(screen.queryByText(/recorded for this workspace/)).toBeNull();
      cleanup();
      seen += 1;
    }
    expect(seen).toBe(2);
    for (const c of [CARD_TRUE, CARD_UNKNOWN]) expect(c).not.toMatch(FORBIDDEN);
  });
});

describe("WebEgressToggle — enable dialog copy", () => {
  const open = (collection: boolean | "unknown") => {
    card({ collection });
    fireEvent.click(screen.getByRole("switch", { name: "Agent web access" }));
    return screen.getByRole("alertdialog");
  };

  it("never says every outbound request is logged", () => {
    let seen = 0;
    for (const c of [true, false, "unknown"] as const) {
      const dlg = open(c);
      expect(dlg.textContent).not.toMatch(/Every outbound request is logged/i);
      seen += 1;
      cleanup();
    }
    expect(seen).toBe(3);
  });

  it("collection on: shows the ruled best-effort notice (members, pre-join, no member or session, minimums, 30-day deletion, off keeps records)", () => {
    const text = open(true).textContent ?? "";
    expect(text).toContain(NOTICE_START);
    expect(text).toContain("Every current member of this workspace can view them, including activity from before they joined.");
    expect(text).toContain("No member or session is recorded, some entries may be missing, and counts are minimums.");
    expect(text).toContain("Records are deleted about 30 days after they were recorded.");
    expect(text).toContain("Turning web access off stops new records but does not delete existing ones.");
    expect(text).not.toContain(UNKNOWN_LEAD);
    expect(text).not.toMatch(FORBIDDEN);
  });

  it("collection unknown: says it could not check, then shows the full notice so an outage cannot hide the disclosure", () => {
    const text = open("unknown").textContent ?? "";
    expect(text).toContain(`${UNKNOWN_LEAD} ${NOTICE_START}`);
    expect(text).toContain("Turning web access off stops new records but does not delete existing ones.");
    expect(text).not.toMatch(FORBIDDEN);
  });

  it("collection off: no recording text at all", () => {
    const text = open(false).textContent ?? "";
    expect(text).not.toContain(NOTICE_START);
    expect(text).not.toContain(UNKNOWN_LEAD);
    expect(text).not.toMatch(/recorded/i);
  });
});
