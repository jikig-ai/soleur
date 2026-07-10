// Live support path (ADR-109): with `support-live` ON, sending a message calls
// POST /api/support and renders the streamed Concierge reply. Inverts the old
// "no network call" assertion (Phase 8.2).

import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen, fireEvent, cleanup, within, waitFor } from "@testing-library/react";

const flagState = vi.hoisted(() => ({ support: true, "support-live": true }));
vi.mock("@/components/feature-flags/provider", () => ({
  useOptionalFeatureFlag: (name: string) =>
    (flagState as Record<string, boolean>)[name] ?? false,
}));
vi.mock("next/navigation", () => ({
  useRouter: () => ({ push: vi.fn(), replace: vi.fn(), prefetch: vi.fn() }),
}));
vi.mock("@/components/tour/tour-provider", () => ({
  useTour: () => ({ available: false, startTour: vi.fn() }),
}));

import { SupportLauncher } from "@/components/support/support-launcher";
import { formatSupportSseFrame } from "@/lib/support-sse";
import type { WSMessage } from "@/lib/types";

/** A Response whose body streams the given dispatch frames as SSE. */
function sseResponse(frames: WSMessage[]): Response {
  const enc = new TextEncoder();
  const body = new ReadableStream<Uint8Array>({
    start(controller) {
      for (const f of frames) controller.enqueue(enc.encode(formatSupportSseFrame(f)));
      controller.close();
    },
  });
  return new Response(body, { status: 200, headers: { "Content-Type": "text/event-stream" } });
}

describe("support live path (support-live ON)", () => {
  beforeEach(() => {
    flagState.support = true;
    flagState["support-live"] = true;
  });
  afterEach(() => {
    cleanup();
    vi.unstubAllGlobals();
  });

  it("sends via POST /api/support and renders the streamed reply", async () => {
    const fetchSpy = vi.fn().mockResolvedValue(
      sseResponse([
        { type: "stream_start", leaderId: "cc_router" } as WSMessage,
        { type: "stream", content: "Open Routines from the left sidebar.", partial: true, leaderId: "cc_router" } as WSMessage,
        { type: "session_ended" } as WSMessage,
      ]),
    );
    vi.stubGlobal("fetch", fetchSpy);

    render(<SupportLauncher />);
    fireEvent.click(screen.getByLabelText("Open support"));
    const dialog = screen.getByRole("dialog");
    const textarea = within(dialog).getByPlaceholderText("Ask a question…");
    fireEvent.change(textarea, { target: { value: "how do I create a routine?" } });
    fireEvent.click(within(dialog).getByLabelText("Send message"));

    // The live path hits the SSE transport (NOT the canned no-network path).
    expect(fetchSpy).toHaveBeenCalledWith("/api/support", expect.objectContaining({ method: "POST" }));
    // User bubble immediately present.
    expect(within(dialog).getByText("how do I create a routine?")).toBeTruthy();
    // Streamed reply appears.
    await waitFor(() =>
      expect(within(dialog).getByText(/Open Routines from the left sidebar/)).toBeTruthy(),
    );
  });

  it("falls back to the canned reply when the transport fails", async () => {
    vi.stubGlobal("fetch", vi.fn().mockRejectedValue(new Error("network down")));

    render(<SupportLauncher />);
    fireEvent.click(screen.getByLabelText("Open support"));
    const dialog = screen.getByRole("dialog");
    const textarea = within(dialog).getByPlaceholderText("Ask a question…");
    fireEvent.change(textarea, { target: { value: "hello" } });
    fireEvent.click(within(dialog).getByLabelText("Send message"));

    // Honest fallback (canned) keeps the user un-stuck.
    await waitFor(() =>
      expect(within(dialog).getByText(/knowledge base/i)).toBeTruthy(),
    );
  });
});
