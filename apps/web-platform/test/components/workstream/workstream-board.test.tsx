import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import {
  cleanup,
  fireEvent,
  render,
  screen,
  waitFor,
} from "@testing-library/react";
import type { WorkstreamIssue } from "@/lib/workstream";

// next/navigation mocked: `mockIssue` drives the ?issue= param (deep-link
// hydration). The drawer is now driven by LOCAL state — open uses
// window.history.pushState (so Back can pop it), close uses replaceState
// (spied), NOT router navigation.
let mockIssue: string | null = null;
vi.mock("next/navigation", () => ({
  usePathname: () => "/dashboard/workstream",
  useSearchParams: () =>
    new URLSearchParams(mockIssue ? `issue=${mockIssue}` : ""),
}));

import { WorkstreamBoard } from "@/components/workstream/workstream-board";
import { SwrTestProvider } from "../../helpers/swr-wrapper";

function Wrapped() {
  return (
    <SwrTestProvider>
      <WorkstreamBoard />
    </SwrTestProvider>
  );
}

function issue(over: Partial<WorkstreamIssue> = {}): WorkstreamIssue {
  return {
    id: "SOLAA-900",
    title: "Seed issue",
    description: "desc",
    status: "backlog",
    priority: "medium",
    assigneeRole: "cto",
    createdAt: "2026-06-20T09:00:00.000Z",
    updatedAt: "2026-06-20T09:00:00.000Z",
    ...over,
  };
}

function mockFetchOnce(issues: WorkstreamIssue[], ok = true) {
  return vi.fn().mockResolvedValue({ ok, json: async () => ({ issues }) });
}

beforeEach(() => {
  mockIssue = null;
  try {
    window.localStorage.clear();
  } catch {
    /* no-op */
  }
});
afterEach(() => {
  cleanup();
  vi.restoreAllMocks();
});

describe("WorkstreamBoard", () => {
  it("renders the 7 columns with the Preview banner", async () => {
    global.fetch = mockFetchOnce([
      issue({ id: "SOLAA-1", title: "Card one" }),
    ]) as unknown as typeof fetch;

    render(<Wrapped />);

    await waitFor(() => expect(screen.getByText("Card one")).toBeTruthy());
    for (const label of [
      "Backlog",
      "Todo",
      "In Progress",
      "In Review",
      "Blocked",
      "Done",
      "Cancelled",
    ]) {
      expect(screen.getByRole("heading", { name: label })).toBeTruthy();
    }
    expect(screen.getByText("Preview")).toBeTruthy();
    expect(
      screen.getByText(/changes aren.?t saved yet/i),
    ).toBeTruthy();
  });

  it("filters by id + title and shows a combined filtered-empty state with a Reset action", async () => {
    global.fetch = mockFetchOnce([
      issue({ id: "SOLAA-1", title: "Wire the store" }),
      issue({ id: "SOLAA-2", title: "Draft copy" }),
    ]) as unknown as typeof fetch;

    render(<Wrapped />);
    await waitFor(() => expect(screen.getByText("Wire the store")).toBeTruthy());

    fireEvent.change(screen.getByLabelText("Search issues"), {
      target: { value: "zzzznope" },
    });
    expect(
      screen.getByText(/No issues match your filters or search/i),
    ).toBeTruthy();

    // Two "Reset filters" buttons exist (top bar + empty state); either clears
    // search + filters. Click the last (the empty-state action).
    const resets = screen.getAllByRole("button", { name: /reset filters/i });
    fireEvent.click(resets[resets.length - 1]);
    await waitFor(() => expect(screen.getByText("Wire the store")).toBeTruthy());
    expect(
      (screen.getByLabelText("Search issues") as HTMLInputElement).value,
    ).toBe("");
  });

  it("Reset filters is disabled with no active filters/search and enabled once active", async () => {
    global.fetch = mockFetchOnce([
      issue({ id: "SOLAA-1", title: "Wire the store" }),
    ]) as unknown as typeof fetch;
    render(<Wrapped />);
    await waitFor(() => expect(screen.getByText("Wire the store")).toBeTruthy());

    const reset = screen.getByRole("button", { name: /reset filters/i });
    expect((reset as HTMLButtonElement).disabled).toBe(true);

    fireEvent.change(screen.getByLabelText("Search issues"), {
      target: { value: "wire" },
    });
    expect(
      (screen.getByRole("button", { name: /reset filters/i }) as HTMLButtonElement)
        .disabled,
    ).toBe(false);
  });

  it("Refresh refetches and KEEPS active search applied to the fresh set", async () => {
    const fetcher = vi
      .fn()
      .mockResolvedValue({
        ok: true,
        json: async () => ({
          issues: [
            issue({ id: "SOLAA-1", title: "Wire the store" }),
            issue({ id: "SOLAA-2", title: "Draft copy" }),
          ],
        }),
      });
    global.fetch = fetcher as unknown as typeof fetch;
    render(<Wrapped />);
    await waitFor(() => expect(screen.getByText("Wire the store")).toBeTruthy());

    // Apply a search that excludes "Draft copy".
    fireEvent.change(screen.getByLabelText("Search issues"), {
      target: { value: "wire" },
    });
    expect(screen.queryByText("Draft copy")).toBeNull();

    const callsBefore = fetcher.mock.calls.length;
    fireEvent.click(screen.getByRole("button", { name: /refresh/i }));
    await waitFor(() =>
      expect(fetcher.mock.calls.length).toBeGreaterThan(callsBefore),
    );
    // Search survived the refresh: the filtered-out card stays out.
    await waitFor(() => expect(screen.getByText("Wire the store")).toBeTruthy());
    expect(screen.queryByText("Draft copy")).toBeNull();
  });

  it("a failed Refresh (with existing data) shows the inline notice, then clears it on a later success", async () => {
    global.fetch = mockFetchOnce([
      issue({ id: "SOLAA-1", title: "Wire the store" }),
    ]) as unknown as typeof fetch;
    render(<Wrapped />);
    await waitFor(() => expect(screen.getByText("Wire the store")).toBeTruthy());

    // Next revalidation rejects → inline "couldn't refresh" notice, data retained.
    global.fetch = vi
      .fn()
      .mockResolvedValue({ ok: false, json: async () => ({}) }) as unknown as typeof fetch;
    fireEvent.click(screen.getByRole("button", { name: /refresh/i }));
    await waitFor(() =>
      expect(screen.getByText(/couldn.?t refresh/i)).toBeTruthy(),
    );
    expect(screen.getByText("Wire the store")).toBeTruthy(); // data retained

    // A subsequent successful refresh clears the stale notice.
    global.fetch = mockFetchOnce([
      issue({ id: "SOLAA-1", title: "Wire the store" }),
    ]) as unknown as typeof fetch;
    fireEvent.click(screen.getByRole("button", { name: /refresh/i }));
    await waitFor(() =>
      expect(screen.queryByText(/couldn.?t refresh/i)).toBeNull(),
    );
  });

  it("a selected filter DIMENSION (not just search) survives a Refresh", async () => {
    const fetcher = vi.fn().mockResolvedValue({
      ok: true,
      json: async () => ({
        issues: [
          issue({ id: "SOLAA-1", title: "Urgent one", priority: "urgent" }),
          issue({ id: "SOLAA-2", title: "Low one", priority: "low" }),
        ],
      }),
    });
    global.fetch = fetcher as unknown as typeof fetch;
    render(<Wrapped />);
    await waitFor(() => expect(screen.getByText("Urgent one")).toBeTruthy());

    // Apply the Priority=Urgent filter.
    fireEvent.click(screen.getByRole("button", { name: /priority/i }));
    fireEvent.click(screen.getByRole("checkbox", { name: /urgent/i }));
    await waitFor(() => expect(screen.queryByText("Low one")).toBeNull());

    const callsBefore = fetcher.mock.calls.length;
    fireEvent.click(screen.getByRole("button", { name: /refresh/i }));
    await waitFor(() =>
      expect(fetcher.mock.calls.length).toBeGreaterThan(callsBefore),
    );
    // Filter dimension survived: the low-priority card stays filtered out.
    await waitFor(() => expect(screen.getByText("Urgent one")).toBeTruthy());
    expect(screen.queryByText("Low one")).toBeNull();
  });

  it("shows the empty first-run state with a New Issue CTA", async () => {
    global.fetch = mockFetchOnce([]) as unknown as typeof fetch;
    render(<Wrapped />);
    await waitFor(() =>
      expect(screen.getByText(/No issues to display/i)).toBeTruthy(),
    );
    expect(
      screen.getByText(/Issues sync from your connected GitHub repo/i),
    ).toBeTruthy();
    // Two New Issue buttons (top bar + empty CTA).
    expect(
      screen.getAllByRole("button", { name: /new issue/i }),
    ).toHaveLength(2);
  });

  it("shows the loading skeleton before the feed resolves", () => {
    // A fetch that never resolves keeps SWR in the loading state.
    global.fetch = vi.fn(
      () => new Promise(() => {}),
    ) as unknown as typeof fetch;
    render(<Wrapped />);
    expect(screen.getByLabelText("Loading")).toBeTruthy();
  });

  it("on fetch failure shows an error with a working Try again retry", async () => {
    global.fetch = vi
      .fn()
      .mockResolvedValue({ ok: false, json: async () => ({}) }) as unknown as typeof fetch;

    render(<Wrapped />);
    await waitFor(() => expect(screen.getByRole("alert")).toBeTruthy());

    global.fetch = mockFetchOnce([
      issue({ id: "SOLAA-9", title: "Recovered" }),
    ]) as unknown as typeof fetch;
    fireEvent.click(screen.getByRole("button", { name: /try again/i }));
    await waitFor(() => expect(screen.getByText("Recovered")).toBeTruthy());
  });

  it("opening a card opens the drawer instantly via local state + pushes ?issue= (so Back can pop it, no navigation)", async () => {
    const pushSpy = vi.spyOn(window.history, "pushState");
    const replaceSpy = vi.spyOn(window.history, "replaceState");
    global.fetch = mockFetchOnce([
      issue({ id: "SOLAA-77", title: "Clickable" }),
    ]) as unknown as typeof fetch;

    render(<Wrapped />);
    await waitFor(() => expect(screen.getByText("Clickable")).toBeTruthy());

    fireEvent.click(screen.getByText("Clickable"));
    // Drawer appears immediately (local state) — the detail dialog for the issue.
    await waitFor(() =>
      expect(
        screen.getByRole("dialog", { name: "Issue SOLAA-77" }),
      ).toBeTruthy(),
    );
    // Open pushes a history entry (NOT replaceState) so Back has something to pop.
    expect(pushSpy).toHaveBeenCalledWith(
      {},
      "",
      "/dashboard/workstream?issue=SOLAA-77",
    );
    expect(replaceSpy).not.toHaveBeenCalledWith(
      expect.anything(),
      "",
      "/dashboard/workstream?issue=SOLAA-77",
    );
  });

  it("Back (popstate with no ?issue) closes the drawer — activeId clears, dialog gone", async () => {
    global.fetch = mockFetchOnce([
      issue({ id: "SOLAA-77", title: "Clickable" }),
    ]) as unknown as typeof fetch;

    render(<Wrapped />);
    await waitFor(() => expect(screen.getByText("Clickable")).toBeTruthy());

    fireEvent.click(screen.getByText("Clickable"));
    await waitFor(() =>
      expect(
        screen.getByRole("dialog", { name: "Issue SOLAA-77" }),
      ).toBeTruthy(),
    );

    // Simulate Back: the pushed ?issue= entry is popped, so location no longer
    // carries the param. The popstate listener re-reads window.location.search.
    window.history.replaceState({}, "", "/dashboard/workstream");
    fireEvent.popState(window);

    await waitFor(() =>
      expect(
        screen.queryByRole("dialog", { name: "Issue SOLAA-77" }),
      ).toBeNull(),
    );
  });

  it("hydrates the drawer from ?issue= on mount (deep-link)", async () => {
    mockIssue = "SOLAA-55";
    global.fetch = mockFetchOnce([
      issue({ id: "SOLAA-55", title: "Deep linked" }),
    ]) as unknown as typeof fetch;

    render(<Wrapped />);
    await waitFor(() =>
      expect(
        screen.getByRole("dialog", { name: "Issue SOLAA-55" }),
      ).toBeTruthy(),
    );
  });

  it("collapses a column to a strip and persists the choice in localStorage", async () => {
    global.fetch = mockFetchOnce([
      issue({ id: "SOLAA-1", title: "Card one" }),
    ]) as unknown as typeof fetch;

    render(<Wrapped />);
    await waitFor(() => expect(screen.getByText("Card one")).toBeTruthy());

    fireEvent.click(
      screen.getByRole("button", { name: "Collapse Backlog" }),
    );
    // Now an Expand control is present (collapsed strip state).
    await waitFor(() =>
      expect(
        screen.getByRole("button", { name: "Expand Backlog" }),
      ).toBeTruthy(),
    );
    const stored = JSON.parse(
      window.localStorage.getItem("workstream:collapsed-columns") ?? "[]",
    ) as string[];
    expect(stored).toContain("backlog");
  });

  it("renders a sibling empty column as a collapsed strip with no toggle", async () => {
    // Only Backlog has an issue; the other 6 columns are empty.
    global.fetch = mockFetchOnce([
      issue({ id: "SOLAA-1", title: "Card one", status: "backlog" }),
    ]) as unknown as typeof fetch;

    const { container } = render(<Wrapped />);
    await waitFor(() => expect(screen.getByText("Card one")).toBeTruthy());

    // Backlog (non-empty) stays expanded with a working Collapse toggle.
    expect(screen.getByRole("button", { name: "Collapse Backlog" })).toBeTruthy();

    // Todo (empty) renders as a w-10 collapsed strip and has no toggle.
    const todo = container.querySelector('section[aria-label="Todo"]');
    expect(todo).toBeTruthy();
    const cls = todo?.getAttribute("class") ?? "";
    expect(cls).toContain("w-10");
    expect(cls).not.toContain("w-72");
    expect(screen.queryByRole("button", { name: "Collapse Todo" })).toBeNull();
    expect(screen.queryByRole("button", { name: "Expand Todo" })).toBeNull();
  });

  it("an unknown ?issue= renders the Issue-not-found Sheet state", async () => {
    mockIssue = "SOLAA-DOESNOTEXIST";
    global.fetch = mockFetchOnce([
      issue({ id: "SOLAA-1", title: "Card one" }),
    ]) as unknown as typeof fetch;

    render(<Wrapped />);
    await waitFor(() => expect(screen.getByText("Issue not found")).toBeTruthy());
    expect(screen.getByRole("button", { name: /back to board/i })).toBeTruthy();
  });
});
