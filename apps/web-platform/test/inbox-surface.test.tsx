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

describe("InboxSurface — bulk archive selection (#9284)", () => {
  /** fetch dispatcher: /api/inbox list vs POST /api/inbox/bulk-archive. */
  function mockFetchWithBulk(
    items: () => MergedInboxItem[],
    bulkResults?: unknown,
  ) {
    return vi.fn().mockImplementation(async (url: string, init?: RequestInit) => {
      if (typeof url === "string" && url.includes("/api/inbox/bulk-archive")) {
        const body = JSON.parse(String(init?.body)) as {
          items: { kind: string; id: string }[];
        };
        return {
          ok: true,
          json: async () => ({
            results:
              bulkResults ??
              body.items.map((i) => ({ ...i, outcome: "archived" })),
          }),
        };
      }
      return { ok: true, json: async () => ({ items: items() }) };
    }) as unknown as typeof fetch;
  }

  it("renders an enabled checkbox on archivable rows and disabled+reason on protected ones", async () => {
    const items = [
      mergedInbox({ title: "Good to know item" }), // info → archivable
      mergedInbox({
        title: "Needs you item",
        severity: "action_required",
        acted_at: null,
      }),
      mergedEmail({ subject: "Statutory one", statutory_class: "dsar" }),
    ];
    global.fetch = mockFetchOnce(items) as unknown as typeof fetch;
    render(<Wrapped />);
    await waitFor(() => expect(screen.getByText("Good to know item")).toBeTruthy());

    // Row checkboxes only — the "Select all" strips carry a different label.
    const boxes = screen.getAllByRole("checkbox", { name: /^Select: / });
    const enabled = boxes.filter((b) => !(b as HTMLInputElement).disabled);
    const disabled = boxes.filter((b) => (b as HTMLInputElement).disabled);
    expect(enabled.length).toBe(1);
    expect(disabled.length).toBe(2);
    expect(screen.getByText("Awaiting your call")).toBeTruthy();
    expect(screen.getByText("Statutory — must stay visible")).toBeTruthy();
  });

  it("selecting a row shows the bulk bar with count; Clear empties it", async () => {
    global.fetch = mockFetchOnce([
      mergedInbox({ title: "A" }),
      mergedInbox({ title: "B" }),
    ]) as unknown as typeof fetch;
    render(<Wrapped />);
    await waitFor(() => expect(screen.getByText("A")).toBeTruthy());

    fireEvent.click(screen.getAllByRole("checkbox", { name: /^Select: / })[0]);
    expect(screen.getByText("1 selected")).toBeTruthy();
    expect(screen.getByRole("button", { name: /Archive 1 selected/ })).toBeTruthy();

    fireEvent.click(screen.getByRole("button", { name: "Clear" }));
    expect(screen.queryByText(/selected/)).toBeNull();
  });

  it("per-section Select all selects only archivable rendered rows in that section", async () => {
    const items = [
      mergedInbox({ title: "Guarded", severity: "action_required", acted_at: null }),
      mergedInbox({ title: "Info one" }),
      mergedInbox({ title: "Info two" }),
    ];
    global.fetch = mockFetchOnce(items) as unknown as typeof fetch;
    render(<Wrapped />);
    await waitFor(() => expect(screen.getByText("Info one")).toBeTruthy());

    const strips = screen.getAllByRole("checkbox", { name: "Select all" });
    // NEEDS YOU strip: its only row is un-acted action_required → disabled.
    expect((strips[0] as HTMLInputElement).disabled).toBe(true);
    // GOOD TO KNOW strip: two archivable rows.
    fireEvent.click(strips[1]);
    expect(screen.getByText("2 selected")).toBeTruthy();
    const boxes = screen.getAllByRole("checkbox", { name: /^Select: / });
    // Render order: [Guarded (disabled), Info one, Info two].
    expect((boxes[0] as HTMLInputElement).checked).toBe(false);
    expect((boxes[1] as HTMLInputElement).checked).toBe(true);
    expect((boxes[2] as HTMLInputElement).checked).toBe(true);
  });

  it("Select all is indeterminate when a subset of the section is selected", async () => {
    global.fetch = mockFetchOnce([
      mergedInbox({ title: "A" }),
      mergedInbox({ title: "B" }),
    ]) as unknown as typeof fetch;
    render(<Wrapped />);
    await waitFor(() => expect(screen.getByText("A")).toBeTruthy());
    fireEvent.click(screen.getAllByRole("checkbox", { name: /^Select: / })[0]);
    const strip = screen.getAllByRole("checkbox", { name: "Select all" })[0] as HTMLInputElement;
    expect(strip.indeterminate).toBe(true);
  });

  it("confirm dialog blocks dismissal while pending and POSTs the selected ids", async () => {
    const a = mergedInbox({ title: "A" });
    const b = mergedInbox({ title: "B" });
    let bulkBody: { items: { kind: string; id: string }[] } | null = null;
    let resolveBulk: ((v: unknown) => void) | null = null;
    global.fetch = vi.fn().mockImplementation((url: string, init?: RequestInit) => {
      if (url.includes("bulk-archive")) {
        bulkBody = JSON.parse(String(init?.body));
        return new Promise((r) => (resolveBulk = r));
      }
      return Promise.resolve({ ok: true, json: async () => ({ items: [a, b] }) });
    }) as unknown as typeof fetch;

    render(<Wrapped />);
    await waitFor(() => expect(screen.getByText("A")).toBeTruthy());
    const boxes = screen.getAllByRole("checkbox", { name: /^Select: / });
    fireEvent.click(boxes[0]);
    fireEvent.click(boxes[1]);
    fireEvent.click(screen.getByRole("button", { name: /Archive 2 selected/ }));

    await waitFor(() =>
      expect(screen.getByText(/Archive 2 items\?/)).toBeTruthy(),
    );
    expect(screen.getByText(/nothing is deleted/i)).toBeTruthy();

    fireEvent.click(screen.getByRole("button", { name: "Archive" }));
    await waitFor(() => expect(bulkBody).not.toBeNull());
    expect(bulkBody!.items).toEqual([
      { kind: "inbox", id: a.id },
      { kind: "inbox", id: b.id },
    ]);

    // While pending, every dismiss vector is inert — Escape leaves the modal open.
    fireEvent.keyDown(document, { key: "Escape" });
    expect(screen.getByText(/Archive 2 items\?/)).toBeTruthy();
    // And it doesn't clear the selection either.
    expect(screen.getByText("2 selected")).toBeTruthy();

    resolveBulk!({
      ok: true,
      json: async () => ({
        results: [
          { id: a.id, kind: "inbox", outcome: "archived" },
          { id: b.id, kind: "inbox", outcome: "archived" },
        ],
      }),
    });
    await waitFor(() =>
      expect(screen.getByRole("status").textContent).toContain("Archived 2."),
    );
  });

  it("result line reports guarded items separately and keeps them selected", async () => {
    const guarded = mergedInbox({
      title: "Guarded",
      severity: "action_required",
      acted_at: "2026-09-30T00:00:00Z", // acted → archivable but server guards
    });
    const ok = mergedInbox({ title: "Ok" });
    global.fetch = mockFetchWithBulk(() => [guarded, ok], [
      { id: guarded.id, kind: "inbox", outcome: "guarded", reason: "needs_action" },
      { id: ok.id, kind: "inbox", outcome: "archived" },
    ]) as unknown as typeof fetch;

    render(<Wrapped />);
    await waitFor(() => expect(screen.getByText("Ok")).toBeTruthy());
    for (const b of screen.getAllByRole("checkbox", { name: /^Select: / })) {
      fireEvent.click(b);
    }
    fireEvent.click(screen.getByRole("button", { name: /Archive 2 selected/ }));
    await waitFor(() => screen.getByText(/Archive 2 items\?/));
    fireEvent.click(screen.getByRole("button", { name: "Archive" }));
    await waitFor(() => {
      const status = screen.getByRole("status").textContent ?? "";
      expect(status).toContain("Archived 1.");
      expect(status).toContain("1 can't be archived until handled.");
    });
    // Residual selection: the non-archived (guarded) id stays selected.
    expect(screen.getByText("1 selected")).toBeTruthy();
    const guardedBox = screen.getAllByRole("checkbox", { name: /^Select: / })[0] as HTMLInputElement;
    expect(guardedBox.checked).toBe(true);
  });

  it("Escape clears the selection when no dialog is open", async () => {
    global.fetch = mockFetchOnce([mergedInbox({ title: "A" })]) as unknown as typeof fetch;
    render(<Wrapped />);
    await waitFor(() => expect(screen.getByText("A")).toBeTruthy());
    fireEvent.click(screen.getByRole("checkbox", { name: /^Select: / }));
    expect(screen.getByText("1 selected")).toBeTruthy();
    fireEvent.keyDown(document, { key: "Escape" });
    expect(screen.queryByText("1 selected")).toBeNull();
  });

  it("checkboxes are not rendered on the Archived tab", async () => {
    mockStatus = "archived";
    global.fetch = mockFetchOnce([
      mergedInbox({ title: "Old", status: "archived" }),
    ]) as unknown as typeof fetch;
    render(<Wrapped />);
    await waitFor(() => expect(screen.getByText("Old")).toBeTruthy());
    expect(screen.queryByRole("checkbox")).toBeNull();
  });

  it("429 response shows its own copy and closes the modal", async () => {
    const a = mergedInbox({ title: "A" });
    global.fetch = vi.fn().mockImplementation(async (url: string) => {
      if (url.includes("bulk-archive")) {
        return { ok: false, status: 429, json: async () => ({}) };
      }
      return { ok: true, json: async () => ({ items: [a] }) };
    }) as unknown as typeof fetch;
    render(<Wrapped />);
    await waitFor(() => expect(screen.getByText("A")).toBeTruthy());
    fireEvent.click(screen.getByRole("checkbox", { name: /^Select: / }));
    fireEvent.click(screen.getByRole("button", { name: /Archive 1 selected/ }));
    await waitFor(() => screen.getByText(/Archive 1 items\?/));
    fireEvent.click(screen.getByRole("button", { name: "Archive" }));
    await waitFor(() =>
      expect(screen.getByRole("status").textContent).toContain(
        "Too many actions — wait a moment",
      ),
    );
    // Modal closed — the result line is visible, not occluded.
    expect(screen.queryByText(/Archive 1 items\?/)).toBeNull();
  });

  it("a thrown fetch reports an error rather than failing silently", async () => {
    const a = mergedInbox({ title: "A" });
    global.fetch = vi.fn().mockImplementation(async (url: string) => {
      if (url.includes("bulk-archive")) throw new Error("network down");
      return { ok: true, json: async () => ({ items: [a] }) };
    }) as unknown as typeof fetch;
    render(<Wrapped />);
    await waitFor(() => expect(screen.getByText("A")).toBeTruthy());
    fireEvent.click(screen.getByRole("checkbox", { name: /^Select: / }));
    fireEvent.click(screen.getByRole("button", { name: /Archive 1 selected/ }));
    await waitFor(() => screen.getByText(/Archive 1 items\?/));
    fireEvent.click(screen.getByRole("button", { name: "Archive" }));
    await waitFor(() =>
      expect(screen.getByRole("status").textContent).toContain(
        "Something went wrong",
      ),
    );
  });

  it("Select all toggles off when every archivable row is already selected", async () => {
    global.fetch = mockFetchOnce([mergedInbox({ title: "A" })]) as unknown as typeof fetch;
    render(<Wrapped />);
    await waitFor(() => expect(screen.getByText("A")).toBeTruthy());
    // Only one section has rows here → one strip.
    const strip = screen.getAllByRole("checkbox", { name: "Select all" })[0];
    fireEvent.click(strip);
    expect(screen.getByText("1 selected")).toBeTruthy();
    fireEvent.click(strip);
    expect(screen.queryByText("1 selected")).toBeNull();
  });
});
