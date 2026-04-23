import { describe, test, expect, vi } from "vitest";
import { render, screen, fireEvent } from "@testing-library/react";

vi.mock("next/font/google", () => ({
  Cormorant_Garamond: () => ({
    className: "mock-serif",
    variable: "--font-serif",
  }),
  Inter: () => ({ className: "mock-sans", variable: "--font-sans" }),
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
