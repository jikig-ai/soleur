import { afterEach, describe, expect, it, vi } from "vitest";
import { cleanup, render, screen, waitFor } from "@testing-library/react";

import { ContactDetailSheet } from "@/components/crm/contact-detail-sheet";
import { SwrTestProvider } from "../helpers/swr-wrapper";

function fetchReturning(res: { ok: boolean; status: number; body: unknown }) {
  return vi.fn(async () => ({
    ok: res.ok,
    status: res.status,
    json: async () => res.body,
  })) as unknown as typeof fetch;
}

function renderSheet(id: string | null) {
  return render(
    <SwrTestProvider>
      <ContactDetailSheet contactId={id} onClose={() => {}} />
    </SwrTestProvider>,
  );
}

afterEach(() => {
  cleanup();
  vi.restoreAllMocks();
});

describe("ContactDetailSheet", () => {
  it("renders nothing when contactId is null", () => {
    global.fetch = fetchReturning({ ok: true, status: 200, body: {} });
    renderSheet(null);
    expect(screen.queryByRole("dialog")).toBeNull();
  });

  it("renders company, dual-lens notes, and stage history on success", async () => {
    global.fetch = fetchReturning({
      ok: true,
      status: 200,
      body: {
        contact: { id: "c1", company: "Bright Ledger", name: "Marco Ruiz", role: "CEO", source: "CRO agent conversation", stage: "qualified", amount: 6000, currency: "USD", last_contact: "2026-07-02", created_at: "2026-06-08T00:00:00Z" },
        notes: [
          { id: "n1", body: "We're drowning in manual reconciliation.", lens: ["sales"], occurred_at: "2026-06-12", created_at: "2026-06-12T00:00:00Z" },
          { id: "n2", body: "Recurring, acute pain — strong wedge.", lens: ["product"], occurred_at: "2026-06-12", created_at: "2026-06-12T00:00:00Z" },
        ],
        transitions: [
          { id: "t1", from_stage: "new", to_stage: "contacted", entered_at: "2026-06-12T00:00:00Z" },
          { id: "t2", from_stage: "contacted", to_stage: "qualified", entered_at: "2026-06-20T00:00:00Z" },
        ],
      },
    });

    renderSheet("c1");
    await waitFor(() => expect(screen.getByRole("dialog")).toBeTruthy());
    expect(screen.getByRole("heading", { name: "Bright Ledger" })).toBeTruthy();
    // Dual-lens labels.
    expect(screen.getByText("What they said")).toBeTruthy();
    expect(screen.getByText("What it means")).toBeTruthy();
    // Stage history includes the implicit 'new' + transitions, current marked.
    expect(screen.getByText("Note timeline")).toBeTruthy();
    expect(screen.getByText("Stage history")).toBeTruthy();
    expect(screen.getByText(/· current/)).toBeTruthy();
    // Read-only escape hatch.
    expect(screen.getByText(/Read-only\./)).toBeTruthy();
  });

  it("shows a neutral, no-oracle notFound state on 404", async () => {
    global.fetch = fetchReturning({ ok: false, status: 404, body: { error: "not_found" } });
    renderSheet("missing");
    await waitFor(() => expect(screen.getByText(/This contact isn't available/)).toBeTruthy());
    expect(screen.getByRole("button", { name: "Back to board" })).toBeTruthy();
    // No raw error code leaks.
    expect(screen.queryByText(/not_found/)).toBeNull();
  });

  it("shows an ErrorCard + Retry (not raw server text) on a 5xx", async () => {
    global.fetch = fetchReturning({ ok: false, status: 502, body: { error: "detail_query_error" } });
    renderSheet("c1");
    await waitFor(() => expect(screen.getByText("Couldn't load this contact")).toBeTruthy());
    expect(screen.queryByText(/detail_query_error/)).toBeNull();
  });
});
