// feat-ui-action-feedback — typed-confirm pending contract (brief §4).
//
// Asserts the modal-stays-open send flow wired through useActionSend's
// `confirmPending` + `error`:
//   - Modal stays MOUNTED while the confirm POST is in flight (was: it
//     closed before the POST — the highest-stakes feedback gap)
//   - Cancel / Esc / form submit are all inert while pending (ResponsiveModal
//     keys every dismiss vector off `onClose` presence → onClose=undefined)
//   - Locked input + "Sending…" status + focus moves to the status element
//   - Enter during pending does NOT re-invoke onConfirm (canSubmit stays
//     true while the input is disabled — the pending guard is load-bearing)
//   - Failure re-enables controls, focuses the in-modal role="alert", and
//     preserves the typed SEND value (no re-typing)
//   - Success / 409 already_sent close the modal via the acknowledged path

import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen, fireEvent, waitFor, act, cleanup } from "@testing-library/react";

import { TypedConfirmModal } from "@/components/ui/typed-confirm-modal";
import { useActionSend } from "@/hooks/use-action-send";
import { reportSilentFallback } from "@/lib/client-observability";

vi.mock("@/lib/client-observability", () => ({
  reportSilentFallback: vi.fn(),
}));

const BASE_PROPS = {
  open: true,
  recipientExcerpt: "customer@example.com",
  contentExcerpt: "Hi — your invoice for May renewed...",
  actionClassLabel: "finance.payment_failed",
  tierLabel: "Approve every time",
};

const CONFIRM_REQUIRED = {
  error: "requires_confirmation",
  action_class: "finance.payment_failed",
  tier: "approve_every_time",
  recipient_excerpt: "customer@example.com",
  content_excerpt: "Hi — your invoice for May renewed...",
  expected_draft_preview_hash: "hash-1",
  message_id: "msg-1",
};

function resp(status: number, body: unknown = {}): Response {
  return {
    status,
    ok: status >= 200 && status < 300,
    json: () => Promise.resolve(body),
  } as Response;
}

function deferred<T>() {
  let resolve!: (value: T) => void;
  const promise = new Promise<T>((res) => {
    resolve = res;
  });
  return { promise, resolve };
}

describe("TypedConfirmModal — pending render", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("keeps the dialog mounted and shows Sending… while pending", () => {
    render(
      <TypedConfirmModal
        {...BASE_PROPS}
        pending
        onCancel={vi.fn()}
        onConfirm={vi.fn()}
      />,
    );

    expect(screen.getByRole("dialog")).toBeInTheDocument();
    expect(screen.getByTestId("typed-confirm-submit")).toHaveTextContent(
      "Sending…",
    );
    expect(screen.getByTestId("typed-confirm-status")).toHaveTextContent(
      "Sending…",
    );
    expect(screen.getByTestId("typed-confirm-submit")).toHaveAttribute(
      "aria-busy",
      "true",
    );
  });

  it("locks the input, disables Cancel, and shows the lock note while pending", () => {
    render(
      <TypedConfirmModal
        {...BASE_PROPS}
        pending
        onCancel={vi.fn()}
        onConfirm={vi.fn()}
      />,
    );

    expect(screen.getByTestId("typed-confirm-input")).toBeDisabled();
    expect(screen.getByTestId("typed-confirm-cancel")).toBeDisabled();
    expect(
      screen.getByText(/input locked while request in flight/i),
    ).toBeInTheDocument();
  });

  it("suppresses Esc, Cancel click, and backdrop-free dismiss while pending", () => {
    const onCancel = vi.fn();
    render(
      <TypedConfirmModal
        {...BASE_PROPS}
        pending
        onCancel={onCancel}
        onConfirm={vi.fn()}
      />,
    );

    fireEvent.keyDown(window, { key: "Escape" });
    fireEvent.click(screen.getByTestId("typed-confirm-cancel"));
    expect(onCancel).not.toHaveBeenCalled();
    expect(screen.getByRole("dialog")).toBeInTheDocument();
  });

  it("Enter during pending does NOT re-invoke onConfirm (canSubmit stays true)", () => {
    const onConfirm = vi.fn();
    const onCancel = vi.fn();
    const { rerender } = render(
      <TypedConfirmModal
        {...BASE_PROPS}
        onCancel={onCancel}
        onConfirm={onConfirm}
      />,
    );
    fireEvent.change(screen.getByTestId("typed-confirm-input"), {
      target: { value: "SEND" },
    });

    rerender(
      <TypedConfirmModal
        {...BASE_PROPS}
        pending
        onCancel={onCancel}
        onConfirm={onConfirm}
      />,
    );

    // Input is disabled but `value === "SEND"` keeps canSubmit true — only
    // the `!pending` guard in handleSubmit blocks the Enter-path submit.
    const form = screen.getByRole("dialog").querySelector("form");
    expect(form).not.toBeNull();
    fireEvent.submit(form!);
    fireEvent.click(screen.getByTestId("typed-confirm-submit"));
    expect(onConfirm).not.toHaveBeenCalled();
  });
});

describe("useActionSend + TypedConfirmModal — pending episode", () => {
  const fetchMock = vi.fn();

  function SendHarness() {
    const {
      onSend,
      error,
      acknowledged,
      confirming,
      confirmPending,
      onConfirmTyped,
      onCancelConfirm,
    } = useActionSend({ messageId: "msg-1" });
    return (
      <div>
        <button type="button" onClick={onSend}>
          Send
        </button>
        {acknowledged ? <p>Acknowledged</p> : null}
        <TypedConfirmModal
          open={confirming !== null}
          pending={confirmPending}
          error={confirming !== null ? error : null}
          recipientExcerpt={confirming?.recipientExcerpt ?? ""}
          contentExcerpt={confirming?.contentExcerpt ?? ""}
          actionClassLabel={confirming?.actionClass ?? ""}
          tierLabel={confirming?.tier ?? ""}
          onCancel={onCancelConfirm}
          onConfirm={onConfirmTyped}
        />
      </div>
    );
  }

  beforeEach(() => {
    vi.stubGlobal("fetch", fetchMock);
    fetchMock.mockReset();
  });

  afterEach(() => {
    cleanup();
    vi.unstubAllGlobals();
  });

  async function openConfirmAndType() {
    fetchMock.mockResolvedValueOnce(resp(409, CONFIRM_REQUIRED));
    render(<SendHarness />);
    fireEvent.click(screen.getByRole("button", { name: "Send" }));
    await screen.findByRole("dialog");
    // Flush the modal's mount effect — it setValue("")s on open and can land
    // AFTER findByRole resolves, racing the typing below into a reset.
    await act(async () => {});
    fireEvent.change(screen.getByTestId("typed-confirm-input"), {
      target: { value: "SEND" },
    });
  }

  it("keeps the modal mounted with Sending… for the whole flight, then closes on 200", async () => {
    await openConfirmAndType();
    const flight = deferred<Response>();
    fetchMock.mockReturnValueOnce(flight.promise);

    fireEvent.click(screen.getByTestId("typed-confirm-submit"));

    // In-flight: dialog mounted, status focused + announcing, controls inert.
    await waitFor(() =>
      expect(screen.getByTestId("typed-confirm-submit")).toHaveTextContent(
        "Sending…",
      ),
    );
    expect(screen.getByRole("dialog")).toBeInTheDocument();
    expect(screen.getByTestId("typed-confirm-input")).toBeDisabled();
    expect(screen.getByTestId("typed-confirm-cancel")).toBeDisabled();
    expect(document.activeElement).toBe(
      screen.getByTestId("typed-confirm-status"),
    );
    fireEvent.keyDown(window, { key: "Escape" });
    expect(screen.getByRole("dialog")).toBeInTheDocument();
    expect(fetchMock).toHaveBeenCalledTimes(2);

    // Success: modal closes via the acknowledged path.
    await act(async () => {
      flight.resolve(resp(200, {}));
    });
    await screen.findByText("Acknowledged");
    expect(screen.queryByRole("dialog")).not.toBeInTheDocument();
  });

  it("on failure: stays open, re-enables, focuses role=alert, SEND persists", async () => {
    await openConfirmAndType();
    const flight = deferred<Response>();
    fetchMock.mockReturnValueOnce(flight.promise);
    fireEvent.click(screen.getByTestId("typed-confirm-submit"));
    await waitFor(() =>
      expect(screen.getByTestId("typed-confirm-submit")).toHaveTextContent(
        "Sending…",
      ),
    );

    await act(async () => {
      flight.resolve(resp(500, {}));
    });

    const alert = await screen.findByRole("alert");
    expect(alert).toHaveTextContent("Send failed (500)");
    expect(document.activeElement).toBe(alert);
    expect(screen.getByRole("dialog")).toBeInTheDocument();
    expect(
      (screen.getByTestId("typed-confirm-input") as HTMLInputElement).value,
    ).toBe("SEND");
    expect(screen.getByTestId("typed-confirm-input")).not.toBeDisabled();
    expect(screen.getByTestId("typed-confirm-submit")).not.toBeDisabled();
    expect(screen.getByTestId("typed-confirm-cancel")).not.toBeDisabled();
  });

  it("on 409 draft-changed: in-modal alert, modal stays open, retry re-arms pending", async () => {
    await openConfirmAndType();
    const first = deferred<Response>();
    fetchMock.mockReturnValueOnce(first.promise);
    fireEvent.click(screen.getByTestId("typed-confirm-submit"));
    await waitFor(() =>
      expect(screen.getByTestId("typed-confirm-submit")).toHaveTextContent(
        "Sending…",
      ),
    );
    await act(async () => {
      first.resolve(resp(409, { error: "hash_mismatch" }));
    });

    const alert = await screen.findByRole("alert");
    expect(alert).toHaveTextContent(
      "Draft changed since you confirmed — please re-send.",
    );
    expect(screen.getByRole("dialog")).toBeInTheDocument();

    // Retry from the same open modal: fresh pending episode, same fetch body.
    const second = deferred<Response>();
    fetchMock.mockReturnValueOnce(second.promise);
    fireEvent.click(screen.getByTestId("typed-confirm-submit"));
    await waitFor(() =>
      expect(screen.getByTestId("typed-confirm-submit")).toHaveTextContent(
        "Sending…",
      ),
    );
    expect(fetchMock).toHaveBeenCalledTimes(3);
    const body = JSON.parse(
      (fetchMock.mock.calls[2][1] as RequestInit).body as string,
    );
    expect(body.expected_draft_preview_hash).toBe("hash-1");
    expect(body.typed_value).toBe("SEND");
    await act(async () => {
      second.resolve(resp(200, {}));
    });
    await screen.findByText("Acknowledged");
  });

  it("a hung send POST terminates into a timeout error + Sentry mirror, dismiss vectors live again", async () => {
    // The AbortSignal.timeout in postSend is the ONLY mechanism that ends a
    // truly-hung episode — deleting it would previously have passed green.
    await openConfirmAndType();
    fetchMock.mockRejectedValueOnce(
      new DOMException("The operation timed out.", "TimeoutError"),
    );

    fireEvent.click(screen.getByTestId("typed-confirm-submit"));

    // Termination: in-modal timeout error announced, controls live again
    // (the transition's isPending clears a tick after the alert paints).
    await screen.findByRole("alert");
    expect(screen.getByRole("alert")).toHaveTextContent(/timed out/i);
    expect(screen.getByRole("dialog")).toBeInTheDocument();
    await waitFor(() => {
      expect(screen.getByTestId("typed-confirm-cancel")).not.toBeDisabled();
      expect(screen.getByTestId("typed-confirm-submit")).not.toBeDisabled();
    });
    // Sentry mirror under the timeout op.
    expect(vi.mocked(reportSilentFallback)).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({ op: "action-send-timeout" }),
    );
  });

  it("a network rejection terminates into the generic send error", async () => {
    await openConfirmAndType();
    fetchMock.mockRejectedValueOnce(new Error("fetch failed"));

    fireEvent.click(screen.getByTestId("typed-confirm-submit"));

    await screen.findByRole("alert");
    expect(screen.getByRole("alert")).toHaveTextContent(/network error/i);
    expect(screen.getByRole("dialog")).toBeInTheDocument();
  });

  it("409 already_sent resolves to acknowledged with no error surface", async () => {
    await openConfirmAndType();
    const flight = deferred<Response>();
    fetchMock.mockReturnValueOnce(flight.promise);
    fireEvent.click(screen.getByTestId("typed-confirm-submit"));
    await act(async () => {
      flight.resolve(resp(409, { error: "already_sent" }));
    });

    await screen.findByText("Acknowledged");
    expect(screen.queryByRole("dialog")).not.toBeInTheDocument();
    expect(screen.queryByRole("alert")).not.toBeInTheDocument();
  });
});
