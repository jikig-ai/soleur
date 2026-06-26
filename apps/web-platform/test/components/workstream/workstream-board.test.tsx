import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import {
  cleanup,
  fireEvent,
  render,
  screen,
  waitFor,
} from "@testing-library/react";
import type { WorkstreamIssue } from "@/lib/workstream";

// next/navigation mocked: `mockIssue` drives the ?issue= param, `mockPush`
// captures Sheet open/close nav.
let mockIssue: string | null = null;
const mockPush = vi.fn();
vi.mock("next/navigation", () => ({
  useRouter: () => ({ push: mockPush, refresh: vi.fn(), prefetch: vi.fn() }),
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
  mockPush.mockClear();
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

  it("filters by id + title and shows a distinct no-results state with clear-search", async () => {
    global.fetch = mockFetchOnce([
      issue({ id: "SOLAA-1", title: "Wire the store" }),
      issue({ id: "SOLAA-2", title: "Draft copy" }),
    ]) as unknown as typeof fetch;

    render(<Wrapped />);
    await waitFor(() => expect(screen.getByText("Wire the store")).toBeTruthy());

    fireEvent.change(screen.getByLabelText("Search issues"), {
      target: { value: "zzzznope" },
    });
    expect(screen.getByText(/No issues match/i)).toBeTruthy();

    fireEvent.click(screen.getByRole("button", { name: /clear search/i }));
    await waitFor(() => expect(screen.getByText("Wire the store")).toBeTruthy());
  });

  it("shows the empty first-run state with a New Issue CTA", async () => {
    global.fetch = mockFetchOnce([]) as unknown as typeof fetch;
    render(<Wrapped />);
    await waitFor(() =>
      expect(screen.getByText(/No issues on the board yet/i)).toBeTruthy(),
    );
    // Two New Issue buttons (top bar + empty CTA).
    expect(screen.getAllByRole("button", { name: /new issue/i }).length).toBeGreaterThan(0);
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

  it("opening a card pushes ?issue=<id>", async () => {
    global.fetch = mockFetchOnce([
      issue({ id: "SOLAA-77", title: "Clickable" }),
    ]) as unknown as typeof fetch;

    render(<Wrapped />);
    await waitFor(() => expect(screen.getByText("Clickable")).toBeTruthy());

    fireEvent.click(screen.getByText("Clickable"));
    expect(mockPush).toHaveBeenCalledWith("/dashboard/workstream?issue=SOLAA-77");
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
