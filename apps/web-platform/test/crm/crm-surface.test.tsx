import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { cleanup, fireEvent, render, screen, waitFor } from "@testing-library/react";

// next/navigation mocked: `mockContact` drives the ?contact= deep-link param.
// The drawer is LOCAL state — open uses pushState, close uses replaceState.
let mockContact: string | null = null;
vi.mock("next/navigation", () => ({
  usePathname: () => "/dashboard/crm",
  useSearchParams: () =>
    new URLSearchParams(mockContact ? `contact=${mockContact}` : ""),
}));

import { CrmSurface } from "@/components/crm/crm-surface";
import { SwrTestProvider } from "../helpers/swr-wrapper";
import type { CrmContact } from "@/components/crm/pipeline-column";

function contact(over: Partial<CrmContact> = {}): CrmContact {
  return {
    id: "c1",
    company: "Northwind Labs",
    name: "Priya Raman",
    role: "Founder",
    stage: "new",
    amount: 2400,
    currency: "USD",
    last_contact: "2026-07-06",
    ...over,
  };
}

// Route global.fetch by URL prefix.
function routeFetch(
  map: Record<string, { ok?: boolean; status?: number; body: unknown }>,
) {
  // Longest key first so "/api/crm/contacts/c1" wins over "/api/crm/contacts".
  const keys = Object.keys(map).sort((a, b) => b.length - a.length);
  return vi.fn(async (input: RequestInfo | URL) => {
    const url = typeof input === "string" ? input : input.toString();
    const key = keys.find((k) => url === k || url.startsWith(k));
    if (!key) return { ok: false, status: 404, json: async () => ({ error: "not_found" }) };
    const v = map[key];
    return { ok: v.ok ?? true, status: v.status ?? 200, json: async () => v.body };
  });
}

function Wrapped() {
  return (
    <SwrTestProvider>
      <CrmSurface />
    </SwrTestProvider>
  );
}

beforeEach(() => {
  mockContact = null;
});
afterEach(() => {
  cleanup();
  vi.restoreAllMocks();
});

describe("CrmSurface board", () => {
  it("renders one column per funnel stage — EMPTY columns too — plus the Closed Lost rail (AC7)", async () => {
    global.fetch = routeFetch({
      "/api/crm/contacts": { body: { contacts: [contact({ id: "c1", stage: "qualified" })] } },
    }) as unknown as typeof fetch;

    render(<Wrapped />);

    // Every funnel stage column renders regardless of occupancy.
    await waitFor(() => expect(screen.getByRole("button", { name: /Open Northwind Labs detail/ })).toBeTruthy());
    for (const label of ["New stage", "Contacted stage", "Qualified stage", "Evaluating stage", "Committed stage", "Closed Won stage"]) {
      expect(screen.getByLabelText(new RegExp(label))).toBeTruthy();
    }
    // Closed Lost renders as the collapsed terminal rail.
    expect(screen.getByLabelText(/Closed Lost: 0/)).toBeTruthy();
  });

  it("shows the empty state when there are zero contacts", async () => {
    global.fetch = routeFetch({
      "/api/crm/contacts": { body: { contacts: [] } },
    }) as unknown as typeof fetch;

    render(<Wrapped />);
    await waitFor(() => expect(screen.getByText("No contacts yet")).toBeTruthy());
    expect(screen.getByText(/This board is read-only/)).toBeTruthy();
  });

  it("shows an ErrorCard + Retry when the list request fails", async () => {
    global.fetch = routeFetch({
      "/api/crm/contacts": { ok: false, status: 502, body: { error: "contacts_query_error" } },
    }) as unknown as typeof fetch;

    render(<Wrapped />);
    await waitFor(() => expect(screen.getByText("Failed to load the board")).toBeTruthy());
    // No raw server text leaks into the UI.
    expect(screen.queryByText(/contacts_query_error/)).toBeNull();
  });

  it("cold deep-link (?contact=c1) opens the drawer AND fetches the board underneath (AC8)", async () => {
    mockContact = "c1";
    global.fetch = routeFetch({
      "/api/crm/contacts/c1": {
        body: {
          contact: { id: "c1", company: "Bright Ledger", name: "Marco Ruiz", role: "CEO", source: null, stage: "qualified", amount: 6000, currency: "USD", last_contact: "2026-07-02", created_at: "2026-06-08T00:00:00Z" },
          notes: [],
          transitions: [],
        },
      },
      "/api/crm/contacts": { body: { contacts: [contact({ id: "c2", company: "Northwind Labs" })] } },
    }) as unknown as typeof fetch;

    render(<Wrapped />);

    // Drawer (portal) shows the detail…
    await waitFor(() => expect(screen.getByRole("dialog")).toBeTruthy());
    expect(screen.getAllByText("Bright Ledger").length).toBeGreaterThan(0);
    // …and the board underneath fetched its list.
    expect(screen.getByRole("button", { name: /Open Northwind Labs detail/ })).toBeTruthy();
  });

  it("toggling to Funnel closes an open drawer (AC8) and stays interactive", async () => {
    global.fetch = routeFetch({
      "/api/crm/contacts/c1": {
        body: {
          contact: { id: "c1", company: "Northwind Labs", name: "Priya Raman", role: "Founder", source: null, stage: "new", amount: 2400, currency: "USD", last_contact: "2026-07-06", created_at: "2026-07-01T00:00:00Z" },
          notes: [],
          transitions: [],
        },
      },
      "/api/crm/contacts": { body: { contacts: [contact({ id: "c1", stage: "new" })] } },
      "/api/crm/funnel": { body: { stages: [{ stage: "new", reached: 1, conversionPct: null }], closedLost: 0, avgTimeInStageDays: null, perTransition: [] } },
    }) as unknown as typeof fetch;

    render(<Wrapped />);
    await waitFor(() => expect(screen.getByRole("button", { name: /Open Northwind Labs detail/ })).toBeTruthy());

    // Open the drawer.
    fireEvent.click(screen.getByRole("button", { name: /Open Northwind Labs detail/ }));
    await waitFor(() => expect(screen.getByRole("dialog")).toBeTruthy());

    // Switch to Funnel — the drawer must close.
    fireEvent.click(screen.getByRole("tab", { name: "funnel" }));
    await waitFor(() => expect(screen.queryByRole("dialog")).toBeNull());
    // Toggle is still interactive: switch back to Board.
    fireEvent.click(screen.getByRole("tab", { name: "board" }));
    await waitFor(() => expect(screen.getByRole("button", { name: /Open Northwind Labs detail/ })).toBeTruthy());
  });
});
