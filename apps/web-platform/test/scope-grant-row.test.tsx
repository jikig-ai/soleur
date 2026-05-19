import { describe, test, expect, vi, beforeEach } from "vitest";
import {
  render,
  screen,
  fireEvent,
  waitFor,
} from "@testing-library/react";

// vi.hoisted is required: vi.mock is hoisted above all imports, so a bare
// top-level `const refresh = vi.fn()` would still be undefined inside the
// mock factory at hoist time. Precedent: api-usage-retry-button.test.tsx:4.
const { mockRefresh } = vi.hoisted(() => ({ mockRefresh: vi.fn() }));

vi.mock("next/navigation", () => ({
  useRouter: () => ({ refresh: mockRefresh, push: vi.fn() }),
}));

import { ScopeGrantRow } from "@/components/scope-grants/scope-grant-row";

describe("ScopeGrantRow — router.refresh after Authorize/Revoke (#4048)", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    global.fetch = vi.fn();
  });

  test("FR1: Authorize success → mockRefresh called exactly once", async () => {
    (global.fetch as ReturnType<typeof vi.fn>).mockResolvedValueOnce({
      ok: true,
      status: 200,
      json: async () => ({
        id: "g1",
        action_class: "finance.payment_failed",
        tier: "draft_one_click",
      }),
    });
    render(
      <ScopeGrantRow
        actionClass="finance.payment_failed"
        currentTier={null}
        grantedAt={null}
      />,
    );
    fireEvent.click(screen.getByRole("radio", { name: /draft, one click/i }));
    fireEvent.click(screen.getByRole("button", { name: /authorize/i }));
    await waitFor(() => expect(mockRefresh).toHaveBeenCalledTimes(1));
    // Note: the headline status string only flips after the server
    // re-renders. In tests, router.refresh is a no-op vi.fn() — the server
    // prop grantedAt remains null, so the headline still shows
    // "Not authorized". FR1 asserts the *trigger* (refresh called); the
    // post-refresh server render lives in the QA Playwright layer.
  });

  test("FR2: Revoke success → mockRefresh called exactly once", async () => {
    (global.fetch as ReturnType<typeof vi.fn>).mockResolvedValueOnce({
      ok: true,
      status: 200,
      json: async () => ({}),
    });
    render(
      <ScopeGrantRow
        actionClass="finance.payment_failed"
        currentTier="draft_one_click"
        grantedAt="2026-05-19T00:00:00Z"
      />,
    );
    fireEvent.click(screen.getByRole("button", { name: /revoke/i }));
    await waitFor(() => expect(mockRefresh).toHaveBeenCalledTimes(1));
  });

  test("FR3: Update tier success → mockRefresh called exactly once", async () => {
    (global.fetch as ReturnType<typeof vi.fn>).mockResolvedValueOnce({
      ok: true,
      status: 200,
      json: async () => ({
        id: "g2",
        action_class: "finance.payment_failed",
        tier: "approve_every_time",
      }),
    });
    render(
      <ScopeGrantRow
        actionClass="finance.payment_failed"
        currentTier="draft_one_click"
        grantedAt="2026-05-19T00:00:00Z"
      />,
    );
    fireEvent.click(
      screen.getByRole("radio", { name: /approve every time/i }),
    );
    fireEvent.click(screen.getByRole("button", { name: /update/i }));
    await waitFor(() => expect(mockRefresh).toHaveBeenCalledTimes(1));
  });

  test("FR4: Authorize failure → mockRefresh NOT called (pessimistic-UI invariant)", async () => {
    (global.fetch as ReturnType<typeof vi.fn>).mockResolvedValueOnce({
      ok: false,
      status: 500,
      json: async () => ({}),
    });
    render(
      <ScopeGrantRow
        actionClass="finance.payment_failed"
        currentTier={null}
        grantedAt={null}
      />,
    );
    fireEvent.click(screen.getByRole("radio", { name: /draft, one click/i }));
    fireEvent.click(screen.getByRole("button", { name: /authorize/i }));
    await waitFor(() =>
      expect(screen.getByRole("alert")).toHaveTextContent(
        /Failed to save \(500\)/,
      ),
    );
    expect(mockRefresh).not.toHaveBeenCalled();
  });

  test("FR6: Authorize network error (catch branch) → mockRefresh NOT called, pessimistic revert", async () => {
    (global.fetch as ReturnType<typeof vi.fn>).mockRejectedValueOnce(
      new Error("network down"),
    );
    render(
      <ScopeGrantRow
        actionClass="finance.payment_failed"
        currentTier={null}
        grantedAt={null}
      />,
    );
    fireEvent.click(screen.getByRole("radio", { name: /draft, one click/i }));
    fireEvent.click(screen.getByRole("button", { name: /authorize/i }));
    await waitFor(() =>
      expect(screen.getByRole("alert")).toHaveTextContent(/network down/),
    );
    expect(mockRefresh).not.toHaveBeenCalled();
  });

  test("FR7: Revoke failure (non-2xx) → mockRefresh NOT called", async () => {
    (global.fetch as ReturnType<typeof vi.fn>).mockResolvedValueOnce({
      ok: false,
      status: 500,
      json: async () => ({}),
    });
    render(
      <ScopeGrantRow
        actionClass="finance.payment_failed"
        currentTier="draft_one_click"
        grantedAt="2026-05-19T00:00:00Z"
      />,
    );
    fireEvent.click(screen.getByRole("button", { name: /revoke/i }));
    await waitFor(() =>
      expect(screen.getByRole("alert")).toHaveTextContent(
        /Failed to revoke \(500\)/,
      ),
    );
    expect(mockRefresh).not.toHaveBeenCalled();
  });

  test("FR5 (regression): auto-tier without ack keeps Authorize disabled; ack enables it", () => {
    render(
      <ScopeGrantRow
        actionClass="finance.payment_failed"
        currentTier={null}
        grantedAt={null}
      />,
    );
    fireEvent.click(screen.getByRole("radio", { name: /^auto/i }));
    expect(
      screen.getByRole("button", { name: /authorize/i }),
    ).toBeDisabled();
    fireEvent.click(screen.getByRole("checkbox"));
    expect(
      screen.getByRole("button", { name: /authorize/i }),
    ).toBeEnabled();
  });
});
