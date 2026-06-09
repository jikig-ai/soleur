import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { cleanup, fireEvent, render, screen, within } from "@testing-library/react";
import { CtaBanner } from "@/components/shared/cta-banner";

const STORAGE_KEY = "soleur:shared:cta-dismissed";

const formPresent = () => screen.queryByPlaceholderText(/you@company.com/i);
const reopenPresent = () => screen.queryByTestId("cta-banner-reopen");

beforeEach(() => {
  sessionStorage.clear();
});

afterEach(() => {
  cleanup();
  sessionStorage.clear();
  vi.restoreAllMocks();
});

describe("CtaBanner collapse / reopen affordance", () => {
  it("renders the waitlist form and the collapse button by default", () => {
    render(<CtaBanner />);
    expect(formPresent()).toBeTruthy();
    expect(screen.getByTestId("cta-banner-dismiss")).toBeTruthy();
    // The reopen affordance only exists once collapsed.
    expect(reopenPresent()).toBeNull();
  });

  it("collapsing shows the thin bar — the banner is NOT unmounted", () => {
    render(<CtaBanner />);
    fireEvent.click(screen.getByTestId("cta-banner-dismiss"));

    // Collapsed strip is present (banner still mounted, just collapsed).
    const reopen = screen.getByRole("button", {
      name: /reopen soleur signup banner/i,
    });
    expect(reopen).toBeTruthy();
    // The full form is gone in the collapsed state.
    expect(formPresent()).toBeNull();
    // The brand label survives INSIDE the collapsed strip specifically
    // (scoped so it can't pass by matching the expanded banner copy).
    expect(within(reopen).getByText(/built with/i)).toBeTruthy();
    expect(within(reopen).getByText(/soleur/i)).toBeTruthy();
  });

  it("the collapsed bar exposes the reopen affordance with correct aria", () => {
    render(<CtaBanner />);
    fireEvent.click(screen.getByTestId("cta-banner-dismiss"));

    const reopen = screen.getByRole("button", {
      name: /reopen soleur signup banner/i,
    });
    expect(reopen.getAttribute("aria-label")).toBe("Reopen Soleur signup banner");
    expect(reopen.getAttribute("aria-expanded")).toBe("false");
  });

  it("clicking the collapsed bar re-expands the full banner with the form", () => {
    render(<CtaBanner />);
    fireEvent.click(screen.getByTestId("cta-banner-dismiss"));
    expect(formPresent()).toBeNull();

    fireEvent.click(
      screen.getByRole("button", { name: /reopen soleur signup banner/i }),
    );

    // Round-trip restored without any reload.
    expect(formPresent()).toBeTruthy();
    expect(reopenPresent()).toBeNull();
  });

  it("the expanded close control reflects aria-expanded=true", () => {
    render(<CtaBanner />);
    expect(
      screen.getByTestId("cta-banner-dismiss").getAttribute("aria-expanded"),
    ).toBe("true");
  });

  it("both controls are real <button> elements (keyboard-operable)", () => {
    render(<CtaBanner />);
    expect(screen.getByTestId("cta-banner-dismiss").tagName).toBe("BUTTON");

    fireEvent.click(screen.getByTestId("cta-banner-dismiss"));
    expect(screen.getByTestId("cta-banner-reopen").tagName).toBe("BUTTON");
  });

  it("does NOT persist collapsed state — no sessionStorage write occurs on collapse", () => {
    // Spy directly so the assertion is non-vacuous: it proves the component
    // issues zero writes, independent of the beforeEach clear (the residue
    // checks below alone would pass even if a write landed under a new key).
    const setItemSpy = vi.spyOn(Storage.prototype, "setItem");
    render(<CtaBanner />);
    fireEvent.click(screen.getByTestId("cta-banner-dismiss"));

    expect(setItemSpy).not.toHaveBeenCalled();
    expect(sessionStorage.getItem(STORAGE_KEY)).toBeNull();
    expect(sessionStorage.length).toBe(0);
  });

  it("a fresh mount always starts expanded even if the old key is set", () => {
    // Pre-seed the legacy key; the component must ignore it (reload restores
    // the full banner).
    sessionStorage.setItem(STORAGE_KEY, "1");
    render(<CtaBanner />);
    expect(formPresent()).toBeTruthy();
    expect(reopenPresent()).toBeNull();
  });
});
