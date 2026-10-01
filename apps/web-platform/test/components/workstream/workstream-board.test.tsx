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
import {
  formatWorkstreamSseFrame,
  type WorkstreamFeedEvent,
} from "@/lib/workstream-feed";

// The board's fetcher negotiates `Accept: text/event-stream`. Mocks that model
// the bulk JSON arm must still present an application/json content-type so the
// fetcher takes its res.json() fallback — identical resolved shape.

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

const JSON_HEADERS = new Headers({ "content-type": "application/json" });

function mockFetchOnce(issues: WorkstreamIssue[], ok = true) {
  return vi.fn().mockResolvedValue({
    ok,
    headers: JSON_HEADERS,
    json: async () => ({ issues }),
  });
}

/** A controllable SSE response — `push` emits frames one at a time so tests
 *  can assert mid-stream state while the feed is still open. */
function sseControlled() {
  const encoder = new TextEncoder();
  let controller!: ReadableStreamDefaultController<Uint8Array>;
  const stream = new ReadableStream<Uint8Array>({
    start(c) {
      controller = c;
    },
  });
  const res = new Response(stream, {
    status: 200,
    headers: { "content-type": "text/event-stream; charset=utf-8" },
  });
  return {
    res,
    push: (e: WorkstreamFeedEvent) =>
      controller.enqueue(encoder.encode(formatWorkstreamSseFrame(e))),
    close: () => controller.close(),
  };
}

const META: WorkstreamFeedEvent = {
  type: "meta",
  board: { onKanbanOrg: false, projectWritable: false },
};

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
  vi.unstubAllGlobals();
});

describe("WorkstreamBoard", () => {
  it("renders the 7 columns backed by the connected repo", async () => {
    global.fetch = mockFetchOnce([
      issue({ id: "SOLAA-1", title: "Card one" }),
    ]) as unknown as typeof fetch;

    render(<Wrapped />);

    await waitFor(() => expect(screen.getByText("Card one")).toBeTruthy());
    for (const label of [
      "Backlog",
      "Ready",
      "In Progress",
      "In Review",
      "Blocked",
      "Pending",
      "Done",
    ]) {
      expect(screen.getByRole("heading", { name: label })).toBeTruthy();
    }
    expect(
      screen.getByText(/backed by your connected GitHub repo/i),
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
        headers: JSON_HEADERS,
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
      headers: JSON_HEADERS,
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

  it("content columns open by default; a content column can be collapsed and the choice persists (v2 key)", async () => {
    global.fetch = mockFetchOnce([
      issue({ id: "SOLAA-1", title: "Card one", status: "backlog" }),
    ]) as unknown as typeof fetch;

    render(<Wrapped />);
    await waitFor(() => expect(screen.getByText("Card one")).toBeTruthy());

    // Backlog (content) is OPEN by default and offers a Collapse toggle.
    const collapseBtn = screen.getByRole("button", { name: "Collapse Backlog" });
    fireEvent.click(collapseBtn);

    // After collapsing it becomes a strip with an Expand toggle...
    await waitFor(() =>
      expect(
        screen.getByRole("button", { name: "Expand Backlog" }),
      ).toBeTruthy(),
    );
    // ...and the choice persists under the v2 key (NOT the legacy v1 key).
    const stored = JSON.parse(
      window.localStorage.getItem("workstream:collapsed-columns-v2") ?? "[]",
    ) as string[];
    expect(stored).toContain("backlog");
    expect(
      window.localStorage.getItem("workstream:collapsed-columns"),
    ).toBeNull();
  });

  it("a sibling empty column collapses to a strip with no toggle", async () => {
    // Only Backlog has an issue; the other 6 columns are empty.
    global.fetch = mockFetchOnce([
      issue({ id: "SOLAA-1", title: "Card one", status: "backlog" }),
    ]) as unknown as typeof fetch;

    const { container } = render(<Wrapped />);
    await waitFor(() => expect(screen.getByText("Card one")).toBeTruthy());

    // Backlog (content) is expanded by default with a working Collapse toggle.
    expect(screen.getByRole("button", { name: "Collapse Backlog" })).toBeTruthy();

    // Ready (empty) renders as a w-10 collapsed strip and has no toggle.
    const ready = container.querySelector('section[aria-label="Ready"]');
    expect(ready).toBeTruthy();
    const cls = ready?.getAttribute("class") ?? "";
    expect(cls).toContain("w-10");
    expect(cls).not.toContain("w-72");
    expect(screen.queryByRole("button", { name: "Collapse Ready" })).toBeNull();
    expect(screen.queryByRole("button", { name: "Expand Ready" })).toBeNull();
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

  // Method-aware fetch: GET → { issues }, POST/PATCH → { issue }. Drives the
  // optimistic→reconcile write-integrity path end-to-end (ADR-067 / AC1/AC7).
  function methodFetch(opts: {
    getIssues: WorkstreamIssue[];
    write?: WorkstreamIssue;
    writeOk?: boolean;
    writeStatus?: number;
  }) {
    return vi.fn((_url: string, init?: { method?: string }) => {
      const method = init?.method ?? "GET";
      if (method === "GET") {
        return Promise.resolve({
          ok: true,
          headers: JSON_HEADERS,
          json: async () => ({ issues: opts.getIssues, board: undefined }),
        });
      }
      return Promise.resolve({
        ok: opts.writeOk ?? true,
        status: opts.writeStatus ?? 200,
        json: async () =>
          opts.writeOk === false
            ? { error: "workstream_write_error" }
            : { issue: opts.write },
      });
    });
  }

  it("create reconciles the optimistic card with the returned REAL number (AC1/AC7)", async () => {
    global.fetch = methodFetch({
      getIssues: [],
      write: issue({ id: "4321", title: "Fresh issue", status: "backlog" }),
    }) as unknown as typeof fetch;

    render(<Wrapped />);
    await waitFor(() =>
      expect(screen.getByText(/No issues to display/i)).toBeTruthy(),
    );

    fireEvent.click(screen.getAllByRole("button", { name: /new issue/i })[0]);
    fireEvent.change(screen.getByLabelText(/title/i), {
      target: { value: "Fresh issue" },
    });
    fireEvent.click(screen.getByRole("button", { name: /create issue/i }));

    // The card is reconciled to the real GitHub number (not the SOLAA-N temp id).
    await waitFor(() => expect(screen.getByText("4321")).toBeTruthy());
    expect(screen.getByText("Fresh issue")).toBeTruthy();
  });

  it("a failed status write rolls back + surfaces a retryable board toast (AC7)", async () => {
    mockIssue = "77";
    global.fetch = methodFetch({
      getIssues: [issue({ id: "77", title: "Movable", status: "backlog" })],
      writeOk: false,
      writeStatus: 502,
    }) as unknown as typeof fetch;

    render(<Wrapped />);
    await waitFor(() =>
      expect(screen.getByRole("dialog", { name: "Issue 77" })).toBeTruthy(),
    );

    fireEvent.change(screen.getByLabelText("Change status"), {
      target: { value: "blocked" },
    });

    // Failure surfaces a retryable board toast; the card rolls back to backlog.
    await waitFor(() =>
      expect(screen.getByText(/couldn.?t save that change/i)).toBeTruthy(),
    );
    expect(
      (screen.getByLabelText("Change status") as HTMLSelectElement).value,
    ).toBe("backlog");
  });

  it("a body edit reconciles from the returned canonical issue (AC1/AC7)", async () => {
    mockIssue = "77";
    global.fetch = methodFetch({
      getIssues: [
        issue({ id: "77", title: "Editable", body: "old body", status: "backlog" }),
      ],
      write: issue({
        id: "77",
        title: "Editable",
        body: "new body",
        description: "new body",
        status: "backlog",
      }),
    }) as unknown as typeof fetch;

    render(<Wrapped />);
    await waitFor(() =>
      expect(screen.getByRole("dialog", { name: "Issue 77" })).toBeTruthy(),
    );

    fireEvent.click(screen.getByLabelText("Edit description"));
    fireEvent.change(screen.getByLabelText("Edit description"), {
      target: { value: "new body" },
    });
    fireEvent.click(screen.getByRole("button", { name: "Save" }));

    // Reconciled: the rendered description now shows the returned canonical body.
    await waitFor(() => expect(screen.getByText("new body")).toBeTruthy());
  });

  it("a failed field write rolls back + surfaces a retryable toast (AC7)", async () => {
    mockIssue = "77";
    global.fetch = methodFetch({
      getIssues: [
        issue({ id: "77", title: "Editable", body: "old body", status: "backlog" }),
      ],
      writeOk: false,
      writeStatus: 502,
    }) as unknown as typeof fetch;

    render(<Wrapped />);
    await waitFor(() =>
      expect(screen.getByRole("dialog", { name: "Issue 77" })).toBeTruthy(),
    );

    fireEvent.click(screen.getByLabelText("Edit description"));
    fireEvent.change(screen.getByLabelText("Edit description"), {
      target: { value: "doomed" },
    });
    fireEvent.click(screen.getByRole("button", { name: "Save" }));

    await waitFor(() =>
      expect(screen.getByText(/couldn.?t save that change/i)).toBeTruthy(),
    );
    // The editor stays open for a retry (board rolled the card back).
    expect(screen.getByLabelText("Edit description")).toBeTruthy();
  });

  it("a 403 write flips the board read-only with an honest hint (AC14)", async () => {
    mockIssue = "77";
    global.fetch = methodFetch({
      getIssues: [issue({ id: "77", title: "Movable", status: "backlog" })],
      writeOk: false,
      writeStatus: 403,
    }) as unknown as typeof fetch;

    render(<Wrapped />);
    await waitFor(() =>
      expect(screen.getByRole("dialog", { name: "Issue 77" })).toBeTruthy(),
    );
    fireEvent.change(screen.getByLabelText("Change status"), {
      target: { value: "blocked" },
    });
    await waitFor(() =>
      expect(
        screen.getAllByText(/read-only access/i).length,
      ).toBeGreaterThan(0),
    );
  });

  // AC7 — a degraded first-load (502, no prior data) shows the ErrorCard and
  // must NOT let a New-Issue create resurrect the false EmptyState: the toolbar
  // "+ New Issue" button is disabled while `error && !data`. (FINDING 2)
  it("disables + New Issue on a first-load degrade so it can't resurrect EmptyState", async () => {
    global.fetch = vi
      .fn()
      .mockResolvedValue({ ok: false, json: async () => ({}) }) as unknown as typeof fetch;

    render(<Wrapped />);

    // First-load failure → ErrorCard (never a false EmptyState).
    await waitFor(() =>
      expect(screen.getByText(/failed to load the board/i)).toBeTruthy(),
    );
    expect(screen.queryByText(/no issues to display/i)).toBeNull();

    // The only New-Issue trigger on screen (toolbar) is disabled, so an
    // optimistic create can't flip `data` non-null and re-render EmptyState.
    const newIssueBtn = screen.getByRole("button", {
      name: /new issue/i,
    }) as HTMLButtonElement;
    expect(newIssueBtn.disabled).toBe(true);
  });

  // The board renders EXACTLY ONE tree, gated by viewport (not a CSS
  // `hidden md:flex` / `md:hidden` pair that would mount both). On a narrow
  // viewport the mobile status-selector board renders and the 7-column desktop
  // heading grid does not — so cards are not duplicated in the DOM.
  it("renders the mobile status-selector board (not the 7 columns) on a narrow viewport", async () => {
    const mql = {
      matches: false, // (min-width: 768px) does NOT match → mobile
      media: "(min-width: 768px)",
      addEventListener: () => {},
      removeEventListener: () => {},
    };
    vi.stubGlobal("matchMedia", () => mql);

    global.fetch = mockFetchOnce([
      issue({ id: "SOLAA-1", title: "Card one", status: "backlog" }),
    ]) as unknown as typeof fetch;

    render(<Wrapped />);

    // Mobile board = a status tablist; the card renders exactly once.
    await waitFor(() => expect(screen.getByRole("tablist")).toBeTruthy());
    expect(screen.getAllByText("Card one")).toHaveLength(1);
    // The desktop column headings are absent (MobileBoard uses tabs, not headings).
    expect(screen.queryByRole("heading", { name: "In Progress" })).toBeNull();
  });

  // --- Progressive SSE feed ---------------------------------------------------
  //
  // The board's fetcher negotiates Accept: text/event-stream and commits each
  // `issues` frame into the shared SWR cache entry while the stream is still
  // open (a reconcile arrives as a plain `issues` frame carrying full cards).
  // These tests drive a controlled ReadableStream so mid-feed state is
  // observable (AC3/AC7/AC8/AC9/AC10).

  it("renders cards after the FIRST issues frame while the stream is still open (AC3)", async () => {
    const ctl = sseControlled();
    const fetchMock = vi.fn().mockResolvedValue(ctl.res);
    global.fetch = fetchMock as unknown as typeof fetch;
    render(<Wrapped />);

    ctl.push(META);
    ctl.push({
      type: "issues",
      issues: [issue({ id: "11", title: "First page card" })],
    });
    await waitFor(() =>
      expect(screen.getByText("First page card")).toBeTruthy(),
    );

    // The feed is still open — Refresh stays in its loading state.
    const refresh = screen.getByRole("button", { name: /refresh/i });
    expect(refresh.getAttribute("aria-busy")).toBe("true");

    ctl.push({
      type: "issues",
      issues: [issue({ id: "12", title: "Second page card" })],
    });
    await waitFor(() =>
      expect(screen.getByText("Second page card")).toBeTruthy(),
    );

    ctl.push({ type: "done", openTruncated: false });
    ctl.close();
    await waitFor(() =>
      expect(refresh.getAttribute("aria-busy")).toBeNull(),
    );
    // Progressive commits must not re-fire the fetcher (revalidate:false) —
    // exactly one upstream request for the whole feed.
    expect(fetchMock).toHaveBeenCalledTimes(1);
    // …and the happy path never showed the refresh-failed banner.
    expect(screen.queryByText(/couldn.?t refresh/i)).toBeNull();
  });

  it("?issue=N deep-link shows loading until the issue's page arrives, then renders it (AC8)", async () => {
    mockIssue = "9999";
    const ctl = sseControlled();
    global.fetch = vi.fn().mockResolvedValue(ctl.res) as unknown as typeof fetch;
    render(<Wrapped />);

    ctl.push(META);
    ctl.push({ type: "issues", issues: [issue({ id: "1", title: "Early" })] });
    // The sheet is LOADING — not "Issue not found" — while the feed is open.
    await waitFor(() =>
      expect(screen.getByLabelText("Loading issue")).toBeTruthy(),
    );
    expect(screen.queryByText("Issue not found")).toBeNull();

    ctl.push({
      type: "issues",
      issues: [issue({ id: "9999", title: "Late issue" })],
    });
    ctl.push({ type: "done", openTruncated: false });
    ctl.close();
    await waitFor(() =>
      expect(screen.getByRole("dialog", { name: "Issue 9999" })).toBeTruthy(),
    );
  });

  it("?issue=N absent after done shows notFound — but never mid-stream (AC8)", async () => {
    mockIssue = "9999";
    const ctl = sseControlled();
    global.fetch = vi.fn().mockResolvedValue(ctl.res) as unknown as typeof fetch;
    render(<Wrapped />);

    ctl.push(META);
    ctl.push({ type: "issues", issues: [issue({ id: "1" })] });
    await waitFor(() =>
      expect(screen.getByLabelText("Loading issue")).toBeTruthy(),
    );
    expect(screen.queryByText("Issue not found")).toBeNull();

    ctl.push({ type: "done", openTruncated: false });
    ctl.close();
    await waitFor(() =>
      expect(screen.getByText("Issue not found")).toBeTruthy(),
    );
  });

  it("?issue=N unresolved after a mid-feed ERROR shows 'couldn't load' — never 'not found' (F1)", async () => {
    mockIssue = "9999";
    const ctl = sseControlled();
    global.fetch = vi.fn().mockResolvedValue(ctl.res) as unknown as typeof fetch;
    render(<Wrapped />);

    ctl.push(META);
    ctl.push({ type: "issues", issues: [issue({ id: "1" })] });
    await waitFor(() =>
      expect(screen.getByLabelText("Loading issue")).toBeTruthy(),
    );

    // The feed dies before issue 9999's page — a truncated set must not claim
    // "Issue not found" (it may live on a page that never streamed).
    ctl.push({ type: "error", code: "workstream_query_error" });
    ctl.close();
    await waitFor(() =>
      expect(screen.getByText(/couldn.?t load this issue/i)).toBeTruthy(),
    );
    expect(screen.queryByText("Issue not found")).toBeNull();
  });

  it("a mid-stream error frame keeps the partial board + shows the refresh-failed banner (AC7)", async () => {
    const ctl = sseControlled();
    global.fetch = vi.fn().mockResolvedValue(ctl.res) as unknown as typeof fetch;
    render(<Wrapped />);

    ctl.push(META);
    ctl.push({
      type: "issues",
      issues: [issue({ id: "1", title: "Partial card" })],
    });
    await waitFor(() => expect(screen.getByText("Partial card")).toBeTruthy());

    ctl.push({ type: "error", code: "workstream_query_error" });
    ctl.close();
    await waitFor(() =>
      expect(screen.getByText(/couldn.?t refresh/i)).toBeTruthy(),
    );
    expect(screen.getByText("Partial card")).toBeTruthy();
  });

  it("a stream truncated WITHOUT done is loud — partial data + banner (AC6)", async () => {
    const ctl = sseControlled();
    global.fetch = vi.fn().mockResolvedValue(ctl.res) as unknown as typeof fetch;
    render(<Wrapped />);

    ctl.push(META);
    ctl.push({ type: "issues", issues: [issue({ id: "1", title: "Partial" })] });
    await waitFor(() => expect(screen.getByText("Partial")).toBeTruthy());

    ctl.close(); // EOF with no done — never a silent-complete
    await waitFor(() =>
      expect(screen.getByText(/couldn.?t refresh/i)).toBeTruthy(),
    );
  });

  it("meta-only keeps the skeleton (no EmptyState flash); done with zero issues → EmptyState (AC10)", async () => {
    const ctl = sseControlled();
    global.fetch = vi.fn().mockResolvedValue(ctl.res) as unknown as typeof fetch;
    render(<Wrapped />);

    ctl.push(META);
    // Only meta arrived: the board stays in skeleton — no false EmptyState.
    await waitFor(() =>
      expect(screen.getByLabelText("Loading")).toBeTruthy(),
    );
    expect(screen.queryByText(/No issues to display/i)).toBeNull();

    ctl.push({ type: "done", openTruncated: false });
    ctl.close();
    await waitFor(() =>
      expect(screen.getByText(/No issues to display/i)).toBeTruthy(),
    );
  });

  it("an optimistic card reconciled mid-stream survives every subsequent issues commit (AC9)", async () => {
    const ctl = sseControlled();
    global.fetch = vi.fn((_url: string, init?: { method?: string }) => {
      if ((init?.method ?? "GET") !== "GET") {
        return Promise.resolve(
          new Response(
            JSON.stringify({
              issue: issue({ id: "777", title: "Created mid-stream" }),
            }),
            { status: 200, headers: JSON_HEADERS },
          ),
        );
      }
      return Promise.resolve(ctl.res);
    }) as unknown as typeof fetch;
    render(<Wrapped />);

    ctl.push(META);
    ctl.push({ type: "issues", issues: [issue({ id: "1", title: "P1" })] });
    await waitFor(() => expect(screen.getByText("P1")).toBeTruthy());

    // Create while the feed is open — optimistic temp → reconciled real card.
    fireEvent.click(screen.getAllByRole("button", { name: /new issue/i })[0]);
    fireEvent.change(screen.getByLabelText(/title/i), {
      target: { value: "Created mid-stream" },
    });
    fireEvent.click(screen.getByRole("button", { name: /create issue/i }));
    await waitFor(() =>
      expect(screen.getByText("777")).toBeTruthy(),
    );

    // The next streamed page must NOT drop the locally-created card.
    ctl.push({ type: "issues", issues: [issue({ id: "2", title: "P2" })] });
    ctl.push({ type: "done", openTruncated: false });
    ctl.close();
    await waitFor(() => expect(screen.getByText("P2")).toBeTruthy());
    expect(screen.getByText("Created mid-stream")).toBeTruthy();
    expect(screen.getByText("P1")).toBeTruthy();
  });
});
