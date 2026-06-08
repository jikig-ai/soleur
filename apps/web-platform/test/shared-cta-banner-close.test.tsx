import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { CtaBanner } from "@/components/shared/cta-banner";

const STORAGE_KEY = "soleur:shared:cta-dismissed";

// Banner presence is asserted via the dismiss button (stable across the
// link→inline-form rewrite) rather than the removed signup link.
const dismissPresent = () => screen.queryByTestId("cta-banner-dismiss");

beforeEach(() => {
  sessionStorage.clear();
});

afterEach(() => {
  cleanup();
  sessionStorage.clear();
  vi.restoreAllMocks();
});

describe("CtaBanner close affordance", () => {
  it("renders the waitlist form and dismiss button by default", () => {
    render(<CtaBanner />);
    expect(screen.getByPlaceholderText(/you@company.com/i)).toBeTruthy();
    expect(screen.getByRole("button", { name: /dismiss signup banner/i })).toBeTruthy();
  });

  it("hides the banner when the close button is clicked", () => {
    render(<CtaBanner />);
    fireEvent.click(screen.getByTestId("cta-banner-dismiss"));
    expect(dismissPresent()).toBeNull();
  });

  it("does not render when sessionStorage already marks the banner dismissed", () => {
    // Control: with cleared storage the banner MUST render — proves the
    // dismissed-key assertion below is gated on storage, not on always-null.
    const control = render(<CtaBanner />);
    expect(dismissPresent()).toBeTruthy();
    control.unmount();

    sessionStorage.setItem(STORAGE_KEY, "1");
    render(<CtaBanner />);
    expect(dismissPresent()).toBeNull();
  });

  it("persists the dismissal across remount within the same session", () => {
    const first = render(<CtaBanner />);
    fireEvent.click(screen.getByTestId("cta-banner-dismiss"));
    first.unmount();

    render(<CtaBanner />);
    expect(dismissPresent()).toBeNull();
    expect(sessionStorage.getItem(STORAGE_KEY)).toBe("1");
  });

  it("renders without throwing when sessionStorage.getItem throws", () => {
    vi.spyOn(Storage.prototype, "getItem").mockImplementation(() => {
      throw new Error("storage unavailable");
    });

    expect(() => render(<CtaBanner />)).not.toThrow();
    expect(dismissPresent()).toBeTruthy();
  });

  it("dismisses without throwing when sessionStorage.setItem throws", () => {
    vi.spyOn(Storage.prototype, "setItem").mockImplementation(() => {
      throw new Error("storage unavailable");
    });

    render(<CtaBanner />);
    expect(() =>
      fireEvent.click(screen.getByTestId("cta-banner-dismiss")),
    ).not.toThrow();
    expect(dismissPresent()).toBeNull();
  });
});
