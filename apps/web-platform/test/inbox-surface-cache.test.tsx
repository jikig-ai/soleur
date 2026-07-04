import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { cleanup, render, screen, waitFor } from "@testing-library/react";
import { SWRConfig } from "swr";
import type { EmailTriageItem } from "@/components/inbox/email-triage-row";
import type { MergedInboxItem } from "@/lib/inbox-severity";

// AC1 (FR1): a warm cache-hit remount renders content with NO loading spinner
// and fires NO refetch within the dedup window — the invariant is asserted on
// the fetcher call COUNT, not DOM presence. AC7: the ambient gold shimmer never
// shows before there is cached data, and no "from cache" status text exists.

let mockStatus: string | null = null;
vi.mock("next/navigation", () => ({
  useRouter: () => ({ push: vi.fn(), refresh: vi.fn(), prefetch: vi.fn() }),
  usePathname: () => "/dashboard/inbox",
  useSearchParams: () =>
    new URLSearchParams(mockStatus ? `status=${mockStatus}` : ""),
}));

import { InboxSurface } from "@/components/inbox/inbox-surface";

function item(subject: string): MergedInboxItem {
  const email: EmailTriageItem = {
    id: crypto.randomUUID(),
    message_id: null,
    sender: "vendor@example.com",
    subject,
    summary: "s",
    mail_class: "vendor",
    statutory_class: null,
    rule_id: null,
    status: "new",
    status_changed_at: null,
    acknowledged_at: null,
    received_at: "2026-06-18T10:00:00.000Z",
    created_at: "2026-06-18T10:00:00.000Z",
  };
  return {
    kind: "email",
    id: email.id,
    severity: "info",
    pinned: false,
    outstanding: false,
    email,
  };
}

beforeEach(() => {
  mockStatus = null;
});
afterEach(() => {
  cleanup();
  vi.restoreAllMocks();
});

// A shared cache + a long dedup window simulate the real app, where a remount
// inside the dedup window is served from cache without a refetch.
function Harness({ show }: { show: boolean }) {
  return (
    <SWRConfig
      value={{
        provider: () => Harness.cache as never,
        dedupingInterval: 100_000,
        shouldRetryOnError: false,
      }}
    >
      {show ? <InboxSurface /> : <div data-testid="elsewhere">away</div>}
    </SWRConfig>
  );
}
Harness.cache = new Map<string, unknown>();

describe("InboxSurface — cache hit on remount (AC1/AC7)", () => {
  it("renders cached content instantly and does not refetch on a warm remount", async () => {
    Harness.cache = new Map();
    const fetchMock = vi.fn().mockResolvedValue({
      ok: true,
      json: async () => ({ items: [item("Cached subject")] }),
    });
    global.fetch = fetchMock as unknown as typeof fetch;

    const { rerender } = render(<Harness show />);
    await waitFor(() => expect(screen.getByText("Cached subject")).toBeTruthy());
    expect(fetchMock).toHaveBeenCalledTimes(1);

    // Navigate away (unmount the surface) then back (remount).
    rerender(<Harness show={false} />);
    expect(screen.queryByText("Cached subject")).toBeNull();
    rerender(<Harness show />);

    // FR1: content is present on the FIRST frame after remount — no Loading
    // flash. (Synchronous query, no waitFor.)
    expect(screen.getByText("Cached subject")).toBeTruthy();
    expect(screen.queryByText(/loading/i)).toBeNull();
    // AC1 invariant: zero refetch on the warm remount (inside dedup window).
    expect(fetchMock).toHaveBeenCalledTimes(1);
  });

  it("never shows the shimmer before there is data, and exposes no 'from cache' status", async () => {
    Harness.cache = new Map();
    // A fetch that never resolves: data stays undefined, isValidating stays true.
    global.fetch = vi.fn(
      () => new Promise(() => {}),
    ) as unknown as typeof fetch;

    render(<Harness show />);
    // First load (no cached data): the ambient shimmer must NOT render — it is
    // gated on `isValidating && data`, not isValidating alone.
    expect(screen.queryByTestId("refresh-shimmer")).toBeNull();
    // No cache-status indicator anywhere.
    expect(screen.queryByText(/from cache/i)).toBeNull();
    expect(screen.getByText(/loading/i)).toBeTruthy();
  });
});
