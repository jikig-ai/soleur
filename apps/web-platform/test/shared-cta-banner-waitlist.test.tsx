import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import {
  cleanup,
  fireEvent,
  render,
  screen,
  waitFor,
} from "@testing-library/react";
import { CtaBanner } from "@/components/shared/cta-banner";

beforeEach(() => {
  sessionStorage.clear();
});

afterEach(() => {
  cleanup();
  sessionStorage.clear();
  vi.restoreAllMocks();
});

function emailInput() {
  return screen.getByPlaceholderText(/you@company.com/i);
}

function typeEmail(value = "user@company.com") {
  fireEvent.change(emailInput(), { target: { value } });
}

function joinButton() {
  return screen.getByRole("button", { name: /^join$/i }) as HTMLButtonElement;
}

describe("CtaBanner waitlist form", () => {
  it("renders an aria-live status region that is empty in idle", () => {
    render(<CtaBanner />);
    const live = screen
      .getAllByRole("status")
      .find((el) => el.getAttribute("aria-live") === "polite");
    expect(live).toBeTruthy();
    expect(live!.textContent).toBe("");
  });

  it("shows the privacy notice + Privacy Policy link in idle", () => {
    render(<CtaBanner />);
    expect(screen.getByText(/no spam\. we email you once/i)).toBeTruthy();
    const link = screen.getByRole("link", {
      name: /privacy policy/i,
    }) as HTMLAnchorElement;
    expect(link.href).toContain("soleur.ai/pages/legal/privacy-policy.html");
  });

  it("on success replaces the form with the confirm-inbox copy", async () => {
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue(new Response("", { status: 200 })));
    render(<CtaBanner />);
    typeEmail();
    fireEvent.click(joinButton());
    await waitFor(() => expect(screen.getByText(/you're on the list/i)).toBeTruthy());
    expect(screen.getByText(/check your inbox to confirm/i)).toBeTruthy();
    // Form is replaced — the email input is gone.
    expect(screen.queryByPlaceholderText(/you@company.com/i)).toBeNull();
  });

  it("on fetch rejection (offline) shows error and re-enables the form", async () => {
    vi.stubGlobal("fetch", vi.fn().mockRejectedValue(new Error("offline")));
    render(<CtaBanner />);
    typeEmail();
    fireEvent.click(joinButton());
    await waitFor(() =>
      expect(screen.getByText(/something went wrong/i)).toBeTruthy(),
    );
    // No permanent submitting freeze: the form is still present and re-enabled.
    expect(joinButton().disabled).toBe(false);
    expect(emailInput()).toBeTruthy();
  });

  it("treats a non-2xx response (e.g. 429) as error", async () => {
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue(new Response("", { status: 429 })));
    render(<CtaBanner />);
    typeEmail();
    fireEvent.click(joinButton());
    await waitFor(() =>
      expect(screen.getByText(/something went wrong/i)).toBeTruthy(),
    );
  });

  it("shows a 'Joining…' affordance while in-flight, then success (manual-trigger timing)", async () => {
    let resolveFetch!: (v: Response) => void;
    const pending = new Promise<Response>((r) => {
      resolveFetch = r;
    });
    vi.stubGlobal("fetch", vi.fn().mockReturnValue(pending));
    render(<CtaBanner />);
    typeEmail();
    fireEvent.click(joinButton());

    // Intermediate submitting state: label flips and the button disables.
    await waitFor(() =>
      expect(screen.getByRole("button", { name: /joining/i })).toBeTruthy(),
    );
    expect(
      (screen.getByRole("button", { name: /joining/i }) as HTMLButtonElement)
        .disabled,
    ).toBe(true);

    resolveFetch(new Response("", { status: 200 }));
    await waitFor(() => expect(screen.getByText(/you're on the list/i)).toBeTruthy());
  });
});
