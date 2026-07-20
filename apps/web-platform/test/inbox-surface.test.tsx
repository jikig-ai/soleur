import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import {
  cleanup,
  fireEvent,
  render,
  screen,
  waitFor,
} from "@testing-library/react";
import type { EmailTriageItem } from "@/components/inbox/email-triage-row";
import type { InboxItemRowData, MergedInboxItem } from "@/lib/inbox-severity";

// next/navigation mocked; `mockStatus` drives useSearchParams (Active vs an
// Archived deep-link); `mockPush` captures tab nav.
let mockStatus: string | null = null;
const mockPush = vi.fn();
vi.mock("next/navigation", () => ({
  useRouter: () => ({ push: mockPush, refresh: vi.fn(), prefetch: vi.fn() }),
  usePathname: () => "/dashboard/inbox",
  useSearchParams: () =>
    new URLSearchParams(mockStatus ? `status=${mockStatus}` : ""),
}));

import { InboxSurface } from "@/components/inbox/inbox-surface";
import { SwrTestProvider } from "./helpers/swr-wrapper";

function Wrapped() {
  return (
    <SwrTestProvider>
      <InboxSurface />
    </SwrTestProvider>
  );
}

function emailRow(over: Partial<EmailTriageItem> = {}): EmailTriageItem {
  return {
    id: crypto.randomUUID(),
    message_id: null,
    sender: "vendor@example.com",
    subject: "Vendor MSA review",
    summary: null,
    mail_class: "vendor",
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

function inboxRow(over: Partial<InboxItemRowData> = {}): InboxItemRowData {
  return {
    id: crypto.randomUUID(),
    severity: "info",
    source: "task_completed",
    title: "Chief Legal Officer finished",
    source_ref: { conversationId: "c1" },
    status: "unread",
    created_at: "2026-07-01T10:00:00.000Z",
    read_at: null,
    acted_at: null,
    archived_at: null,
    ...over,
  };
}

function mergedEmail(over: Partial<EmailTriageItem> = {}): MergedInboxItem {
  const email = emailRow(over);
  const statutory = email.statutory_class !== null;
  return {
    kind: "email",
    id: email.id,
    severity: statutory ? "action_required" : "info",
    pinned: statutory,
    outstanding: statutory,
    email,
  };
}

function mergedInbox(over: Partial<InboxItemRowData> = {}): MergedInboxItem {
  const inbox = inboxRow(over);
  return {
    kind: "inbox",
    id: inbox.id,
    severity: inbox.severity,
    pinned: false,
    outstanding: inbox.severity === "action_required" && inbox.acted_at === null,
    inbox,
  };
}

function mockFetchOnce(items: MergedInboxItem[], ok = true) {
  return vi.fn().mockResolvedValue({ ok, json: async () => ({ items }) });
}

beforeEach(() => {
  mockStatus = null;
  mockPush.mockClear();
});

afterEach(() => {
  cleanup();
  vi.restoreAllMocks();
});

describe("InboxSurface (unified merged inbox)", () => {
  it("fetches the unified Active endpoint and renders rows in API order", async () => {
    const a = mergedInbox({ title: "First finished" });
    const b = mergedInbox({ title: "Second finished" });
    global.fetch = mockFetchOnce([a, b]) as unknown as typeof fetch;

    render(<Wrapped />);

    await waitFor(() => expect(screen.getByText("First finished")).toBeTruthy());
    expect(global.fetch).toHaveBeenCalledWith("/api/inbox");
    const titles = screen.getAllByText(/finished$/).map((el) => el.textContent);
    expect(titles).toEqual(["First finished", "Second finished"]);
  });

  it("groups action_required under NEEDS YOU and info under GOOD TO KNOW", async () => {
    global.fetch = mockFetchOnce([
      mergedEmail({ subject: "DSAR request", statutory_class: "dsar" }),
      mergedInbox({ title: "Design finished", severity: "info" }),
    ]) as unknown as typeof fetch;

    render(<Wrapped />);

    await waitFor(() => expect(screen.getByText("NEEDS YOU")).toBeTruthy());
    expect(screen.getByText("GOOD TO KNOW")).toBeTruthy();
    // Email row (statutory) rendered by EmailTriageRow; native by InboxItemRow.
    expect(screen.getByText("DSAR request")).toBeTruthy();
    expect(screen.getByText("Design finished")).toBeTruthy();
  });

  it("Archived deep-link fetches ?status=archived and highlights the Archived tab", async () => {
    mockStatus = "archived";
    global.fetch = mockFetchOnce([
      mergedInbox({ title: "Done", status: "archived", archived_at: "2026-07-02T00:00:00.000Z" }),
    ]) as unknown as typeof fetch;

    render(<Wrapped />);

    await waitFor(() =>
      expect(global.fetch).toHaveBeenCalledWith("/api/inbox?status=archived"),
    );
    expect(
      screen.getByRole("tab", { name: /archived/i }).getAttribute("aria-selected"),
    ).toBe("true");
  });

  it("shows the Appendix A empty states for Active vs Archived", async () => {
    global.fetch = mockFetchOnce([]) as unknown as typeof fetch;
    render(<Wrapped />);
    await waitFor(() =>
      expect(screen.getByText("You're all caught up.")).toBeTruthy(),
    );

    cleanup();
    mockStatus = "archived";
    global.fetch = mockFetchOnce([]) as unknown as typeof fetch;
    render(<Wrapped />);
    await waitFor(() =>
      expect(screen.getByText("Nothing here yet.")).toBeTruthy(),
    );
  });

  it("shows the reassurance state when NEEDS YOU is empty but FYI is present", async () => {
    global.fetch = mockFetchOnce([
      mergedInbox({ title: "Legal finished", severity: "info" }),
    ]) as unknown as typeof fetch;
    render(<Wrapped />);
    await waitFor(() =>
      expect(screen.getByText("Nothing needs your call right now.")).toBeTruthy(),
    );
    // The FYI item still renders under GOOD TO KNOW.
    expect(screen.getByText("Legal finished")).toBeTruthy();
  });

  it("shows a Loading affordance before content resolves", async () => {
    let resolve!: (v: unknown) => void;
    global.fetch = vi
      .fn()
      .mockReturnValue(new Promise((r) => (resolve = r))) as unknown as typeof fetch;
    render(<Wrapped />);
    expect(screen.getByText(/loading/i)).toBeTruthy();
    resolve({ ok: true, json: async () => ({ items: [] }) });
    await waitFor(() =>
      expect(screen.getByText("You're all caught up.")).toBeTruthy(),
    );
  });

  it("on fetch failure shows an error with retry, keeps tabs, and retry refetches", async () => {
    global.fetch = vi
      .fn()
      .mockResolvedValue({ ok: false, json: async () => ({}) }) as unknown as typeof fetch;
    render(<Wrapped />);
    await waitFor(() => expect(screen.getByRole("alert")).toBeTruthy());
    expect(screen.getByRole("tab", { name: /active/i })).toBeTruthy();
    expect(screen.getByRole("tab", { name: /archived/i })).toBeTruthy();

    global.fetch = mockFetchOnce([
      mergedInbox({ title: "Recovered finished" }),
    ]) as unknown as typeof fetch;
    fireEvent.click(screen.getByRole("button", { name: /try again/i }));
    await waitFor(() => expect(screen.getByText("Recovered finished")).toBeTruthy());
  });

  it("switching tabs pushes the status query param", async () => {
    global.fetch = mockFetchOnce([]) as unknown as typeof fetch;
    render(<Wrapped />);
    await waitFor(() =>
      expect(screen.getByText("You're all caught up.")).toBeTruthy(),
    );
    fireEvent.click(screen.getByRole("tab", { name: /archived/i }));
    expect(mockPush).toHaveBeenCalledWith("/dashboard/inbox?status=archived");
    fireEvent.click(screen.getByRole("tab", { name: /active/i }));
    expect(mockPush).toHaveBeenCalledWith("/dashboard/inbox");
  });

  it("drops a superseded (out-of-order) response so stale items never clobber fresh ones", async () => {
    const resolvers: Array<(v: unknown) => void> = [];
    global.fetch = vi
      .fn()
      .mockImplementation(() => new Promise((r) => resolvers.push(r))) as unknown as typeof fetch;

    const { rerender } = render(<Wrapped />); // fetch #1 (Active)
    mockStatus = "archived";
    rerender(<Wrapped />); // fetch #2 (Archived)
    await waitFor(() => expect(resolvers.length).toBe(2));

    resolvers[1]({
      ok: true,
      json: async () => ({ items: [mergedInbox({ title: "Fresh archived", status: "archived" })] }),
    });
    await waitFor(() => expect(screen.getByText("Fresh archived")).toBeTruthy());
    resolvers[0]({
      ok: true,
      json: async () => ({ items: [mergedInbox({ title: "Stale active" })] }),
    });
    await Promise.resolve();
    expect(screen.queryByText("Stale active")).toBeNull();
    expect(screen.getByText("Fresh archived")).toBeTruthy();
  });
});
