import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen, fireEvent, waitFor } from "@testing-library/react";

// feat-skip-api-key-onboarding (#4642) — AC4. The /setup-key page offers a
// "Set up later" action that POSTs the CSRF-guarded skip route and then
// routes onward to /connect-repo (keyless-safe). The FR4 warning copy is
// present and factual (separate, paid Anthropic account).

const pushMock = vi.fn();
// GAP E (ADR-067 staleTimes): the "Set up later" skip terminal hop into
// /dashboard now HARD-navs via window.location.assign; the intermediate hop to
// /connect-repo still uses router.push.
const assignMock = vi.fn();
vi.mock("next/navigation", () => ({
  useRouter: () => ({ push: pushMock }),
  // Sibling #4641 added invite redirectTo threading via useSearchParams.
  useSearchParams: () => new URLSearchParams(),
}));

import SetupKeyPage from "@/app/(auth)/setup-key/page";

let originalLocation: Location;
beforeEach(() => {
  vi.clearAllMocks();
  vi.stubGlobal("fetch", vi.fn());
  originalLocation = window.location;
  Object.defineProperty(window, "location", {
    configurable: true,
    writable: true,
    value: { assign: assignMock, pathname: "/setup-key" } as unknown as Location,
  });
});

afterEach(() => {
  Object.defineProperty(window, "location", {
    configurable: true,
    writable: true,
    value: originalLocation,
  });
});

describe("SetupKeyPage — Set up later (AC4)", () => {
  it("renders the FR4 factual warning copy", () => {
    render(<SetupKeyPage />);
    expect(
      screen.getByText(/requires your own Anthropic API key/i),
    ).toBeTruthy();
    expect(screen.getByText(/separate, paid Anthropic account/i)).toBeTruthy();
  });

  it("POSTs the skip route then routes to /dashboard on success", async () => {
    (fetch as ReturnType<typeof vi.fn>).mockResolvedValue({ ok: true });
    render(<SetupKeyPage />);

    fireEvent.click(screen.getByRole("button", { name: /set up later/i }));

    await waitFor(() => expect(assignMock).toHaveBeenCalledWith("/dashboard"));
    expect(fetch).toHaveBeenCalledWith(
      "/api/setup-key/skip",
      expect.objectContaining({ method: "POST" }),
    );
  });

  it("shows an error and does NOT route when the skip route fails", async () => {
    (fetch as ReturnType<typeof vi.fn>).mockResolvedValue({ ok: false });
    render(<SetupKeyPage />);

    fireEvent.click(screen.getByRole("button", { name: /set up later/i }));

    await waitFor(() => expect(screen.getByRole("alert")).toBeTruthy());
    expect(assignMock).not.toHaveBeenCalled();
    expect(pushMock).not.toHaveBeenCalled();
  });
});
