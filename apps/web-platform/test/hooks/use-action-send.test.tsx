/**
 * #10543 — useActionSend: client handling of the new send-route contract.
 *
 * Both entry points (`onSend`, and `onConfirmTyped` once the typed-confirm modal is open) must handle:
 *   503 enqueue_unavailable            → approval saved, retry copy, NOT acknowledged, NOT archived, modal stays open
 *   409 approval_expired               → copy split on the additive `reason` (expired / future_clicked_at); an absent or
 *                                        unknown reason keeps the "can no longer run" fallback
 *   409 not_a_draft                    → "already handled" (usually a second tab or a click after a client abort)
 *   409 draft_changed_since_approval   → restore-or-refresh copy, nothing acknowledged
 *   409 send_in_progress               → "another send is in progress", never acknowledges or archives
 *   403 with no denyReasonCopy entry   → generic "Permissions changed" copy
 * and the confirm path adopts the fresh draft hash from a 409 requires_confirmation so a retype does not loop.
 */

import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { renderHook, act, waitFor } from "@testing-library/react";

vi.mock("@/lib/client-observability", () => ({
  reportSilentFallback: vi.fn(),
}));

import { useActionSend } from "@/hooks/use-action-send";

const ORIGINAL_FETCH = globalThis.fetch;

let responses: Array<{ status: number; body: Record<string, unknown> }> = [];

beforeEach(() => {
  responses = [];
  globalThis.fetch = vi.fn(async () => {
    const next = responses.shift() ?? { status: 200, body: {} };
    return new Response(JSON.stringify(next.body), {
      status: next.status,
      headers: { "Content-Type": "application/json" },
    });
  }) as unknown as typeof fetch;
});

afterEach(() => {
  globalThis.fetch = ORIGINAL_FETCH;
});

const COPY_503 =
  "Your approval is saved, but we couldn't send it yet. Try again in a moment.";
// Fallback for an approval_expired body with an absent or unknown `reason` (deploy skew either way).
const COPY_NO_LONGER = "This approval can no longer run. Refresh to update this card.";
const COPY_EXPIRED =
  "This approval expired, so this attempt didn't go through. Refresh to update this card.";
const COPY_SKEW =
  "We couldn't confirm when you approved this, so this attempt didn't go through. Try again shortly.";
const COPY_HANDLED =
  "This draft was already handled, maybe in another tab. Refresh to update this card.";
const COPY_CHANGED =
  "This draft changed after you approved it, so this approval can't run.";
const COPY_IN_PROGRESS = "Another send is in progress — try again in a moment";
const COPY_PERMISSIONS =
  "Permissions changed since you approved. This action can't run.";

function setup() {
  const onAcknowledgedArchive = vi.fn();
  const hook = renderHook(() =>
    useActionSend({ messageId: "msg-1", onAcknowledgedArchive }),
  );
  return { ...hook, onAcknowledgedArchive };
}

/** Drive onSend to a 409 requires_confirmation so the confirm modal state is open. */
async function openConfirm(
  hook: ReturnType<typeof setup>,
  hash = "hash-1",
): Promise<void> {
  responses.push({
    status: 409,
    body: {
      error: "requires_confirmation",
      action_class: "finance.payment_failed",
      tier: "approve_every_time",
      recipient_excerpt: "r",
      content_excerpt: "c",
      expected_draft_preview_hash: hash,
      message_id: "msg-1",
    },
  });
  act(() => hook.result.current.onSend());
  await waitFor(() => expect(hook.result.current.confirming).not.toBeNull());
}

const CASES: Array<{
  name: string;
  status: number;
  body: Record<string, unknown>;
  copy: string;
}> = [
  {
    name: "503 enqueue_unavailable",
    status: 503,
    body: { error: "enqueue_unavailable", action_send_id: "as-1", retryable: true },
    copy: COPY_503,
  },
  {
    name: "409 approval_expired reason=expired",
    status: 409,
    body: { error: "approval_expired", message_id: "msg-1", reason: "expired" },
    copy: COPY_EXPIRED,
  },
  {
    name: "409 approval_expired reason=future_clicked_at",
    status: 409,
    body: {
      error: "approval_expired",
      message_id: "msg-1",
      reason: "future_clicked_at",
    },
    copy: COPY_SKEW,
  },
  {
    name: "409 approval_expired with no reason (older server)",
    status: 409,
    body: { error: "approval_expired", message_id: "msg-1" },
    copy: COPY_NO_LONGER,
  },
  {
    name: "409 approval_expired with an unknown string reason",
    status: 409,
    body: { error: "approval_expired", message_id: "msg-1", reason: "other" },
    copy: COPY_NO_LONGER,
  },
  {
    name: "409 approval_expired with a non-string reason",
    status: 409,
    body: { error: "approval_expired", message_id: "msg-1", reason: 7 },
    copy: COPY_NO_LONGER,
  },
  {
    name: "409 not_a_draft",
    status: 409,
    body: { error: "not_a_draft", status: "archived" },
    copy: COPY_HANDLED,
  },
  {
    name: "409 draft_changed_since_approval",
    status: 409,
    body: { error: "draft_changed_since_approval", message_id: "msg-1" },
    copy: COPY_CHANGED,
  },
  {
    name: "409 send_in_progress",
    status: 409,
    body: { error: "send_in_progress", message_id: "msg-1" },
    copy: COPY_IN_PROGRESS,
  },
  {
    name: "403 no_active_grant (no denyReasonCopy)",
    status: 403,
    body: { error: "no_active_grant", action_class: "x" },
    copy: COPY_PERMISSIONS,
  },
];

describe("onSend", () => {
  it.each(CASES)("$name sets its copy and never acknowledges or archives", async (c) => {
    const hook = setup();
    responses.push({ status: c.status, body: c.body });

    act(() => hook.result.current.onSend());
    await waitFor(() => expect(hook.result.current.error).toBe(c.copy));

    expect(hook.result.current.acknowledged).toBe(false);
    expect(hook.onAcknowledgedArchive).not.toHaveBeenCalled();
  });

  it("409 already_sent stays a soft success (acknowledged + archive)", async () => {
    const hook = setup();
    responses.push({
      status: 409,
      body: { error: "already_sent", message_id: "msg-1" },
    });

    act(() => hook.result.current.onSend());
    await waitFor(() => expect(hook.result.current.acknowledged).toBe(true));
    expect(hook.onAcknowledgedArchive).toHaveBeenCalledTimes(1);
  });
});

describe("onConfirmTyped", () => {
  it.each(CASES)("$name sets its copy, keeps the modal open, and never acknowledges or archives", async (c) => {
    const hook = setup();
    await openConfirm(hook, "hash-1");
    responses.push({ status: c.status, body: c.body });

    act(() => hook.result.current.onConfirmTyped(true, "SEND"));
    await waitFor(() => expect(hook.result.current.error).toBe(c.copy));

    expect(hook.result.current.acknowledged).toBe(false);
    expect(hook.onAcknowledgedArchive).not.toHaveBeenCalled();
    expect(hook.result.current.confirming).not.toBeNull();
    expect(hook.result.current.confirming?.expectedDraftPreviewHash).toBe(
      "hash-1",
    );
  });

  it("a 409 requires_confirmation adopts the fresh expected_draft_preview_hash and keeps the 're-send' copy", async () => {
    const hook = setup();
    await openConfirm(hook, "hash-stale");
    responses.push({
      status: 409,
      body: {
        error: "requires_confirmation",
        expected_draft_preview_hash: "hash-fresh",
        message_id: "msg-1",
      },
    });

    act(() => hook.result.current.onConfirmTyped(true, "SEND"));
    await waitFor(() =>
      expect(hook.result.current.error).toBe(
        "Draft changed since you confirmed — please re-send.",
      ),
    );
    expect(hook.result.current.confirming?.expectedDraftPreviewHash).toBe(
      "hash-fresh",
    );
  });

  it("any other 409 falls through to the generic 'Send failed (409)'", async () => {
    const hook = setup();
    await openConfirm(hook);
    responses.push({ status: 409, body: { error: "something_new" } });

    act(() => hook.result.current.onConfirmTyped(true, "SEND"));
    await waitFor(() =>
      expect(hook.result.current.error).toBe("Send failed (409)"),
    );
  });
});

describe("bare 503 (no enqueue_unavailable body) is not an 'approval saved' claim", () => {
  it("onSend: a gateway 503 falls through to 'Send failed (503)'", async () => {
    const hook = setup();
    responses.push({ status: 503, body: {} });

    act(() => hook.result.current.onSend());
    await waitFor(() =>
      expect(hook.result.current.error).toBe("Send failed (503)"),
    );
    expect(hook.result.current.error).not.toMatch(/approval is saved/);
  });

  it("onConfirmTyped: a gateway 503 falls through to 'Send failed (503)'", async () => {
    const hook = setup();
    await openConfirm(hook);
    responses.push({ status: 503, body: {} });

    act(() => hook.result.current.onConfirmTyped(true, "SEND"));
    await waitFor(() =>
      expect(hook.result.current.error).toBe("Send failed (503)"),
    );
  });
});

describe("in-flight guard (#10543, CTO Q7)", () => {
  it("a double onSend in one tick makes ONE fetch", async () => {
    const hook = setup();
    responses.push({ status: 200, body: {} });

    act(() => {
      hook.result.current.onSend();
      hook.result.current.onSend();
    });
    await waitFor(() => expect(hook.result.current.acknowledged).toBe(true));
    expect(globalThis.fetch as ReturnType<typeof vi.fn>).toHaveBeenCalledTimes(
      1,
    );
  });

  it("the guard releases after a 503, so the next click sends again", async () => {
    const hook = setup();
    responses.push({
      status: 503,
      body: { error: "enqueue_unavailable", retryable: true },
    });
    act(() => hook.result.current.onSend());
    await waitFor(() => expect(hook.result.current.error).toBe(COPY_503));

    responses.push({ status: 200, body: {} });
    act(() => hook.result.current.onSend());
    await waitFor(() => expect(hook.result.current.acknowledged).toBe(true));
    expect(globalThis.fetch as ReturnType<typeof vi.fn>).toHaveBeenCalledTimes(
      2,
    );
  });

  it("the guard releases after a thrown fetch", async () => {
    const hook = setup();
    (globalThis.fetch as ReturnType<typeof vi.fn>).mockRejectedValueOnce(
      new Error("network down"),
    );
    act(() => hook.result.current.onSend());
    await waitFor(() =>
      expect(hook.result.current.error).toBe("Send failed — network error"),
    );

    responses.push({ status: 200, body: {} });
    act(() => hook.result.current.onSend());
    await waitFor(() => expect(hook.result.current.acknowledged).toBe(true));
  });

  it("onConfirmTyped is guarded the same way: a double submit makes ONE confirm fetch", async () => {
    const hook = setup();
    await openConfirm(hook);
    const before = (globalThis.fetch as ReturnType<typeof vi.fn>).mock.calls
      .length;
    responses.push({ status: 200, body: {} });

    act(() => {
      hook.result.current.onConfirmTyped(true, "SEND");
      hook.result.current.onConfirmTyped(true, "SEND");
    });
    await waitFor(() => expect(hook.result.current.acknowledged).toBe(true));
    expect(
      (globalThis.fetch as ReturnType<typeof vi.fn>).mock.calls.length - before,
    ).toBe(1);
  });

  it("onConfirmTyped releases the guard after a 503: the next typed submit sends again and acknowledges", async () => {
    const hook = setup();
    await openConfirm(hook);
    const before = (globalThis.fetch as ReturnType<typeof vi.fn>).mock.calls
      .length;

    responses.push({
      status: 503,
      body: { error: "enqueue_unavailable", retryable: true },
    });
    act(() => hook.result.current.onConfirmTyped(true, "SEND"));
    await waitFor(() => expect(hook.result.current.error).toBe(COPY_503));
    expect(hook.result.current.confirming).not.toBeNull();

    responses.push({ status: 200, body: {} });
    act(() => hook.result.current.onConfirmTyped(true, "SEND"));
    await waitFor(() => expect(hook.result.current.acknowledged).toBe(true));
    expect(
      (globalThis.fetch as ReturnType<typeof vi.fn>).mock.calls.length - before,
    ).toBe(2);
  });
});
