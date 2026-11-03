import { describe, it, expect, vi, afterEach } from "vitest";
import { render, screen, cleanup } from "@testing-library/react";

// The post-delete screen is the only pending-state copy a deleted user actually reads. It is an
// async server component fed `searchParams`; render the awaited element directly.

vi.mock("@/components/auth/login-form", () => ({ LoginForm: () => <div data-testid="login-form" /> }));
vi.mock("@/components/auth/dev-sign-in-panel", () => ({ DevSignInPanel: () => null }));

import LoginPage from "@/app/(auth)/login/page";
import {
  ERASURE_PENDING_DETAIL,
  ERASURE_PENDING_HEADLINE,
  ERASURE_RETRY_QUALIFIER,
  NEW_TAB_CUE,
  PRIVACY_POLICY_CITATION,
  PRIVACY_POLICY_URL,
} from "@/lib/legal/account-deletion-copy";

async function renderPage(params: Record<string, string>) {
  render(await LoginPage({ searchParams: Promise.resolve(params) }));
}

afterEach(cleanup);

describe("login page erasure-pending notice", () => {
  it("renders the shared strings as a status region with the policy link when ?erasure=pending", async () => {
    await renderPage({ deleted: "true", erasure: "pending" });
    const notice = screen.getByRole("status");
    expect(screen.queryByRole("alert")).toBeNull();
    expect(notice.textContent).toContain(ERASURE_PENDING_HEADLINE);
    expect(notice.textContent).toContain(ERASURE_PENDING_DETAIL);
    expect(notice.textContent).toContain(ERASURE_RETRY_QUALIFIER);
    const link = screen.getByRole("link", { name: /privacy policy/i });
    expect(link.getAttribute("href")).toBe(PRIVACY_POLICY_URL);
    expect(link.childNodes[0].textContent).toBe(PRIVACY_POLICY_CITATION);
    expect(link.textContent).toBe(PRIVACY_POLICY_CITATION + NEW_TAB_CUE);
  });

  it("never states a guarantee, a recorded fact, informal wording, or workspace-file / residue claims", async () => {
    await renderPage({ erasure: "pending" });
    const text = screen.getByRole("status").textContent ?? "";
    expect(text).not.toMatch(
      /will be completed|nothing further|recorded as outstanding|not going to tell|workspace files|\.gc-cursor|lock file|purge|erased|wiped/i,
    );
    expect(text).toMatch(/best effort/i);
  });

  it("renders no notice without the erasure param (plain deleted state and bare login)", async () => {
    await renderPage({ deleted: "true" });
    expect(screen.queryByRole("status")).toBeNull();
    expect(screen.queryByText(ERASURE_PENDING_HEADLINE)).toBeNull();
    cleanup();
    await renderPage({ erasure: "other" });
    expect(screen.queryByRole("status")).toBeNull();
    expect(screen.getByTestId("login-form")).toBeInTheDocument();
  });
});
