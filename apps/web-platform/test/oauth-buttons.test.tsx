import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";

const { searchParamsRef } = vi.hoisted(() => ({
  searchParamsRef: { current: new URLSearchParams() },
}));

vi.mock("next/navigation", () => ({
  useSearchParams: () => searchParamsRef.current,
}));

const mockSignInWithOAuth = vi.fn().mockResolvedValue({ error: null });

vi.mock("@/lib/supabase/client", () => ({
  createClient: () => ({
    auth: {
      signInWithOAuth: mockSignInWithOAuth,
    },
  }),
}));

import { OAuthButtons } from "@/components/auth/oauth-buttons";

describe("OAuthButtons", () => {
  beforeEach(() => {
    mockSignInWithOAuth.mockClear();
    searchParamsRef.current = new URLSearchParams();
  });

  it("renders buttons for all four providers", () => {
    render(<OAuthButtons />);
    expect(screen.getByRole("button", { name: /google/i })).toBeInTheDocument();
    expect(screen.getByRole("button", { name: /apple/i })).toBeInTheDocument();
    expect(screen.getByRole("button", { name: /github/i })).toBeInTheDocument();
    expect(screen.getByRole("button", { name: /microsoft/i })).toBeInTheDocument();
  });

  it("calls signInWithOAuth with google provider", async () => {
    render(<OAuthButtons />);
    await userEvent.click(screen.getByRole("button", { name: /google/i }));
    expect(mockSignInWithOAuth).toHaveBeenCalledWith({
      provider: "google",
      options: { redirectTo: expect.stringContaining("/callback") },
    });
  });

  it("calls signInWithOAuth with apple provider", async () => {
    render(<OAuthButtons />);
    await userEvent.click(screen.getByRole("button", { name: /apple/i }));
    expect(mockSignInWithOAuth).toHaveBeenCalledWith({
      provider: "apple",
      options: { redirectTo: expect.stringContaining("/callback") },
    });
  });

  it("calls signInWithOAuth with github provider", async () => {
    render(<OAuthButtons />);
    await userEvent.click(screen.getByRole("button", { name: /github/i }));
    expect(mockSignInWithOAuth).toHaveBeenCalledWith({
      provider: "github",
      options: { redirectTo: expect.stringContaining("/callback") },
    });
  });

  it("calls signInWithOAuth with azure provider for Microsoft", async () => {
    render(<OAuthButtons />);
    await userEvent.click(screen.getByRole("button", { name: /microsoft/i }));
    expect(mockSignInWithOAuth).toHaveBeenCalledWith({
      provider: "azure",
      options: {
        redirectTo: expect.stringContaining("/callback"),
        scopes: "email profile openid",
      },
    });
  });

  it("displays error message when OAuth fails", async () => {
    mockSignInWithOAuth.mockResolvedValueOnce({
      error: { message: "Provider not configured" },
    });
    render(<OAuthButtons />);
    await userEvent.click(screen.getByRole("button", { name: /google/i }));
    expect(screen.getByText("Something went wrong. Please try again.")).toBeInTheDocument();
  });

  it("disables all buttons while loading", async () => {
    // Make signInWithOAuth hang to keep loading state
    mockSignInWithOAuth.mockReturnValueOnce(new Promise(() => {}));
    render(<OAuthButtons />);
    await userEvent.click(screen.getByRole("button", { name: /google/i }));

    expect(screen.getByRole("button", { name: /google/i })).toBeDisabled();
    expect(screen.getByRole("button", { name: /apple/i })).toBeDisabled();
    expect(screen.getByRole("button", { name: /github/i })).toBeDisabled();
    expect(screen.getByRole("button", { name: /microsoft/i })).toBeDisabled();
  });

  it("disables all buttons when disabled prop is true", () => {
    render(<OAuthButtons disabled />);
    expect(screen.getByRole("button", { name: /google/i })).toBeDisabled();
    expect(screen.getByRole("button", { name: /apple/i })).toBeDisabled();
    expect(screen.getByRole("button", { name: /github/i })).toBeDisabled();
    expect(screen.getByRole("button", { name: /microsoft/i })).toBeDisabled();
  });

  it("threads a validated redirectTo through /callback as an encoded next param", async () => {
    searchParamsRef.current = new URLSearchParams("redirectTo=/invite/tok123");
    render(<OAuthButtons />);
    await userEvent.click(screen.getByRole("button", { name: /google/i }));
    expect(mockSignInWithOAuth).toHaveBeenCalledWith({
      provider: "google",
      options: {
        redirectTo: expect.stringContaining(
          `/callback?next=${encodeURIComponent("/invite/tok123")}`,
        ),
      },
    });
  });

  it("does NOT append a next param for a rejected open-redirect redirectTo", async () => {
    searchParamsRef.current = new URLSearchParams(
      "redirectTo=https://evil.example",
    );
    render(<OAuthButtons />);
    await userEvent.click(screen.getByRole("button", { name: /google/i }));
    const call = mockSignInWithOAuth.mock.calls[0][0];
    expect(call.options.redirectTo).not.toContain("next=");
    expect(call.options.redirectTo).toContain("/callback");
  });
});
