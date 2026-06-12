import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import {
  cleanup,
  fireEvent,
  render,
  screen,
  waitFor,
} from "@testing-library/react";
import { CtaBanner } from "@/components/shared/cta-banner";

const JOINED_KEY = "soleur:shared:waitlist-joined";

beforeEach(() => {
  sessionStorage.clear();
  localStorage.clear();
});

afterEach(() => {
  cleanup();
  sessionStorage.clear();
  localStorage.clear();
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

describe("CtaBanner remembers an already-joined visitor (localStorage)", () => {
  // TST1 / AC1 — a returning visitor whose browser carries the joined flag is
  // shown NO banner at all (wireframe State C): the component returns null.
  it("renders nothing when the joined flag is seeded before mount", () => {
    localStorage.setItem(JOINED_KEY, "1");
    render(<CtaBanner />);
    // The whole component short-circuited to null — form AND brand header gone.
    expect(screen.queryByPlaceholderText(/you@company.com/i)).toBeNull();
    expect(screen.queryByText(/built with/i)).toBeNull();
  });

  // TST2a / AC2 — a confirmed 2xx join writes the durable flag exactly once,
  // with the boolean "1" value (never the email — AC7).
  it("writes the joined flag on a successful (2xx) submit", async () => {
    const setItemSpy = vi.spyOn(localStorage, "setItem");
    vi.stubGlobal(
      "fetch",
      vi.fn().mockResolvedValue(new Response("", { status: 200 })),
    );
    render(<CtaBanner />);
    typeEmail();
    fireEvent.click(joinButton());
    await waitFor(() =>
      expect(screen.getByText(/you're on the list/i)).toBeTruthy(),
    );
    expect(setItemSpy).toHaveBeenCalledWith(JOINED_KEY, "1");
    // AC7 — the entered email is never persisted to storage.
    expect(setItemSpy).not.toHaveBeenCalledWith(
      JOINED_KEY,
      expect.stringContaining("@"),
    );
  });

  // TST2b / AC3 (load-bearing) — a non-2xx (429) submit must NOT write the flag.
  // Response.ok is false for every non-2xx, so 429 represents the whole class.
  it("does NOT write the joined flag on a non-2xx (429) submit", async () => {
    const setItemSpy = vi.spyOn(localStorage, "setItem");
    vi.stubGlobal(
      "fetch",
      vi.fn().mockResolvedValue(new Response("", { status: 429 })),
    );
    render(<CtaBanner />);
    typeEmail();
    fireEvent.click(joinButton());
    await waitFor(() =>
      expect(screen.getByText(/something went wrong/i)).toBeTruthy(),
    );
    expect(setItemSpy).not.toHaveBeenCalledWith(JOINED_KEY, expect.anything());
  });

  // TST2b / AC3 (load-bearing) — a fetch rejection (offline) must NOT write the
  // flag (the catch branch). A flag on a failed signup is the lost-lead incident.
  it("does NOT write the joined flag on a fetch rejection (offline)", async () => {
    const setItemSpy = vi.spyOn(localStorage, "setItem");
    vi.stubGlobal("fetch", vi.fn().mockRejectedValue(new Error("offline")));
    render(<CtaBanner />);
    typeEmail();
    fireEvent.click(joinButton());
    await waitFor(() =>
      expect(screen.getByText(/something went wrong/i)).toBeTruthy(),
    );
    expect(setItemSpy).not.toHaveBeenCalledWith(JOINED_KEY, expect.anything());
  });

  // TST2c / AC6 — a thrown read falls back to "show the banner" (the safe
  // direction). A read-throw that hid the banner would be a distinct
  // single-user incident, so this pins the fallback direction.
  it("still shows the banner when localStorage.getItem throws", () => {
    vi.spyOn(localStorage, "getItem").mockImplementation(() => {
      throw new Error("denied");
    });
    render(<CtaBanner />);
    expect(screen.queryByPlaceholderText(/you@company.com/i)).toBeTruthy();
  });
});
