import { describe, it, expect, vi } from "vitest";
import { render, screen } from "@testing-library/react";

// #4307 plan §2.6 / AC8. The /login page's LoginForm reads
// `?revoked=removed|role-changed` and renders a banner above the form.
// Unknown values render no banner (defensive default).

// next/navigation is the SUT's source of search params; mock it per-test.
const searchParamsHolder: { current: URLSearchParams } = {
  current: new URLSearchParams(),
};

vi.mock("next/navigation", () => ({
  useSearchParams: () => searchParamsHolder.current,
  useRouter: () => ({ push: vi.fn(), replace: vi.fn() }),
}));

// supabase client + observability live behind imports that we don't exercise
// in the initial render; stub minimally.
vi.mock("@/lib/supabase/client", () => ({
  createClient: () => ({ auth: { signInWithOtp: vi.fn(), verifyOtp: vi.fn() } }),
}));
vi.mock("@/lib/client-observability", () => ({
  reportSilentFallback: vi.fn(),
}));
vi.mock("@/components/auth/oauth-buttons", () => ({
  OAuthButtons: () => null,
}));

import { LoginForm } from "@/components/auth/login-form";

describe("LoginForm #4307 revoked banner", () => {
  it("renders the 'removed' copy when ?revoked=removed", () => {
    searchParamsHolder.current = new URLSearchParams("revoked=removed");
    render(<LoginForm />);
    const banner = screen.getByTestId("revoked-banner");
    expect(banner.textContent).toMatch(/workspace owner removed you/i);
  });

  it("renders the 'role-changed' copy when ?revoked=role-changed", () => {
    searchParamsHolder.current = new URLSearchParams("revoked=role-changed");
    render(<LoginForm />);
    const banner = screen.getByTestId("revoked-banner");
    expect(banner.textContent).toMatch(/role was updated/i);
  });

  it("renders NO banner when ?revoked is absent", () => {
    searchParamsHolder.current = new URLSearchParams();
    render(<LoginForm />);
    expect(screen.queryByTestId("revoked-banner")).toBeNull();
  });

  it("renders NO banner for unknown ?revoked values (defensive default)", () => {
    searchParamsHolder.current = new URLSearchParams("revoked=something-else");
    render(<LoginForm />);
    expect(screen.queryByTestId("revoked-banner")).toBeNull();
  });
});
