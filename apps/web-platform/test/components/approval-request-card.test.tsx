/**
 * #4672 task 3.1: the durable approval card, every wireframe state.
 *
 * The card is a state machine fed by props, so the transition tests RERENDER the same mounted component (a remount would
 * hide a stale-state bug). Synthesized data only.
 */
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { useState } from "react";
import { act, cleanup, fireEvent, render, screen, waitFor } from "@testing-library/react";
import { ApprovalRequestCard, APPROVAL_DECIDE_REPLY_TIMEOUT_MS, type ApprovalRequestCardProps } from "@/components/chat/approval-request-card";
import { canonicalizeAction } from "@/server/approval/canonical";
import { renderApprovalView } from "@/server/approval/render";
import { SAMPLES, TOOLS } from "../approval/fixtures";

const APPROVAL_ID = "00000000-0000-4000-8000-000000000006";
const NOW = Date.parse("2026-10-28T10:00:00Z");
const view = (tool: string = TOOLS.emailSend, s = SAMPLES[tool]) => renderApprovalView(canonicalizeAction(tool, s.input, s.server));

function props(over: Partial<ApprovalRequestCardProps> = {}): ApprovalRequestCardProps {
  return {
    approvalId: APPROVAL_ID,
    view: view(),
    status: "pending",
    expiresAt: "2026-10-29T09:41:00Z",
    requestCount: 1,
    viewerRole: "owner",
    agentWaiting: true,
    onDecide: vi.fn(() => true),
    now: () => NOW,
    ...over,
  };
}

const card = () => screen.getByTestId("approval-request-card");
const state = () => card().getAttribute("data-approval-state");

beforeEach(() => {
  vi.useRealTimers();
});
afterEach(() => {
  cleanup();
  vi.useRealTimers();
});

describe("pending, Owner (wireframes 01, 04A1, 04A2)", () => {
  it("shows the bound block, the fixed Approve and Deny, the consequence line and the single-use line", () => {
    const v = view();
    render(<ApprovalRequestCard {...props({ view: v })} />);
    expect(state()).toBe("pending_owner");
    expect(screen.getByText(v.title)).toBeTruthy();
    for (const f of v.fields) expect(screen.getByTestId("approval-bound-block").textContent).toContain(f.value);
    expect(screen.getByText(v.consequence)).toBeTruthy();
    expect(screen.getByText(v.singleUse)).toBeTruthy();
    expect(screen.getByRole("button", { name: "Approve" })).toBeTruthy();
    expect(screen.getByRole("button", { name: "Deny" })).toBeTruthy();
    // No "Approve all", no remember-this: exactly two decision buttons.
    expect(screen.getAllByRole("button")).toHaveLength(2);
  });

  it("renders the countdown chip and turns amber under one hour", () => {
    const { rerender } = render(<ApprovalRequestCard {...props()} />);
    expect(screen.getByTestId("approval-expiry").textContent).toContain("Expires in 23h 41m");
    rerender(<ApprovalRequestCard {...props({ expiresAt: "2026-10-28T10:38:00Z" })} />);
    expect(screen.getByTestId("approval-expiry").textContent).toContain("Expires in 38m");
    expect(screen.getByTestId("approval-expiry").className).toContain("amber");
  });

  it("shows the 'agent stopped waiting' sub-line only after the wait ends (04A1 vs 04A2)", () => {
    const { rerender } = render(<ApprovalRequestCard {...props({ agentWaiting: true })} />);
    expect(screen.queryByTestId("approval-subline")).toBeNull();
    rerender(<ApprovalRequestCard {...props({ agentWaiting: false })} />);
    expect(screen.getByTestId("approval-subline").textContent).toBe("Your agent stopped waiting after 5 minutes");
  });

  it("shows the request-count header from request 2 onward (04M) and not for the first request", () => {
    const { rerender } = render(<ApprovalRequestCard {...props({ requestCount: 1 })} />);
    expect(screen.queryByTestId("approval-request-count")).toBeNull();
    rerender(<ApprovalRequestCard {...props({ requestCount: 3 })} />);
    expect(screen.getByTestId("approval-request-count").textContent).toBe("The agent asked again, request 3");
  });

  it("shows the newer-request banner on an older decidable card (04L) and keeps it decidable", () => {
    render(<ApprovalRequestCard {...props({ newerRequestExists: true })} />);
    expect(screen.getByTestId("approval-newer-banner").textContent).toContain("A newer request from your agent exists");
    expect(screen.getByRole("button", { name: "Approve" })).toBeTruthy();
  });

  it("the workspace-autonomy card is the danger variant", () => {
    render(<ApprovalRequestCard {...props({ view: view(TOOLS.setAutonomous) })} />);
    expect(card().className).toContain("red");
  });
});

describe("pending, non-owner (wireframe 05)", () => {
  it("renders read-only: the exact action, the waiting title, NO buttons at all (absent, not disabled)", () => {
    const v = view();
    render(<ApprovalRequestCard {...props({ viewerRole: "member", view: v })} />);
    expect(state()).toBe("pending_member");
    expect(screen.getByText("Waiting for the workspace Owner")).toBeTruthy();
    expect(screen.getByTestId("approval-bound-block").textContent).toContain(v.fields[0].value);
    expect(screen.getByTestId("approval-member-role").textContent).toContain("only they can decide");
    expect(screen.queryAllByRole("button")).toHaveLength(0);
    expect(screen.queryByText("Approve")).toBeNull();
  });
});

describe("resolved states (wireframe 04)", () => {
  const cases: Array<[string, Partial<ApprovalRequestCardProps>, string, RegExp]> = [
    ["released (consumed)", { status: "consumed", agentWaiting: false }, "released", /Released, your agent is continuing/],
    ["denied (04E)", { status: "rejected" }, "denied", /You denied this email/],
    ["expired unanswered (04F)", { status: "expired" }, "expired", /Nobody decided in time/],
    ["expired after approval (04H)", { status: "expired", expiredAfterApproval: true }, "expired_after_approval", /You approved this, but your agent never asked again/],
    ["already decided (04I)", { status: "approved", decideOutcome: "conflict" }, "already_decided", /Already decided/],
    ["already decided by another Owner", { status: "approved", decideOutcome: "already_decided" }, "already_decided", /Already decided by another Owner/],
    ["revoked", { status: "rejected", decideOutcome: "revoked" }, "revoked", /Approval revoked/],
    ["revoked (row says so)", { status: "rejected", revoked: true }, "revoked", /Approval revoked/],
    ["conversation closed (04J)", { status: "pending", decideOutcome: "closed" }, "conversation_closed", /This conversation is closed/],
    ["details removed (04K)", { view: null }, "details_removed", /Details removed per retention policy/],
  ];
  for (const [name, over, expected, title] of cases) {
    it(`${name}: no buttons, correct state and title, no outcome claim`, () => {
      render(<ApprovalRequestCard {...props(over)} />);
      expect(state()).toBe(expected);
      expect(screen.getByRole("heading").textContent).toMatch(title);
      expect(screen.queryAllByRole("button")).toHaveLength(0);
      expect(card().textContent).not.toMatch(/\b(sent|executed|delivered)\b|\bran\b(?! nothing\b)/i);
    });
  }

  it("a revoke tap answered with a conflict on a used request reads as released with the too-late copy, not as a lost race", async () => {
    const { rerender } = render(<ApprovalRequestCard {...props({ status: "approved", agentWaiting: false })} />);
    await act(async () => {
      fireEvent.click(screen.getByRole("button", { name: "Revoke approval" }));
    });
    rerender(<ApprovalRequestCard {...props({ status: "consumed", decideOutcome: "conflict" })} />);
    expect(state()).toBe("released");
    expect(screen.getByRole("heading").textContent).toBe("Your revoke came too late: your agent had already used this approval");
  });

  it("an APPROVE tap answered with a conflict on a used request is NOT 'revoke too late' (a second Owner never revoked anything)", async () => {
    const { rerender } = render(<ApprovalRequestCard {...props({})} />);
    await act(async () => {
      fireEvent.click(screen.getByRole("button", { name: "Approve" }));
    });
    rerender(<ApprovalRequestCard {...props({ status: "consumed", decideOutcome: "conflict" })} />);
    expect(state()).toBe("released");
    const heading = screen.getByRole("heading").textContent ?? "";
    expect(heading).not.toMatch(/revoke/i);
    expect(heading).toBe("Released, your agent is continuing");
  });

  it("a released card without a lost revoke keeps its ordinary title", () => {
    render(<ApprovalRequestCard {...props({ status: "consumed" })} />);
    expect(screen.getByRole("heading").textContent).toBe("Released, your agent is continuing");
  });

  it("the released card says what the agent does next is not reported", () => {
    render(<ApprovalRequestCard {...props({ status: "consumed" })} />);
    expect(screen.getByTestId("approval-info").textContent).toContain("Released to your agent");
    expect(screen.getByTestId("approval-info").textContent).toContain("this card does not report an outcome");
  });

  it("the loser state names who decided when the caller knows, and is neutral otherwise", () => {
    const { rerender } = render(<ApprovalRequestCard {...props({ status: "approved", decideOutcome: "conflict" })} />);
    expect(screen.getByRole("heading").textContent).toBe("Already decided");
    rerender(<ApprovalRequestCard {...props({ status: "approved", decideOutcome: "conflict", alreadyDecidedBy: { name: "Priya", role: "Owner" } })} />);
    expect(screen.getByRole("heading").textContent).toBe("Already decided by Priya (Owner)");
  });

  it("details removed names the day count only when the row is at least that many days past its end (the scheduled scrub); otherwise the neutral line", () => {
    const now = Date.parse("2026-12-15T00:00:00Z");
    const infoFor = (endedAt: string | null | undefined) => {
      const { unmount } = render(<ApprovalRequestCard {...props({ view: null, endedAt, now: () => now })} />);
      const t = screen.getByTestId("approval-info").textContent;
      unmount();
      return t;
    };
    expect(infoFor("2026-11-10T00:00:00Z")).toContain("removed 30 days after this request ended");
    expect(infoFor("2026-11-20T00:00:00Z")).toBe(
      "The action details have been removed. We keep the kind of action, its status and its times, and, unless that person's account has been erased, who asked and who decided.",
    );
    expect(infoFor(undefined)).not.toMatch(/\d+ days/);
    expect(infoFor("not a date")).not.toMatch(/\d+ days/);
  });

  it("details removed shows no bound block and no stale values", () => {
    render(<ApprovalRequestCard {...props({ view: null })} />);
    expect(screen.queryByTestId("approval-bound-block")).toBeNull();
  });

  it("shows the decided meta label on a resolved card", () => {
    render(<ApprovalRequestCard {...props({ status: "rejected", decidedLabel: "Wed 28 Oct, 10:44 UTC · by you" })} />);
    expect(screen.getByTestId("approval-decided-label").textContent).toContain("by you");
  });
});

describe("an approved request that can no longer be used (decider lost Owner standing, or requester left)", () => {
  it("never says 'ask again' or that asking again is allowed, and says what to do instead", () => {
    render(<ApprovalRequestCard {...props({ status: "approved", agentWaiting: false, approvalUnusable: true })} />);
    expect(state()).toBe("approved_late");
    expect(screen.getByRole("heading").textContent).toBe("Approved, but this approval can no longer be used");
    expect(screen.getByTestId("approval-badge").textContent).toBe("Approved · unusable");
    const text = card().textContent ?? "";
    expect(text).not.toMatch(/ask(ing)? (it |your agent )?again|is allowed/i);
    expect(screen.getByTestId("approval-info").textContent).toMatch(/revoke it, or wait for it to expire, then start a new request/);
  });

  it("an ordinary late approval still invites asking again", () => {
    render(<ApprovalRequestCard {...props({ status: "approved", agentWaiting: false })} />);
    expect(screen.getByRole("heading").textContent).toBe("Approved. Ask your agent again.");
  });
});

describe("state transitions on ONE mounted card (rerender, not remount)", () => {
  it("pending -> approved(late) -> consumed and pending -> denied", () => {
    const { rerender, container } = render(<ApprovalRequestCard {...props({ agentWaiting: false })} />);
    const el = container.firstElementChild;
    expect(state()).toBe("pending_owner");
    rerender(<ApprovalRequestCard {...props({ status: "approved", agentWaiting: false })} />);
    expect(state()).toBe("approved_late");
    rerender(<ApprovalRequestCard {...props({ status: "consumed", agentWaiting: false })} />);
    expect(state()).toBe("released");
    expect(container.firstElementChild).toBe(el); // same DOM node: it was not remounted
    rerender(<ApprovalRequestCard {...props({ status: "rejected" })} />);
    expect(state()).toBe("denied");
  });
});

describe("deciding (fail closed)", () => {
  it("Approve and Deny call onDecide with the closed decision enum", async () => {
    const onDecide = vi.fn(() => true);
    const { rerender } = render(<ApprovalRequestCard {...props({ onDecide })} />);
    await act(async () => {
      fireEvent.click(screen.getByRole("button", { name: "Approve" }));
    });
    expect(onDecide).toHaveBeenCalledWith("approve");
    // server replies: the card changes only now
    rerender(<ApprovalRequestCard {...props({ onDecide, status: "approved", agentWaiting: false, decideOutcome: "decided" })} />);
    expect(state()).toBe("approved_late");
  });

  it("locks both buttons while the decision is in flight and shows 'Approving…' with no optimistic state", async () => {
    const onDecide = vi.fn(() => true);
    render(<ApprovalRequestCard {...props({ onDecide })} />);
    await act(async () => {
      fireEvent.click(screen.getByRole("button", { name: "Approve" }));
    });
    expect(state()).toBe("pending_owner"); // NOT approved: the server has not said so
    const approve = screen.getByRole("button", { name: /Approving/ });
    expect(approve.getAttribute("aria-busy")).toBe("true");
    expect((screen.getByRole("button", { name: "Deny" }) as HTMLButtonElement).disabled).toBe(true);
    expect(screen.getByText("Recording your decision…")).toBeTruthy();
  });

  it("a double click sends one decision", async () => {
    const onDecide = vi.fn(() => true);
    render(<ApprovalRequestCard {...props({ onDecide })} />);
    const btn = screen.getByRole("button", { name: "Approve" });
    await act(async () => {
      fireEvent.click(btn);
      fireEvent.click(btn);
    });
    expect(onDecide).toHaveBeenCalledTimes(1);
  });

  it("a decision that could not be sent shows a static error, keeps the card pending and unlocks the buttons", async () => {
    const onDecide = vi.fn(() => false);
    render(<ApprovalRequestCard {...props({ onDecide })} />);
    await act(async () => {
      fireEvent.click(screen.getByRole("button", { name: "Approve" }));
    });
    expect(screen.getByTestId("approval-decide-error").textContent).toContain("couldn't confirm your decision");
    expect(state()).toBe("pending_owner");
    expect((screen.getByRole("button", { name: "Approve" }) as HTMLButtonElement).disabled).toBe(false);
  });

  it("a thrown onDecide is the same static error (never the error message)", async () => {
    const onDecide = vi.fn(() => {
      throw new Error("secret internal detail");
    });
    render(<ApprovalRequestCard {...props({ onDecide })} />);
    await act(async () => {
      fireEvent.click(screen.getByRole("button", { name: "Deny" }));
    });
    expect(screen.getByRole("alert").textContent).not.toContain("secret internal detail");
    expect(state()).toBe("pending_owner");
  });

  it("a reply that never arrives ends in the static error after the reply timeout (no hang, no approved state)", async () => {
    vi.useFakeTimers();
    const onDecide = vi.fn(() => true);
    render(<ApprovalRequestCard {...props({ onDecide })} />);
    await act(async () => {
      fireEvent.click(screen.getByRole("button", { name: "Approve" }));
    });
    expect(screen.queryByTestId("approval-decide-error")).toBeNull();
    await act(async () => {
      await vi.advanceTimersByTimeAsync(APPROVAL_DECIDE_REPLY_TIMEOUT_MS + 200);
    });
    expect(screen.getByTestId("approval-decide-error")).toBeTruthy();
    expect(state()).toBe("pending_owner");
  });

  it("a reply that lands BEFORE the wait starts is not missed (async onDecide that settles the card itself)", async () => {
    let setProps: (p: Partial<ApprovalRequestCardProps>) => void = () => {};
    function Harness() {
      const [over, set] = useState<Partial<ApprovalRequestCardProps>>({});
      setProps = set;
      return <ApprovalRequestCard {...props({ ...over, onDecide: async () => { set({ status: "rejected" }); return true; } })} />;
    }
    render(<Harness />);
    await act(async () => {
      fireEvent.click(screen.getByRole("button", { name: "Deny" }));
    });
    await waitFor(() => expect(state()).toBe("denied"));
    expect(screen.queryByTestId("approval-decide-error")).toBeNull();
    void setProps;
  });
});

describe("landing layout (wireframe 07b)", () => {
  it("stacks full-width Approve above Deny", () => {
    render(<ApprovalRequestCard {...props({ layout: "landing" })} />);
    const approve = screen.getByRole("button", { name: "Approve" });
    const deny = screen.getByRole("button", { name: "Deny" });
    expect(approve.className).toContain("w-full");
    expect(approve.className).toContain("order-1");
    expect(deny.className).toContain("order-2");
  });
});

describe("revoke: an approved, unconsumed request can be taken back (CTO ruling 2)", () => {
  it.each([
    ["approved, agent waiting (released)", { status: "approved" as const, agentWaiting: true }, "released"],
    ["approved, agent stopped waiting (04D)", { status: "approved" as const, agentWaiting: false }, "approved_late"],
  ])("%s: shows 'Revoke approval' and no Approve/Deny; the click sends deny", async (_n, over, expected) => {
    const onDecide = vi.fn(() => true);
    render(<ApprovalRequestCard {...props({ ...over, onDecide })} />);
    expect(state()).toBe(expected);
    expect(screen.queryByRole("button", { name: "Approve" })).toBeNull();
    expect(screen.queryByRole("button", { name: "Deny" })).toBeNull();
    await act(async () => {
      fireEvent.click(screen.getByRole("button", { name: "Revoke approval" }));
    });
    expect(onDecide).toHaveBeenCalledWith("deny");
  });

  it("never offered on a used (consumed), pending, denied or expired request, or to a member", () => {
    for (const over of [{ status: "consumed" as const }, { status: "pending" as const }, { status: "rejected" as const }, { status: "expired" as const }]) {
      const { unmount } = render(<ApprovalRequestCard {...props(over)} />);
      expect(screen.queryByRole("button", { name: "Revoke approval" })).toBeNull();
      unmount();
    }
    render(<ApprovalRequestCard {...props({ status: "approved", viewerRole: "member" })} />);
    expect(screen.queryByRole("button", { name: "Revoke approval" })).toBeNull();
  });

  it("settles to the revoked state only on the server's word (rerender), and the button disappears", async () => {
    const { rerender } = render(<ApprovalRequestCard {...props({ status: "approved", agentWaiting: false })} />);
    await act(async () => {
      fireEvent.click(screen.getByRole("button", { name: "Revoke approval" }));
    });
    expect(state()).toBe("approved_late"); // no optimistic state
    rerender(<ApprovalRequestCard {...props({ status: "rejected", decideOutcome: "revoked" })} />);
    expect(state()).toBe("revoked");
    expect(screen.getByTestId("approval-info").textContent).toBe("Revoked. Your agent cannot use this approval.");
    expect(screen.queryAllByRole("button")).toHaveLength(0);
  });

  it("a revoke that lost the race to the agent's repeat unlocks into the released state", async () => {
    const { rerender } = render(<ApprovalRequestCard {...props({ status: "approved", agentWaiting: false })} />);
    await act(async () => {
      fireEvent.click(screen.getByRole("button", { name: "Revoke approval" }));
    });
    rerender(<ApprovalRequestCard {...props({ status: "consumed", decideOutcome: "conflict" })} />);
    expect(state()).toBe("released");
    expect(screen.getByRole("heading").textContent).toBe("Your revoke came too late: your agent had already used this approval");
    expect(screen.queryByRole("button", { name: "Revoke approval" })).toBeNull();
  });
});

describe("the card renders agent-authored values as inert, untruncated text", () => {
  it("renders markup-looking values as text, never as elements", () => {
    const s = SAMPLES[TOOLS.emailSend];
    const v = renderApprovalView(canonicalizeAction(TOOLS.emailSend, { ...s.input, body: "<img src=x onerror=alert(1)> **bold** [x](javascript:alert(1))" }, {}));
    render(<ApprovalRequestCard {...props({ view: v })} />);
    expect(document.querySelector("img")).toBeNull();
    expect(document.querySelector("a")).toBeNull();
    expect(screen.getByTestId("approval-bound-block").textContent).toContain("<img src=x onerror=alert(1)> **bold**");
  });

  it("makes a right-to-left override in a recipient visible instead of letting it spoof", () => {
    const s = SAMPLES[TOOLS.emailSend];
    const v = renderApprovalView(canonicalizeAction(TOOLS.emailSend, { ...s.input, to: "ok@example.test\u202Etxt.evil" }, {}));
    render(<ApprovalRequestCard {...props({ view: v })} />);
    expect(screen.getByTestId("approval-bound-block").textContent).toContain("<U+202E>");
    expect(screen.getByTestId("approval-bound-block").textContent).not.toContain("\u202E");
  });

  it("a long body scrolls inside the card with a visible 'N more lines' marker and loses no line", () => {
    const s = SAMPLES[TOOLS.emailSend];
    const body = Array.from({ length: 40 }, (_, i) => `line ${i + 1}`).join("\n");
    const v = renderApprovalView(canonicalizeAction(TOOLS.emailSend, { ...s.input, body }, {}));
    render(<ApprovalRequestCard {...props({ view: v })} />);
    expect(screen.getByText("26 more lines")).toBeTruthy();
    const region = screen.getByRole("region", { name: /BODY, 40 lines, scrollable/ });
    expect(region.textContent).toBe(body);
  });

  it("a short body has no scroll region or marker", () => {
    render(<ApprovalRequestCard {...props()} />);
    expect(screen.queryByRole("region")).toBeNull();
    expect(screen.queryByText(/more lines/)).toBeNull();
  });
});

describe("accessibility", () => {
  it("the card is a labelled group named by its title, and busy while deciding", async () => {
    render(<ApprovalRequestCard {...props()} />);
    const g = screen.getByRole("group");
    expect(g.getAttribute("aria-labelledby")).toBe(screen.getByRole("heading").id);
    expect(g.getAttribute("aria-busy")).toBe("false");
  });
});

// ---------------------------------------------------------------------------------------------------------------------
// #9601: the requester line on the Owner card, and the withheld (redacted) member card.
// ---------------------------------------------------------------------------------------------------------------------
describe("requester line on the Owner card (#9601)", () => {
  const line = () => screen.getByTestId("approval-requester");

  it.each([
    ["jane@example.com", "Requested by jane@example.com"],
    ["you", "Requested by you"],
    ["a workspace member", "Requested by a workspace member"],
  ])("renders the label %s as '%s'", (requester, text) => {
    render(<ApprovalRequestCard {...props({ requester })} />);
    expect(state()).toBe("pending_owner");
    expect(line().textContent).toBe(text);
  });

  it("no requester prop: no requester line at all (a failed lookup omits the key, it never invents one)", () => {
    render(<ApprovalRequestCard {...props()} />);
    expect(screen.queryByTestId("approval-requester")).toBeNull();
  });

  it("the label is a plain text node: no link, no mailto, no markup", () => {
    render(<ApprovalRequestCard {...props({ requester: "jane@example.com" })} />);
    expect(card().querySelector('a[href^="mailto:"]')).toBeNull();
    expect(line().querySelector("a")).toBeNull();
    const { unmount } = render(<ApprovalRequestCard {...props({ requester: "<b>x</b>@example.com" })} />);
    expect(screen.getAllByTestId("approval-requester").some((el) => el.textContent === "Requested by <b>x</b>@example.com")).toBe(true);
    expect(document.querySelector("b")).toBeNull();
    unmount();
  });

  it("a right-to-left override in the label is made visible, not obeyed", () => {
    render(<ApprovalRequestCard {...props({ requester: "jane‮evil@example.com" })} />);
    expect(line().textContent).toContain("<U+202E>");
    expect(line().textContent).not.toContain("‮");
  });

  it("a 254-character address wraps (the wrap classes are on the label) and is never truncated", () => {
    const long = `${"a".repeat(254 - "@example.com".length)}@example.com`;
    render(<ApprovalRequestCard {...props({ requester: long })} />);
    expect(line().textContent).toContain(long);
    const wrapEl = line().querySelector("span") ?? line();
    expect(`${line().className} ${wrapEl.className}`).toContain("[overflow-wrap:anywhere]");
    expect(`${line().className} ${wrapEl.className}`).toContain("min-w-0");
    expect(`${line().className} ${wrapEl.className}`).not.toMatch(/truncate|text-ellipsis|line-clamp/);
  });

  it("the line sits outside the aria-live region and above the title", () => {
    render(<ApprovalRequestCard {...props({ requester: "jane@example.com" })} />);
    expect(line().closest("[aria-live]")).toBeNull();
    const heading = screen.getByRole("heading");
    expect(line().compareDocumentPosition(heading) & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy();
  });

  it("the landing layout shows the same line", () => {
    render(<ApprovalRequestCard {...props({ layout: "landing", requester: "jane@example.com", agentWaiting: false })} />);
    expect(line().textContent).toBe("Requested by jane@example.com");
  });

  it("a scrubbed Owner card (details removed) hides the requester line", () => {
    render(<ApprovalRequestCard {...props({ view: null, requester: "jane@example.com" })} />);
    expect(state()).toBe("details_removed");
    expect(screen.queryByTestId("approval-requester")).toBeNull();
  });

  it("an Owner card with a label keeps Approve and Deny", () => {
    render(<ApprovalRequestCard {...props({ requester: "jane@example.com" })} />);
    expect(screen.getByRole("button", { name: "Approve" })).toBeTruthy();
    expect(screen.getByRole("button", { name: "Deny" })).toBeTruthy();
  });
});

describe("withheld member card (#9601)", () => {
  const WAITING = "An action in this conversation is waiting for an Owner's approval.";
  const withheld = (over: Partial<ApprovalRequestCardProps> = {}) => props({ view: null, viewerRole: "member", ...over });

  it("pending: the waiting copy, no bound block, no buttons, never 'Details removed'", () => {
    render(<ApprovalRequestCard {...withheld()} />);
    expect(state()).toBe("pending_member");
    expect(screen.getByRole("heading").textContent).toBe(WAITING);
    expect(screen.queryByTestId("approval-bound-block")).toBeNull();
    expect(screen.queryAllByRole("button")).toHaveLength(0);
    expect(card().textContent).not.toMatch(/Details removed/i);
    expect(screen.queryByTestId("approval-requester")).toBeNull();
  });

  it("pending: keeps the countdown and the member role line (time, not action text)", () => {
    render(<ApprovalRequestCard {...withheld()} />);
    expect(screen.getByTestId("approval-expiry").textContent).toContain("Expires in 23h 41m");
    expect(screen.getByTestId("approval-member-role").textContent).toContain("only they can decide");
  });

  it("the newer-request banner never renders on a withheld card (two redacted cards share a tool name)", () => {
    render(<ApprovalRequestCard {...withheld({ newerRequestExists: true })} />);
    expect(screen.queryByTestId("approval-newer-banner")).toBeNull();
  });

  it("the requester member keeps the full bound block and reads 'You requested this. Waiting for an Owner's approval.'", () => {
    const v = view();
    render(<ApprovalRequestCard {...props({ viewerRole: "member", view: v, requester: "you" })} />);
    expect(state()).toBe("pending_member");
    expect(screen.getByRole("heading").textContent).toBe("You requested this. Waiting for an Owner's approval.");
    for (const f of v.fields) expect(screen.getByTestId("approval-bound-block").textContent).toContain(f.value);
    expect(screen.queryAllByRole("button")).toHaveLength(0);
  });

  it("a member with a full view and no label keeps the existing wording", () => {
    render(<ApprovalRequestCard {...props({ viewerRole: "member", view: view() })} />);
    expect(screen.getByRole("heading").textContent).toBe("Waiting for the workspace Owner");
  });

  // Defensive: the server never sends a non-pending status to a withheld card, but if one arrives the card must not
  // state anything the viewer cannot see (no bound block) and must not speak of "your agent" or "continuing".
  it.each([
    ["consumed", { status: "consumed" as const, agentWaiting: false }],
    ["approved, agent waiting", { status: "approved" as const, agentWaiting: true }],
    ["approved, agent gone", { status: "approved" as const, agentWaiting: false }],
    ["rejected", { status: "rejected" as const }],
    ["expired", { status: "expired" as const }],
    ["expired after approval", { status: "expired" as const, expiredAfterApproval: true }],
    ["revoked", { status: "rejected" as const, revoked: true }],
  ])("a withheld card handed a non-pending status (%s) shows no bound block and no agent claims", (_n, over) => {
    render(<ApprovalRequestCard {...withheld(over)} />);
    expect(screen.queryByTestId("approval-bound-block")).toBeNull();
    expect(screen.queryAllByRole("button")).toHaveLength(0);
    const text = card().textContent ?? "";
    expect(text).not.toMatch(/your agent/i);
    expect(text).not.toMatch(/continuing/i);
    expect(text).not.toMatch(/Details removed/i);
    expect(text).not.toMatch(/\b(sent|executed|delivered)\b|\bran\b/i);
    expect(text).not.toContain("email"); // the generic noun is 'request'
  });
});
