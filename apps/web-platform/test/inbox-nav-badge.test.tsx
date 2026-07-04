import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen, cleanup } from "@testing-library/react";
import type { MergedInboxItem } from "@/lib/inbox-severity";

// The badge derives its count from the SAME shared SWR key the Inbox Active tab
// uses (swrKeys.inbox("active")), so we drive it purely by controlling what
// useSWR returns. It counts OUTSTANDING action_required only, caps at 9+, shows
// a gold dot for unread FYI, and NEVER renders a false "0" (FR6).
const useSWRMock = vi.fn();
vi.mock("swr", async (importOriginal) => {
  const actual = await importOriginal<typeof import("swr")>();
  return { ...actual, default: (...args: unknown[]) => useSWRMock(...args) };
});

function action(n: number): MergedInboxItem[] {
  return Array.from({ length: n }, (_, i) => ({
    kind: "inbox" as const,
    id: `a${i}`,
    severity: "action_required" as const,
    pinned: false as const,
    outstanding: true,
    inbox: {
      id: `a${i}`,
      severity: "action_required" as const,
      source: "system" as const,
      title: "billing failed",
      source_ref: null,
      status: "unread",
      created_at: "2026-07-01T00:00:00.000Z",
      read_at: null,
      acted_at: null,
      archived_at: null,
    },
  }));
}

function fyi(n: number): MergedInboxItem[] {
  return Array.from({ length: n }, (_, i) => ({
    kind: "inbox" as const,
    id: `f${i}`,
    severity: "info" as const,
    pinned: false as const,
    outstanding: false,
    inbox: {
      id: `f${i}`,
      severity: "info" as const,
      source: "task_completed" as const,
      title: "Legal finished",
      source_ref: { conversationId: "c1" },
      status: "unread",
      created_at: "2026-07-01T00:00:00.000Z",
      read_at: null, // unread
      acted_at: null,
      archived_at: null,
    },
  }));
}

beforeEach(() => useSWRMock.mockReset());
afterEach(() => cleanup());

async function renderBadge(collapsed = false) {
  const { InboxNavBadge } = await import(
    "@/components/dashboard/inbox-nav-badge"
  );
  return render(<InboxNavBadge collapsed={collapsed} />);
}

describe("InboxNavBadge (outstanding action_required)", () => {
  it("keys the SAME shared SWR tuple the Inbox Active tab uses (dedup)", async () => {
    useSWRMock.mockReturnValue({ data: action(2), error: undefined });
    await renderBadge();
    const { swrKeys } = await import("@/lib/swr-config");
    expect(useSWRMock.mock.calls[0]![0]).toEqual(swrKeys.inbox("active"));
  });

  it("counts outstanding action_required only, with a decision-framed a11y name", async () => {
    useSWRMock.mockReturnValue({ data: [...action(3), ...fyi(4)], error: undefined });
    await renderBadge();
    const badge = screen.getByTestId("inbox-nav-badge");
    expect(badge).toHaveTextContent("3"); // FYI not counted
    expect(badge).toHaveAccessibleName("3 items need your decision");
    // Neutral fill (gold is reserved for active-state).
    expect(badge.className).toContain("bg-soleur-bg-badge");
  });

  it("uses the singular at count 1", async () => {
    useSWRMock.mockReturnValue({ data: action(1), error: undefined });
    await renderBadge();
    expect(screen.getByTestId("inbox-nav-badge")).toHaveAccessibleName(
      "1 item needs your decision",
    );
  });

  it("caps at 9+ (Appendix A): shows 9 at the boundary, 9+ above", async () => {
    useSWRMock.mockReturnValue({ data: action(9), error: undefined });
    const { unmount } = await renderBadge();
    expect(screen.getByTestId("inbox-nav-badge")).toHaveTextContent("9");
    unmount();
    useSWRMock.mockReturnValue({ data: action(10), error: undefined });
    await renderBadge();
    expect(screen.getByTestId("inbox-nav-badge")).toHaveTextContent("9+");
  });

  it("shows a gold FYI dot (no number) when only unread FYI is present", async () => {
    useSWRMock.mockReturnValue({ data: fyi(2), error: undefined });
    await renderBadge();
    expect(screen.queryByTestId("inbox-nav-badge")).not.toBeInTheDocument();
    const dot = screen.getByTestId("inbox-nav-badge-dot");
    expect(dot).toHaveAccessibleName("New updates in your inbox");
    expect(dot.className).toContain("bg-soleur-accent-gold-fill");
  });

  it("omits everything when nothing is outstanding and nothing is unread", async () => {
    // Acted action_required + a read FYI → nothing to surface.
    const read = fyi(1);
    read[0].kind === "inbox" && (read[0].inbox.read_at = "2026-07-02T00:00:00.000Z");
    useSWRMock.mockReturnValue({ data: read, error: undefined });
    await renderBadge();
    expect(screen.queryByTestId("inbox-nav-badge")).not.toBeInTheDocument();
    expect(screen.queryByTestId("inbox-nav-badge-dot")).not.toBeInTheDocument();
    expect(screen.queryByText("0")).not.toBeInTheDocument();
  });

  it("omits on a COLD fetch error — never a false 0 (FR6)", async () => {
    useSWRMock.mockReturnValue({ data: undefined, error: new Error("inbox 500") });
    await renderBadge();
    expect(screen.queryByTestId("inbox-nav-badge")).not.toBeInTheDocument();
    expect(screen.queryByText("0")).not.toBeInTheDocument();
  });

  it("keeps the last-good count on a WARM revalidation error (FR6)", async () => {
    useSWRMock.mockReturnValue({ data: action(6), error: new Error("revalidate") });
    await renderBadge();
    expect(screen.getByTestId("inbox-nav-badge")).toHaveTextContent("6");
  });

  it("does NOT render while loading (data undefined)", async () => {
    useSWRMock.mockReturnValue({ data: undefined, error: undefined });
    await renderBadge();
    expect(screen.queryByTestId("inbox-nav-badge")).not.toBeInTheDocument();
  });

  it("renders the collapsed corner variant with a rail-matching ring", async () => {
    useSWRMock.mockReturnValue({ data: action(5), error: undefined });
    await renderBadge(true);
    const dot = screen.getByTestId("inbox-nav-badge-collapsed");
    expect(dot).toHaveTextContent("5");
    expect(dot.className).toMatch(/ring-soleur-bg-surface-1/);
    expect(dot).toHaveAttribute("aria-hidden", "true");
  });
});
