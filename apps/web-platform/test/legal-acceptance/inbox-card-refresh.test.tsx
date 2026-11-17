/**
 * AC9 (Ref #12197), the card's half: a recorded decision asks SWR to revalidate the shared inbox key, `swrKeys.inbox("active")`,
 * and a refused one does not. The nav badge (mounted in the dashboard shell) revalidates only on focus, so without this call it
 * would keep showing the outstanding dot until the founder refocused the window. That the badge and the Inbox list then turn
 * FYI is SWR's own behavior for that key (they read it through `fetchMergedInbox`), covered where the badge and surface are
 * tested (`inbox-nav-badge.test.tsx`, `inbox-surface-legal.test.tsx`); this file pins only that `mutate` is called, with that key,
 * once, and only after a recorded decision.
 */
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { cleanup, render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { LegalAcceptanceCard } from "@/components/approvals/legal-acceptance-card";
import { LEGAL_COPY } from "@/lib/legal-acceptance-copy";
import { swrKeys } from "@/lib/swr-config";

const h = vi.hoisted(() => ({ mutate: vi.fn() }));
vi.mock("swr", async (orig) => {
  const real = await orig<typeof import("swr")>();
  return { ...real, useSWRConfig: () => ({ ...real.useSWRConfig(), mutate: h.mutate }) };
});

const HASH = "10d283e02d4543d291468750655bbaf4375f807a585cd5138724a362b993a287";
const props = {
  keyName: "founder-acceptance-record",
  label: "How your decisions are recorded and kept",
  version: "2026-11-07",
  body: "Short text.\n",
  textHash: HASH,
  validUntil: null,
  state: "pending" as const,
  row: null,
  surfaceEnabled: true,
  email: "founder@example.com",
  currentVersion: "2026-11-07",
};

function stubDecide(reply: { status?: number; body: unknown }) {
  vi.stubGlobal(
    "fetch",
    vi.fn(async () => ({ ok: (reply.status ?? 200) < 300, status: reply.status ?? 200, json: async () => reply.body })),
  );
}

beforeEach(() => h.mutate.mockReset());
afterEach(() => {
  cleanup();
  vi.unstubAllGlobals();
});

describe("the card revalidates the shared inbox key on a recorded decision, and only then", () => {
  it("refreshes swrKeys.inbox('active') once the decision is recorded", async () => {
    stubDecide({ body: { outcome: "recorded", choice: "decline", decidedAt: "2026-11-09T10:42:00Z" } });
    const user = userEvent.setup();
    render(<LegalAcceptanceCard {...props} />);
    await user.click(screen.getByRole("button", { name: /^No/ }));
    expect(h.mutate).not.toHaveBeenCalled(); // asking to confirm records nothing
    await user.click(screen.getByRole("button", { name: LEGAL_COPY.decline.confirm }));
    await waitFor(() => expect(screen.getByText(LEGAL_COPY.declined.badge)).toBeInTheDocument());
    expect(h.mutate).toHaveBeenCalledTimes(1);
    expect(h.mutate).toHaveBeenCalledWith(swrKeys.inbox("active"));
  });

  it("does not refresh when the decision was refused (nothing recorded)", async () => {
    stubDecide({ status: 400, body: { error: "nope" } });
    const user = userEvent.setup();
    render(<LegalAcceptanceCard {...props} />);
    await user.click(screen.getByRole("button", { name: /^No/ }));
    await user.click(screen.getByRole("button", { name: LEGAL_COPY.decline.confirm }));
    await waitFor(() => expect(screen.getByText(LEGAL_COPY.errors.nothingRecorded)).toBeInTheDocument());
    expect(h.mutate).not.toHaveBeenCalled();
  });
});
