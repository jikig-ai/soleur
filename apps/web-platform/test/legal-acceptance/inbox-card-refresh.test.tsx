/**
 * AC9 (Ref #12197): after a recorded decision the Inbox row turns FYI and the nav dot clears WITHOUT a reload. The nav badge
 * stays mounted while the founder is on the card page and revalidates only on focus, so the card refreshes the shared inbox key
 * itself when (and only when) a decision is recorded.
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
  flagEnabled: true,
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

describe("a recorded decision refreshes the shared inbox key", () => {
  it("refreshes swrKeys.inbox('active') once the decision is recorded", async () => {
    stubDecide({ body: { outcome: "recorded", choice: "decline", decidedAt: "2026-11-09T10:42:00Z" } });
    const user = userEvent.setup();
    render(<LegalAcceptanceCard {...props} />);
    await user.click(screen.getByRole("button", { name: /^No/ }));
    expect(h.mutate).not.toHaveBeenCalled(); // asking to confirm records nothing
    await user.click(screen.getByRole("button", { name: LEGAL_COPY.decline.confirm }));
    await waitFor(() => expect(screen.getByText(LEGAL_COPY.declined.badge)).toBeInTheDocument());
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
