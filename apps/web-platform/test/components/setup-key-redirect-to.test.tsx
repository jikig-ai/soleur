import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, screen, fireEvent, waitFor } from "@testing-library/react";

// A keyless invitee threads the invite target through setup-key: accept-terms
// returns /setup-key?redirectTo=/invite/<token>, and on key-save success
// setup-key must carry it to connect-repo (the terminal funnel hop) as
// `return_to`, so the new invitee auto-returns to /invite after onboarding.

const routerMock = { push: vi.fn() };
const searchParamsHolder: { current: URLSearchParams } = {
  current: new URLSearchParams(),
};

vi.mock("next/navigation", () => ({
  useRouter: () => routerMock,
  useSearchParams: () => searchParamsHolder.current,
}));

import SetupKeyPage from "@/app/(auth)/setup-key/page";

const INVITE_PATH = "/invite/Zm9vYmFyYmF6cXV4MTIzNDU2Nzg5MGFiY2RlZmdoaWpr";

async function saveKeyWith(redirectToParam: string | null) {
  searchParamsHolder.current = new URLSearchParams(
    redirectToParam === null ? {} : { redirectTo: redirectToParam },
  );
  vi.stubGlobal(
    "fetch",
    vi.fn().mockResolvedValue({
      ok: true,
      json: () => Promise.resolve({ valid: true }),
    }),
  );
  render(<SetupKeyPage />);
  fireEvent.change(screen.getByPlaceholderText("sk-ant-..."), {
    target: { value: "sk-ant-xyz" },
  });
  fireEvent.click(screen.getByRole("button", { name: /save key/i }));
}

describe("setup-key → connect-repo carry-forward", () => {
  beforeEach(() => {
    routerMock.push.mockClear();
    searchParamsHolder.current = new URLSearchParams();
  });

  it("carries a validated /invite target to connect-repo as return_to", async () => {
    await saveKeyWith(INVITE_PATH);
    await waitFor(
      () =>
        expect(routerMock.push).toHaveBeenCalledWith(
          `/connect-repo?return_to=${encodeURIComponent(INVITE_PATH)}`,
        ),
      { timeout: 2000 },
    );
  });

  it("pushes bare /connect-repo when no redirectTo (genuine new signup)", async () => {
    await saveKeyWith(null);
    await waitFor(
      () => expect(routerMock.push).toHaveBeenCalledWith("/connect-repo"),
      { timeout: 2000 },
    );
  });

  it("drops an open-redirect redirectTo (bare /connect-repo, never off-origin)", async () => {
    await saveKeyWith("https://evil.example");
    await waitFor(
      () => expect(routerMock.push).toHaveBeenCalledWith("/connect-repo"),
      { timeout: 2000 },
    );
    const pushed = routerMock.push.mock.calls.map((c) => c[0]).join(" ");
    expect(pushed).not.toContain("evil.example");
    expect(pushed).not.toContain("return_to");
  });
});
