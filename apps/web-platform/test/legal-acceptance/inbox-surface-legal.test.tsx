/**
 * The founder's legal-text row in the Inbox surface (CPO ruling P3, CTO ruling T7, 2026-11-08; Ref #12197).
 * A legal row: no checkbox, never archivable, never calls /api/inbox/[id]/state, opens /dashboard/approvals/legal/<key>.
 * Copy comes only from the existing deck strings (LEGAL_COPY / the kind's own wording): the expectations below are read from
 * the deck, so a reworded deck needs no edit here, and a hand-written string in the row would fail.
 */
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { cleanup, fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import type { MergedInboxItem, LegalInboxState } from "@/lib/inbox-severity";
import { LEGAL_COPY, LEGAL_KIND_COPY } from "@/lib/legal-acceptance-copy";

let mockStatus: string | null = null;
const mockPush = vi.fn();
vi.mock("next/navigation", () => ({
  useRouter: () => ({ push: mockPush, refresh: vi.fn(), prefetch: vi.fn() }),
  usePathname: () => "/dashboard/inbox",
  useSearchParams: () => new URLSearchParams(mockStatus ? `status=${mockStatus}` : ""),
}));

import { InboxSurface } from "@/components/inbox/inbox-surface";
import { SwrTestProvider } from "../helpers/swr-wrapper";

const KEY = "founder-acceptance-record";
const LABEL = "How your decisions are recorded and kept";

function legal(state: LegalInboxState, over: { key?: string; validUntil?: string | null } = {}): MergedInboxItem {
  const pending = state === "pending";
  return {
    kind: "legal",
    id: over.key ?? KEY,
    severity: pending ? "action_required" : "info",
    pinned: false,
    outstanding: pending,
    legal: { key: over.key ?? KEY, label: LABEL, version: "2026-11-07", validUntil: over.validUntil ?? null, state },
  };
}

function inboxItem(title: string): MergedInboxItem {
  return {
    kind: "inbox",
    id: crypto.randomUUID(),
    severity: "info",
    pinned: false,
    outstanding: false,
    inbox: {
      id: crypto.randomUUID(),
      severity: "info",
      source: "task_completed",
      title,
      source_ref: { conversationId: "c1" },
      status: "read",
      created_at: "2026-07-01T10:00:00.000Z",
      read_at: "2026-07-01T10:00:00.000Z",
      acted_at: null,
      archived_at: null,
    },
  };
}

function Wrapped() {
  return (
    <SwrTestProvider>
      <InboxSurface />
    </SwrTestProvider>
  );
}

const fetchMock = vi.fn();
const mockItems = (items: MergedInboxItem[]) => fetchMock.mockResolvedValue({ ok: true, json: async () => ({ items }) });

beforeEach(() => {
  mockStatus = null;
  mockPush.mockClear();
  fetchMock.mockReset();
  global.fetch = fetchMock as unknown as typeof fetch;
});
afterEach(() => cleanup());

const ack = LEGAL_KIND_COPY.acknowledgement;
const pendingTitle = ack.pendingTitle(LABEL);

describe("legal row states", () => {
  it("pending: NEEDS YOU with the deck's pending title and badge; no checkbox for the row", async () => {
    mockItems([legal("pending")]);
    render(<Wrapped />);
    await waitFor(() => expect(screen.getByText(pendingTitle)).toBeTruthy());
    expect(screen.getByText("NEEDS YOU")).toBeTruthy();
    expect(screen.getByText(LEGAL_COPY.pending.badge)).toBeTruthy();
    expect(screen.queryByRole("checkbox", { name: /^Select: / })).toBeNull();
    // No expiry chip without a valid_until.
    expect(screen.queryByText(/Open until/)).toBeNull();
  });

  it("pending with valid_until shows the deck's open-until chip", async () => {
    mockItems([legal("pending", { validUntil: "2026-12-31" })]);
    render(<Wrapped />);
    await waitFor(() => expect(screen.getByText(LEGAL_COPY.pending.openUntil("2026-12-31"))).toBeTruthy());
  });

  it.each([
    ["accepted", ack.acceptedTitle(LABEL), ack.acceptedBadge],
    ["declined", ack.declinedTitle(LABEL), LEGAL_COPY.declined.badge],
    ["changes_requested", LEGAL_COPY.changesRequested.title, LEGAL_COPY.changesRequested.badge],
    ["expired", LEGAL_COPY.expired.title, LEGAL_COPY.expired.badge],
  ] as const)("%s: FYI under GOOD TO KNOW with the deck's own title and badge", async (state, title, badge) => {
    mockItems([legal(state)]);
    render(<Wrapped />);
    await waitFor(() => expect(screen.getByText(title)).toBeTruthy());
    expect(screen.getByText(badge)).toBeTruthy();
    expect(screen.getByText("GOOD TO KNOW")).toBeTruthy();
    expect(screen.queryByText(pendingTitle)).toBeNull();
    expect(screen.queryByRole("checkbox", { name: /^Select: / })).toBeNull();
  });
});

describe("legal row behaviour", () => {
  it("click opens the card; it never calls the state or archive endpoints", async () => {
    mockItems([legal("pending")]);
    render(<Wrapped />);
    const row = (await waitFor(() => screen.getByText(pendingTitle))).closest("[role=button]") as HTMLElement;
    fireEvent.click(row);
    expect(mockPush).toHaveBeenCalledWith(`/dashboard/approvals/legal/${KEY}`);
    const urls = fetchMock.mock.calls.map((c) => String(c[0]));
    expect(urls.every((u) => u === "/api/inbox")).toBe(true);
  });

  it("Enter on the focused row opens the card too", async () => {
    mockItems([legal("accepted")]);
    render(<Wrapped />);
    const row = (await waitFor(() => screen.getByText(ack.acceptedTitle(LABEL)))).closest("[role=button]") as HTMLElement;
    fireEvent.keyDown(row, { key: "Enter" });
    expect(mockPush).toHaveBeenCalledWith(`/dashboard/approvals/legal/${KEY}`);
  });

  it("archive and select-all keys on a focused legal row are a no-op (no request, no selection bar)", async () => {
    mockItems([legal("accepted")]);
    render(<Wrapped />);
    const row = (await waitFor(() => screen.getByText(ack.acceptedTitle(LABEL)))).closest("[role=button]") as HTMLElement;
    for (const init of [{ key: "e" }, { key: "a" }, { key: "a", ctrlKey: true }, { key: "Delete" }, { key: "#" }]) fireEvent.keyDown(row, init);
    expect(mockPush).not.toHaveBeenCalled();
    expect(fetchMock).toHaveBeenCalledTimes(1);
    expect(screen.queryByText(/selected/)).toBeNull();
  });

  it("has no Archive or Mark done control", async () => {
    mockItems([legal("pending")]);
    render(<Wrapped />);
    await waitFor(() => screen.getByText(pendingTitle));
    expect(screen.queryByRole("button", { name: /archive/i })).toBeNull();
    expect(screen.queryByRole("button", { name: /mark done/i })).toBeNull();
  });

  it("a key that is not a registry-shaped key is non-navigating (never a path built from a free string)", async () => {
    mockItems([legal("pending", { key: "../admin" })]);
    render(<Wrapped />);
    // An undeclared key has no kind wording, so the title is the plain label; the row is not a button and leads nowhere.
    const row = (await waitFor(() => screen.getByText(LABEL))).closest("[data-testid=legal-inbox-row]") as HTMLElement;
    expect(row.getAttribute("role")).toBeNull();
    fireEvent.click(row);
    fireEvent.keyDown(row, { key: "Enter" });
    expect(mockPush).not.toHaveBeenCalled();
  });

  it("legal rows do not take part in Select all: other rows' strip counts only archivable rows", async () => {
    mockItems([legal("accepted"), inboxItem("Design finished")]);
    render(<Wrapped />);
    await waitFor(() => screen.getByText("Design finished"));
    const checkboxes = screen.getAllByRole("checkbox", { name: /^Select: / });
    expect(checkboxes).toHaveLength(1);
    fireEvent.click(screen.getAllByRole("checkbox", { name: "Select all" })[0]);
    expect(screen.getByText("1 selected")).toBeTruthy();
    expect(within(document.body).queryByText("2 selected")).toBeNull();
  });
});

describe("row-state transitions", () => {
  it("pending turns FYI when the shared inbox key is refreshed (what a recorded decision triggers), without a reload", async () => {
    const { useSWRConfig } = await import("swr");
    const { swrKeys } = await import("@/lib/swr-config");
    function Refresh() {
      const { mutate } = useSWRConfig();
      return <button onClick={() => void mutate(swrKeys.inbox("active"))}>refresh-shared-key</button>;
    }
    mockItems([legal("pending")]);
    render(
      <SwrTestProvider>
        <Refresh />
        <InboxSurface />
      </SwrTestProvider>,
    );
    await waitFor(() => screen.getByText(pendingTitle));
    mockItems([legal("accepted")]);
    fireEvent.click(screen.getByText("refresh-shared-key"));
    await waitFor(() => expect(screen.getByText(ack.acceptedTitle(LABEL))).toBeTruthy());
    expect(screen.queryByText(pendingTitle)).toBeNull();
    expect(screen.getByText("GOOD TO KNOW")).toBeTruthy();
  });

  it("a replaced text (new hash, no answer for it) is a pending row for the new version", async () => {
    const item = legal("pending");
    if (item.kind !== "legal") throw new Error("fixture");
    item.legal.version = "2026-12-01";
    mockItems([item]);
    render(<Wrapped />);
    await waitFor(() => expect(screen.getByText(pendingTitle)).toBeTruthy());
    expect(screen.getByText(/2026-12-01/)).toBeTruthy();
  });
});
