import { describe, test, expect, vi, beforeEach } from "vitest";
import { render, screen, fireEvent, waitFor } from "@testing-library/react";

vi.mock("next/font/google", () => ({
  Inter: () => ({ className: "mock-sans", variable: "--font-inter" }),
}));

const { mockRpc, mockRefreshSession, mockReportSilentFallback } = vi.hoisted(
  () => ({
    mockRpc: vi.fn(),
    mockRefreshSession: vi.fn(),
    mockReportSilentFallback: vi.fn(),
  }),
);

vi.mock("@/lib/supabase/client", () => ({
  createClient: () => ({
    rpc: mockRpc,
    auth: { refreshSession: mockRefreshSession },
  }),
}));

vi.mock("@/lib/client-observability", () => ({
  reportSilentFallback: (...a: unknown[]) => mockReportSilentFallback(...a),
}));

import { FailedState } from "@/components/connect-repo/failed-state";

describe("<FailedState> code-mapped copy", () => {
  test("REPO_ACCESS_REVOKED renders reinstall copy + CTA", () => {
    render(
      <FailedState
        onRetry={() => {}}
        errorCode="REPO_ACCESS_REVOKED"
        errorMessage="fatal: access revoked"
      />,
    );
    expect(
      screen.getAllByText(/no longer has access/i).length,
    ).toBeGreaterThanOrEqual(1);
    expect(
      screen.getByRole("button", { name: /reinstall/i }),
    ).toBeInTheDocument();
  });

  test("REPO_NOT_FOUND renders 'Repository not found' + choose-different CTA", () => {
    render(
      <FailedState
        onRetry={() => {}}
        errorCode="REPO_NOT_FOUND"
        errorMessage="fatal: not found"
      />,
    );
    expect(screen.getByText(/repository not found/i)).toBeInTheDocument();
    expect(
      screen.getByRole("button", { name: /choose a different/i }),
    ).toBeInTheDocument();
  });

  test("CLONE_TIMEOUT renders timeout copy + retry CTA", () => {
    render(
      <FailedState
        onRetry={() => {}}
        errorCode="CLONE_TIMEOUT"
        errorMessage="timeout exceeded"
      />,
    );
    expect(screen.getByText(/timed out/i)).toBeInTheDocument();
  });

  test("AUTH_FAILED renders authentication-failed copy + reinstall CTA", () => {
    render(
      <FailedState
        onRetry={() => {}}
        errorCode="AUTH_FAILED"
        errorMessage="fatal: could not read Username"
      />,
    );
    expect(screen.getByText(/authentication failed/i)).toBeInTheDocument();
    expect(
      screen.getByRole("button", { name: /reinstall/i }),
    ).toBeInTheDocument();
  });

  test("legacy row (errorCode undefined) renders generic 'Project Setup Failed'", () => {
    render(
      <FailedState
        onRetry={() => {}}
        errorMessage="some old raw stderr from an older deploy"
      />,
    );
    expect(screen.getByText(/project setup failed/i)).toBeInTheDocument();
  });

  test("raw errorMessage is wrapped in <details> collapsed by default", () => {
    const { container } = render(
      <FailedState
        onRetry={() => {}}
        errorCode="CLONE_UNKNOWN"
        errorMessage="fatal: raw git stderr"
      />,
    );
    const details = container.querySelector("details");
    expect(details).not.toBeNull();
    expect(details!.hasAttribute("open")).toBe(false);
    expect(details!.textContent).toContain("fatal: raw git stderr");
  });

  test("Try Again button invokes onRetry", () => {
    const onRetry = vi.fn();
    render(
      <FailedState
        onRetry={onRetry}
        errorCode="CLONE_UNKNOWN"
        errorMessage="boom"
      />,
    );
    fireEvent.click(screen.getByRole("button", { name: /try again/i }));
    expect(onRetry).toHaveBeenCalledTimes(1);
  });
});

// feat-repo-connect-block-offer-join — connect-time block states reuse FailedState.
describe("<FailedState> connect-time block states", () => {
  const assignMock = vi.fn();
  const OWN_WS = "11111111-1111-1111-1111-111111111111";

  beforeEach(() => {
    vi.clearAllMocks();
    mockRpc.mockResolvedValue({ error: null });
    mockRefreshSession.mockResolvedValue({ data: { session: null }, error: null });
    Object.defineProperty(window.location, "assign", {
      configurable: true,
      value: assignMock,
    });
  });

  test("STATE 2 decline (repo_connect_blocked): generic, non-disclosing copy + choose CTA", () => {
    render(
      <FailedState onRetry={() => {}} errorCode="repo_connect_blocked" />,
    );
    expect(
      screen.getByText(/this repository can't be connected/i),
    ).toBeInTheDocument();
    // Non-disclosing forward CTA: "ask … owner … invite", never "taken"/another user.
    const body = document.body.textContent ?? "";
    expect(body).toMatch(/ask/i);
    expect(body).toMatch(/invite/i);
    expect(body).not.toMatch(/taken|already connected|another (user|workspace)|someone else/i);
    expect(
      screen.getByRole("button", { name: /pick a different repository|different repository/i }),
    ).toBeInTheDocument();
  });

  test("STATE 2 decline: primary CTA returns the user to repo choice (onRetry)", () => {
    const onRetry = vi.fn();
    render(<FailedState onRetry={onRetry} errorCode="repo_connect_blocked" />);
    fireEvent.click(
      screen.getByRole("button", { name: /different repository/i }),
    );
    expect(onRetry).toHaveBeenCalledTimes(1);
  });

  test("STATE 1 switch (workspace_switch_required): switch CTA → RPC + refresh + hard nav", async () => {
    render(
      <FailedState
        onRetry={() => {}}
        errorCode="workspace_switch_required"
        existingWorkspaceId={OWN_WS}
      />,
    );
    const btn = screen.getByRole("button", { name: /switch to that workspace|switch/i });
    fireEvent.click(btn);
    await waitFor(() => expect(mockRpc).toHaveBeenCalledTimes(1));
    expect(mockRpc).toHaveBeenCalledWith("set_current_workspace_id", {
      p_workspace_id: OWN_WS,
    });
    await waitFor(() => expect(assignMock).toHaveBeenCalledWith("/dashboard"));
    expect(mockRefreshSession).toHaveBeenCalled();
    // Load-bearing ORDER (ADR-044 Decision.3 + org-switcher two-phase commit):
    // RPC (durable write) → refreshSession (JWT re-mint) → hard nav. Asserting the
    // calls happened is not enough — assign-before-refresh would land on the stale
    // prior-workspace claim and still pass a count-only check.
    expect(mockRpc.mock.invocationCallOrder[0]).toBeLessThan(
      mockRefreshSession.mock.invocationCallOrder[0],
    );
    expect(mockRefreshSession.mock.invocationCallOrder[0]).toBeLessThan(
      assignMock.mock.invocationCallOrder[0],
    );
  });

  test("STATE 1 switch: refreshSession throw converges forward (still navigates) AND mirrors to Sentry", async () => {
    // The RPC has committed the durable pointer; a refresh failure must not strand
    // the user, so we converge forward via hard nav — but the post-commit divergence
    // must be observable (cq-silent-fallback-must-mirror-to-sentry).
    mockRefreshSession.mockRejectedValue(new Error("network blip"));
    render(
      <FailedState
        onRetry={() => {}}
        errorCode="workspace_switch_required"
        existingWorkspaceId={OWN_WS}
      />,
    );
    fireEvent.click(screen.getByRole("button", { name: /switch/i }));
    await waitFor(() => expect(assignMock).toHaveBeenCalledWith("/dashboard"));
    expect(mockReportSilentFallback).toHaveBeenCalledTimes(1);
    expect(mockReportSilentFallback.mock.calls[0][1]).toMatchObject({
      op: "refresh-session-post-rpc",
    });
  });

  test("STATE 1 switch: RPC failure (revoked/deleted) falls back to onRetry, no nav", async () => {
    mockRpc.mockResolvedValue({ error: { message: "not a member" } });
    const onRetry = vi.fn();
    render(
      <FailedState
        onRetry={onRetry}
        errorCode="workspace_switch_required"
        existingWorkspaceId={OWN_WS}
      />,
    );
    fireEvent.click(screen.getByRole("button", { name: /switch/i }));
    await waitFor(() => expect(onRetry).toHaveBeenCalledTimes(1));
    expect(assignMock).not.toHaveBeenCalled();
  });
});
