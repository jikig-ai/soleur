import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen, cleanup } from "@testing-library/react";

// The badge derives its count from the SAME shared SWR key the Inbox Active
// tab uses (swrKeys.inboxEmails("active")), so we drive the component purely by
// controlling what `useSWR` returns — no network, no InboxSurface mount. We
// assert the honesty contract the user-impact-reviewer gates on (FR6): a
// loading/errored fetch must NEVER render as a false "0".
const useSWRMock = vi.fn();
vi.mock("swr", async (importOriginal) => {
  const actual = await importOriginal<typeof import("swr")>();
  return { ...actual, default: (...args: unknown[]) => useSWRMock(...args) };
});

function makeItems(n: number): Array<{ id: string }> {
  return Array.from({ length: n }, (_, i) => ({ id: `item-${i}` }));
}

beforeEach(() => {
  useSWRMock.mockReset();
});

afterEach(() => {
  cleanup();
});

async function renderBadge(collapsed = false) {
  const { InboxNavBadge } = await import(
    "@/components/dashboard/inbox-nav-badge"
  );
  return render(<InboxNavBadge collapsed={collapsed} />);
}

describe("InboxNavBadge", () => {
  it("keys the SAME shared SWR tuple the Inbox Active tab uses (TR3 — dedup)", async () => {
    useSWRMock.mockReturnValue({ data: makeItems(2), error: undefined });
    await renderBadge();
    const { swrKeys } = await import("@/lib/swr-config");
    // The badge must fetch under swrKeys.inboxEmails("active") so it coalesces
    // with InboxSurface's request rather than double-fetching /api/inbox/emails.
    expect(useSWRMock).toHaveBeenCalled();
    const passedKey = useSWRMock.mock.calls[0]![0];
    expect(passedKey).toEqual(swrKeys.inboxEmails("active"));
  });

  it("renders the active-item count as a neutral pill (FR2/FR5)", async () => {
    useSWRMock.mockReturnValue({ data: makeItems(3), error: undefined });
    await renderBadge();
    const badge = screen.getByTestId("inbox-nav-badge");
    expect(badge).toHaveTextContent("3");
    // Gold is reserved for the active-state (FR5) — the badge must NOT use it.
    expect(badge.className).not.toMatch(/gold/);
  });

  it("omits the badge entirely at count 0 — never an empty pill (FR3)", async () => {
    useSWRMock.mockReturnValue({ data: makeItems(0), error: undefined });
    await renderBadge();
    expect(screen.queryByTestId("inbox-nav-badge")).not.toBeInTheDocument();
    expect(
      screen.queryByTestId("inbox-nav-badge-collapsed"),
    ).not.toBeInTheDocument();
  });

  it("caps large counts at 99+ (FR5)", async () => {
    useSWRMock.mockReturnValue({ data: makeItems(150), error: undefined });
    await renderBadge();
    expect(screen.getByTestId("inbox-nav-badge")).toHaveTextContent("99+");
  });

  it("does NOT render a false 0 on fetch error — omits instead (FR6)", async () => {
    useSWRMock.mockReturnValue({
      data: undefined,
      error: new Error("inbox emails 500"),
    });
    await renderBadge();
    expect(screen.queryByTestId("inbox-nav-badge")).not.toBeInTheDocument();
    expect(screen.queryByText("0")).not.toBeInTheDocument();
  });

  it("does NOT render while the count is still loading (data undefined)", async () => {
    useSWRMock.mockReturnValue({ data: undefined, error: undefined });
    await renderBadge();
    expect(screen.queryByTestId("inbox-nav-badge")).not.toBeInTheDocument();
  });

  it("renders the corner-overlay variant with a rail-matching ring when collapsed (FR4)", async () => {
    useSWRMock.mockReturnValue({ data: makeItems(5), error: undefined });
    await renderBadge(true);
    const dot = screen.getByTestId("inbox-nav-badge-collapsed");
    expect(dot).toHaveTextContent("5");
    // The 2px ring cuts the dot out of the icon — it must match the rail bg
    // (the soleur-bg-surface-1 token) so it stays theme-correct.
    expect(dot.className).toMatch(/ring-soleur-bg-surface-1/);
  });

  it("does NOT render the collapsed corner variant when expanded", async () => {
    useSWRMock.mockReturnValue({ data: makeItems(5), error: undefined });
    await renderBadge(false);
    expect(
      screen.queryByTestId("inbox-nav-badge-collapsed"),
    ).not.toBeInTheDocument();
  });
});
