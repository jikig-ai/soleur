// feat-ui-action-feedback — billing pending contract (brief §5, AC5/AC6b).
//
//   - redirectTo must NEVER reset `loading` once window.location.href is
//     assigned (the redirect latch — use-sign-out precedent; the old
//     `finally { setLoading(false) }` re-enabled the button in the gap
//     before the Stripe redirect committed → double-submit window)
//   - Error paths DO reset loading so retry stays possible
//   - Reactivate carries disabled + aria-busy while the portal POST is out
//   - A pending episode >~8s appends "Still working…" to a polite
//     role="status" region; the timer resets per episode

import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen, fireEvent, act, cleanup } from "@testing-library/react";

vi.mock("next/navigation", () => ({
  useRouter: () => ({ push: vi.fn(), refresh: vi.fn() }),
}));

import { BillingSection } from "@/components/settings/billing-section";

const BASE_PROPS = {
  subscriptionStatus: null as string | null,
  currentPeriodEnd: null as string | null,
  cancelAtPeriodEnd: false,
  conversationCount: 0,
  serviceTokenCount: 0,
  createdAt: new Date("2026-01-10").toISOString(),
};

function resp(ok: boolean, body: unknown = {}, status = ok ? 200 : 500): Response {
  return {
    ok,
    status,
    json: () => Promise.resolve(body),
  } as Response;
}

const fetchMock = vi.fn();
const hrefSetter = vi.fn<(v: string) => void>();

beforeEach(() => {
  vi.clearAllMocks();
  vi.stubGlobal("fetch", fetchMock);
  // Intercept `window.location.href = url` the way connect-repo-page.test.tsx
  // does — the setter capture is what lets the latch be observed without a
  // real document navigation.
  const originalHref = window.location.href;
  Object.defineProperty(window.location, "href", {
    get: () => originalHref,
    set: hrefSetter,
    configurable: true,
  });
});

afterEach(() => {
  cleanup();
  vi.unstubAllGlobals();
});

describe("BillingSection — redirect latch", () => {
  it("does NOT reset loading after window.location.href is assigned", async () => {
    fetchMock.mockResolvedValue(
      resp(true, { url: "https://billing.stripe.test/portal" }),
    );
    render(<BillingSection {...BASE_PROPS} />);

    const subscribe = screen.getByRole("button", { name: /^subscribe$/i });
    fireEvent.click(subscribe);

    await vi.waitFor(() =>
      expect(hrefSetter).toHaveBeenCalledWith(
        "https://billing.stripe.test/portal",
      ),
    );
    // The document load is the reset — until then the button stays latched.
    expect(subscribe).toBeDisabled();
    expect(subscribe).toHaveTextContent(/redirecting/i);
  });

  it("resets loading + surfaces role=alert when the endpoint errors", async () => {
    fetchMock.mockResolvedValue(resp(false, { error: "portal exploded" }));
    render(<BillingSection {...BASE_PROPS} />);

    const subscribe = screen.getByRole("button", { name: /^subscribe$/i });
    fireEvent.click(subscribe);

    const alert = await screen.findByRole("alert");
    expect(alert).toHaveTextContent("portal exploded");
    expect(subscribe).not.toBeDisabled();
    expect(hrefSetter).not.toHaveBeenCalled();
  });

  it("Reactivate is disabled + aria-busy while the portal request is in flight", async () => {
    let resolvePortal!: (v: Response) => void;
    fetchMock.mockImplementation((input: RequestInfo | URL) => {
      if (String(input).includes("invoices")) {
        return Promise.resolve(resp(true, { invoices: [] }));
      }
      return new Promise<Response>((res) => {
        resolvePortal = res;
      });
    });
    render(
      <BillingSection
        {...BASE_PROPS}
        subscriptionStatus="active"
        cancelAtPeriodEnd
        currentPeriodEnd="2026-05-13T00:00:00.000Z"
      />,
    );

    const reactivate = screen.getByRole("button", { name: /reactivate/i });
    fireEvent.click(reactivate);

    await vi.waitFor(() => expect(reactivate).toBeDisabled());
    expect(reactivate).toHaveAttribute("aria-busy", "true");

    await act(async () => {
      resolvePortal(resp(true, { url: "https://billing.stripe.test/p" }));
    });
    expect(hrefSetter).toHaveBeenCalledWith("https://billing.stripe.test/p");
    expect(reactivate).toBeDisabled();
  });
});

describe("BillingSection — ~8s escalation", () => {
  beforeEach(() => {
    vi.useFakeTimers();
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  function pendingPortalFetch() {
    const requests: Array<(v: Response) => void> = [];
    fetchMock.mockImplementation((input: RequestInfo | URL) => {
      if (String(input).includes("invoices")) {
        return Promise.resolve(resp(true, { invoices: [] }));
      }
      return new Promise<Response>((res) => {
        requests.push(res);
      });
    });
    return requests;
  }

  it("appends Still working… after ~8s pending and resets per episode", async () => {
    const requests = pendingPortalFetch();
    render(<BillingSection {...BASE_PROPS} />);

    const status = screen.getByRole("status");
    const subscribe = screen.getByRole("button", { name: /^subscribe$/i });
    expect(status).not.toHaveTextContent("Still working…");

    fireEvent.click(subscribe);
    await act(async () => {
      await vi.advanceTimersByTimeAsync(7_999);
    });
    expect(status).not.toHaveTextContent("Still working…");
    await act(async () => {
      await vi.advanceTimersByTimeAsync(2);
    });
    expect(status).toHaveTextContent("Still working…");

    // Episode ends in an error → escalation clears, control re-enables.
    await act(async () => {
      requests[0](resp(false, { error: "boom" }));
    });
    expect(status).not.toHaveTextContent("Still working…");
    expect(subscribe).not.toBeDisabled();

    // A new pending episode gets a fresh clock — no inherited stale timer.
    fireEvent.click(subscribe);
    await act(async () => {
      await vi.advanceTimersByTimeAsync(7_999);
    });
    expect(status).not.toHaveTextContent("Still working…");
    await act(async () => {
      await vi.advanceTimersByTimeAsync(2);
    });
    expect(status).toHaveTextContent("Still working…");
    await act(async () => {
      requests[1](resp(true, { url: "https://billing.stripe.test/p" }));
    });
  });
});
