import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";
import { render, screen, waitFor } from "@testing-library/react";
import { userEvent } from "@testing-library/user-event";

import { TodayCard } from "@/components/dashboard/today-card";

// #4579 — KB-drift DIGEST card (one row summarizing N findings). It renders a
// Dismiss affordance (archive via the existing /discard route), NOT the
// per-finding spawn/send button. Mirrors the mock policy of
// today-card.click.test.tsx (method-aware fetch mock; no MSW).

const { createClientMock } = vi.hoisted(() => ({ createClientMock: vi.fn() }));
vi.mock("@/lib/supabase/client", () => ({ createClient: createClientMock }));

function buildNoOpSupabaseClient() {
  const fromChain: Record<string, unknown> = {};
  Object.assign(fromChain, {
    select: vi.fn(() => fromChain),
    eq: vi.fn(() => fromChain),
    maybeSingle: vi.fn(() => Promise.resolve({ data: null, error: null })),
  });
  const channel: Record<string, unknown> = {};
  Object.assign(channel, { on: vi.fn(() => channel), subscribe: vi.fn(() => channel) });
  return {
    from: vi.fn(() => fromChain),
    channel: vi.fn(() => channel),
    removeChannel: vi.fn(),
  };
}

const ORIGINAL_FETCH = globalThis.fetch;
let lastFetch: { url: string; method: string } | null = null;
let nextStatus = 200;

const DIGEST_PROPS = {
  id: "msg-digest-1",
  source: "kb-drift",
  sourceRef: "digest-abc123",
  owningDomain: "knowledge",
  draftPreview: "3 KB-drift findings — review\n• Broken link in a.md → /x",
  urgency: "low",
};

beforeEach(() => {
  vi.clearAllMocks();
  createClientMock.mockReturnValue(buildNoOpSupabaseClient());
  lastFetch = null;
  nextStatus = 200;
  globalThis.fetch = vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
    lastFetch = { url: String(input), method: init?.method ?? "GET" };
    return new Response(JSON.stringify({ ok: true }), { status: nextStatus });
  }) as typeof fetch;
});

afterEach(() => {
  globalThis.fetch = ORIGINAL_FETCH;
});

describe("KbDriftCard — digest variant", () => {
  it("renders a Dismiss button and NO send-capable affordance (regression guard)", () => {
    render(<TodayCard {...DIGEST_PROPS} />);
    expect(screen.getByRole("button", { name: /dismiss digest/i })).toBeTruthy();
    // The spawn/send button must NOT be present for a digest card.
    expect(document.querySelector('[data-action="kb-drift-fix"]')).toBeNull();
    expect(document.querySelector('[data-action="kb-drift-dismiss"]')).not.toBeNull();
  });

  it("Dismiss POSTs to /discard and removes the card on success", async () => {
    const user = userEvent.setup();
    render(<TodayCard {...DIGEST_PROPS} />);
    await user.click(screen.getByRole("button", { name: /dismiss digest/i }));
    await waitFor(() => {
      expect(lastFetch?.url).toContain(`/api/dashboard/today/${DIGEST_PROPS.id}/discard`);
      expect(lastFetch?.method).toBe("POST");
    });
    // Card archives (returns null) on a 200 discard.
    await waitFor(() => {
      expect(document.querySelector(`[data-message-id="${DIGEST_PROPS.id}"]`)).toBeNull();
    });
  });

  it("restores the card and shows an error when /discard fails", async () => {
    nextStatus = 500;
    const user = userEvent.setup();
    render(<TodayCard {...DIGEST_PROPS} />);
    await user.click(screen.getByRole("button", { name: /dismiss digest/i }));
    await waitFor(() => {
      expect(screen.getByRole("alert").textContent).toMatch(/Dismiss failed \(500\)/);
    });
    // Card is restored (not archived) so the operator can retry.
    expect(document.querySelector(`[data-message-id="${DIGEST_PROPS.id}"]`)).not.toBeNull();
  });
});

describe("KbDriftCard — legacy per-finding variant still spawns", () => {
  it("a non-digest (link-*) card renders the spawn button, not Dismiss", () => {
    render(<TodayCard {...DIGEST_PROPS} sourceRef="link-deadbeef00000000" />);
    expect(document.querySelector('[data-action="kb-drift-fix"]')).not.toBeNull();
    expect(document.querySelector('[data-action="kb-drift-dismiss"]')).toBeNull();
  });
});
