import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import {
  cleanup,
  fireEvent,
  render,
  screen,
  waitFor,
  within,
} from "@testing-library/react";
import type { EmailTriageItem } from "@/components/inbox/email-triage-row";

// next/navigation is mocked; `mockStatus` drives useSearchParams so each test
// can simulate Active vs an Archived deep-link, and `mockPush` captures tab nav.
let mockStatus: string | null = null;
const mockPush = vi.fn();
vi.mock("next/navigation", () => ({
  useRouter: () => ({ push: mockPush, refresh: vi.fn(), prefetch: vi.fn() }),
  usePathname: () => "/dashboard/inbox",
  useSearchParams: () =>
    new URLSearchParams(mockStatus ? `status=${mockStatus}` : ""),
}));

import { InboxSurface } from "@/components/inbox/inbox-surface";

function item(over: Partial<EmailTriageItem> = {}): EmailTriageItem {
  return {
    id: crypto.randomUUID(),
    message_id: null,
    sender: "vendor@example.com",
    subject: "Vendor MSA review",
    summary: "Renewal terms",
    mail_class: "operational",
    statutory_class: null,
    rule_id: null,
    status: "new",
    status_changed_at: null,
    acknowledged_at: null,
    received_at: "2026-06-18T10:00:00.000Z",
    created_at: "2026-06-18T10:00:00.000Z",
    ...over,
  };
}

function mockFetchOnce(items: EmailTriageItem[], ok = true) {
  return vi.fn().mockResolvedValue({
    ok,
    json: async () => ({ items }),
  });
}

beforeEach(() => {
  mockStatus = null;
  mockPush.mockClear();
});

afterEach(() => {
  cleanup();
  vi.restoreAllMocks();
});

describe("InboxSurface", () => {
  it("fetches the Active view and renders rows in API order (no re-sort)", async () => {
    const a = item({ subject: "First from API" });
    const b = item({ subject: "Second from API" });
    global.fetch = mockFetchOnce([a, b]) as unknown as typeof fetch;

    render(<InboxSurface />);

    await waitFor(() => expect(screen.getByText("First from API")).toBeTruthy());
    // Default (Active) view fetches the plain endpoint, no ?status=archived.
    expect(global.fetch).toHaveBeenCalledWith("/api/inbox/emails");

    const subjects = screen
      .getAllByText(/from API$/)
      .map((el) => el.textContent);
    expect(subjects).toEqual(["First from API", "Second from API"]);
  });

  it("Archived deep-link fetches ?status=archived and highlights the Archived tab", async () => {
    mockStatus = "archived";
    global.fetch = mockFetchOnce([item({ status: "archived", subject: "Done item" })]) as unknown as typeof fetch;

    render(<InboxSurface />);

    await waitFor(() =>
      expect(global.fetch).toHaveBeenCalledWith(
        "/api/inbox/emails?status=archived",
      ),
    );
    const archivedTab = screen.getByRole("tab", { name: /archived/i });
    expect(archivedTab.getAttribute("aria-selected")).toBe("true");
  });

  it("shows distinct empty-state copy for Active vs Archived", async () => {
    global.fetch = mockFetchOnce([]) as unknown as typeof fetch;
    render(<InboxSurface />);
    await waitFor(() =>
      expect(screen.getByText("No items needing attention")).toBeTruthy(),
    );

    cleanup();
    mockStatus = "archived";
    global.fetch = mockFetchOnce([]) as unknown as typeof fetch;
    render(<InboxSurface />);
    await waitFor(() =>
      expect(screen.getByText("Nothing archived yet")).toBeTruthy(),
    );
  });

  it("shows a Loading affordance before content resolves", async () => {
    let resolve!: (v: unknown) => void;
    global.fetch = vi
      .fn()
      .mockReturnValue(
        new Promise((r) => {
          resolve = r;
        }),
      ) as unknown as typeof fetch;

    render(<InboxSurface />);
    expect(screen.getByText(/loading/i)).toBeTruthy();

    resolve({ ok: true, json: async () => ({ items: [] }) });
    await waitFor(() =>
      expect(screen.getByText("No items needing attention")).toBeTruthy(),
    );
  });

  it("on fetch failure shows an error with retry, keeps tabs rendered, and retry refetches", async () => {
    const failing = vi.fn().mockResolvedValue({ ok: false, json: async () => ({}) });
    global.fetch = failing as unknown as typeof fetch;

    render(<InboxSurface />);
    await waitFor(() => expect(screen.getByRole("alert")).toBeTruthy());
    // Tabs must stay reachable in the error state (no strand).
    expect(screen.getByRole("tab", { name: /active/i })).toBeTruthy();
    expect(screen.getByRole("tab", { name: /archived/i })).toBeTruthy();

    // Retry refetches the current tab.
    global.fetch = mockFetchOnce([item({ subject: "Recovered" })]) as unknown as typeof fetch;
    fireEvent.click(screen.getByRole("button", { name: /try again/i }));
    await waitFor(() => expect(screen.getByText("Recovered")).toBeTruthy());
  });

  it("switching tabs pushes the status query param", async () => {
    global.fetch = mockFetchOnce([]) as unknown as typeof fetch;
    render(<InboxSurface />);
    await waitFor(() =>
      expect(screen.getByText("No items needing attention")).toBeTruthy(),
    );

    fireEvent.click(screen.getByRole("tab", { name: /archived/i }));
    expect(mockPush).toHaveBeenCalledWith("/dashboard/inbox?status=archived");

    fireEvent.click(screen.getByRole("tab", { name: /active/i }));
    expect(mockPush).toHaveBeenCalledWith("/dashboard/inbox");
  });

  it("refetches the archived endpoint when the status param changes (tab switch)", async () => {
    global.fetch = mockFetchOnce([item({ subject: "Active row" })]) as unknown as typeof fetch;
    const { rerender } = render(<InboxSurface />);
    await waitFor(() => expect(screen.getByText("Active row")).toBeTruthy());
    expect(global.fetch).toHaveBeenLastCalledWith("/api/inbox/emails");

    // Simulate the URL changing to ?status=archived (what router.push does),
    // then re-render — the surface must refetch the archived endpoint.
    mockStatus = "archived";
    global.fetch = mockFetchOnce([item({ status: "archived", subject: "Archived row" })]) as unknown as typeof fetch;
    rerender(<InboxSurface />);
    await waitFor(() =>
      expect(global.fetch).toHaveBeenCalledWith("/api/inbox/emails?status=archived"),
    );
    await waitFor(() => expect(screen.getByText("Archived row")).toBeTruthy());
  });

  it("drops a superseded (out-of-order) response so stale items never clobber fresh ones", async () => {
    // Two overlapping fetches; the FIRST resolves LAST. The request-sequence
    // guard must keep the second (newer) result and discard the first.
    const resolvers: Array<(v: unknown) => void> = [];
    global.fetch = vi
      .fn()
      .mockImplementation(
        () => new Promise((r) => resolvers.push(r)),
      ) as unknown as typeof fetch;

    const { rerender } = render(<InboxSurface />); // fetch #1 (Active) in flight
    mockStatus = "archived";
    rerender(<InboxSurface />); // fetch #2 (Archived) in flight
    await waitFor(() => expect(resolvers.length).toBe(2));

    // Resolve the NEWER request first, then the older stale one.
    resolvers[1]({ ok: true, json: async () => ({ items: [item({ subject: "Fresh archived" })] }) });
    await waitFor(() => expect(screen.getByText("Fresh archived")).toBeTruthy());
    resolvers[0]({ ok: true, json: async () => ({ items: [item({ subject: "Stale active" })] }) });

    // Give the stale resolution a tick; it must NOT replace the fresh result.
    await Promise.resolve();
    expect(screen.queryByText("Stale active")).toBeNull();
    expect(screen.getByText("Fresh archived")).toBeTruthy();
  });
});
