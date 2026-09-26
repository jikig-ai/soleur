import { describe, it, expect, beforeEach, vi } from "vitest";
import { render, fireEvent, screen } from "@testing-library/react";
import React from "react";

type CapturedOnNavigate = ((event: { preventDefault: () => void }) => void) | undefined;

// Stand-in Link: renders a real anchor, forwards every prop, and fires the
// Next `onNavigate` contract on click (SPA same-origin navigations only).
vi.mock("next/link", () => ({
  __esModule: true,
  default: ({
    onNavigate,
    children,
    href,
    prefetch: _prefetch,
    ...rest
  }: {
    onNavigate?: CapturedOnNavigate;
    children?: React.ReactNode;
    href: unknown;
    prefetch?: unknown;
    [key: string]: unknown;
  }) => (
    <a
      href={typeof href === "string" ? href : "#mock-url-object"}
      {...rest}
      onClick={(e) => {
        e.preventDefault();
        onNavigate?.({ preventDefault: () => {} });
      }}
    >
      {children}
    </a>
  ),
}));

vi.mock("@/lib/nav-pending-store", () => ({
  startNavPending: vi.fn(),
  isSameDocTarget: vi.fn(() => false),
}));

import { isSameDocTarget, startNavPending } from "@/lib/nav-pending-store";
import { NavLink } from "@/components/ui/nav-link";

// feat-ui-action-feedback Layer 2 trigger (a): NavLink fires start() on
// navigation unless the href resolves to the current document (active-rail
// re-click would strand the bar — kieran #2), and forwards a caller's
// onNavigate plus every other Link/anchor prop.

describe("NavLink", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    vi.mocked(isSameDocTarget).mockReturnValue(false);
  });

  it("starts the pending episode on navigate to a different doc", () => {
    render(<NavLink href="/inbox">Inbox</NavLink>);
    fireEvent.click(screen.getByRole("link", { name: "Inbox" }));
    expect(isSameDocTarget).toHaveBeenCalledWith("/inbox");
    expect(startNavPending).toHaveBeenCalledTimes(1);
    expect(startNavPending).toHaveBeenCalledWith("link");
  });

  it("never starts on a same-doc target (hash-only / active-rail re-click)", () => {
    vi.mocked(isSameDocTarget).mockReturnValue(true);
    render(<NavLink href="/inbox">Inbox</NavLink>);
    fireEvent.click(screen.getByRole("link", { name: "Inbox" }));
    expect(startNavPending).not.toHaveBeenCalled();
  });

  it("forwards a caller-supplied onNavigate", () => {
    const callerOnNavigate = vi.fn();
    render(
      <NavLink href="/inbox" onNavigate={callerOnNavigate}>
        Inbox
      </NavLink>,
    );
    fireEvent.click(screen.getByRole("link", { name: "Inbox" }));
    expect(callerOnNavigate).toHaveBeenCalledTimes(1);
    expect(callerOnNavigate).toHaveBeenCalledWith(
      expect.objectContaining({ preventDefault: expect.any(Function) }),
    );
    expect(startNavPending).toHaveBeenCalledWith("link");
  });

  it("passes Link/anchor props through untouched", () => {
    render(
      <NavLink
        href="/kb"
        className="rail-item"
        data-testid="nav-kb"
        data-tour-id="kb-rail"
        aria-current="page"
        prefetch={false}
      >
        KB
      </NavLink>,
    );
    const anchor = screen.getByTestId("nav-kb");
    expect(anchor).toHaveAttribute("href", "/kb");
    expect(anchor).toHaveAttribute("aria-current", "page");
    expect(anchor).toHaveAttribute("data-tour-id", "kb-rail");
    expect(anchor).toHaveClass("rail-item");
    expect(anchor).toHaveTextContent("KB");
  });
});
