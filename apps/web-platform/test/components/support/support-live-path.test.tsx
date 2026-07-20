// Live support path (ADR-113): with `support-live` ON, sending a message calls
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
    // Live copy (Phase 6): the panel shows the live subtitle, not the preview one.
    expect(within(dialog).getByText(/always on/i)).toBeTruthy();
    expect(within(dialog).queryByText(/coming soon/i)).toBeNull();
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

  it("New conversation button: appears after a turn, clears history, and the next send mints a fresh thread", async () => {
    // Distinct reply per call so transcript assertions are unambiguous.
    let turn = 0;
    const fetchSpy = vi.fn().mockImplementation(async () => {
      turn += 1;
      return sseResponse([
        { type: "stream", content: `reply-${turn}`, partial: true, leaderId: "cc_router" } as WSMessage,
        { type: "session_ended" } as WSMessage,
      ]);
    });
    vi.stubGlobal("fetch", fetchSpy);

    render(<SupportLauncher />);
    fireEvent.click(screen.getByLabelText("Open support"));
    const dialog = screen.getByRole("dialog");

    // No new-conversation button on an empty thread.
    expect(within(dialog).queryByLabelText("New conversation")).toBeNull();

    const textarea = within(dialog).getByPlaceholderText("Ask a question…");
    fireEvent.change(textarea, { target: { value: "first question" } });
    fireEvent.click(within(dialog).getByLabelText("Send message"));
    await waitFor(() => expect(within(dialog).getByText("reply-1")).toBeTruthy());
    // First send does NOT force a new conversation.
    expect(JSON.parse(fetchSpy.mock.calls[0][1].body)).toEqual({ message: "first question" });

    // Button now present; clicking it clears the transcript.
    fireEvent.click(within(dialog).getByLabelText("New conversation"));
    expect(within(dialog).queryByText("reply-1")).toBeNull();
    expect(within(dialog).queryByText("first question")).toBeNull();
    // And the button hides again on the now-empty thread.
    expect(within(dialog).queryByLabelText("New conversation")).toBeNull();

    // The NEXT send carries newConversation:true exactly once.
    fireEvent.change(textarea, { target: { value: "second question" } });
    fireEvent.click(within(dialog).getByLabelText("Send message"));
    await waitFor(() => expect(within(dialog).getByText("reply-2")).toBeTruthy());
    expect(JSON.parse(fetchSpy.mock.calls[1][1].body)).toEqual({
      message: "second question",
      newConversation: true,
    });

    // A THIRD send reuses (flag consumed — no newConversation).
    fireEvent.change(textarea, { target: { value: "third question" } });
    fireEvent.click(within(dialog).getByLabelText("Send message"));
    await waitFor(() => expect(within(dialog).getByText("reply-3")).toBeTruthy());
    expect(JSON.parse(fetchSpy.mock.calls[2][1].body)).toEqual({ message: "third question" });
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
