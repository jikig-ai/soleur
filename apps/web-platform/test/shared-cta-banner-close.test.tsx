import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { CtaBanner } from "@/components/shared/cta-banner";

const STORAGE_KEY = "soleur:shared:cta-dismissed";

const formPresent = () => screen.queryByPlaceholderText(/you@company.com/i);
const toggle = () => screen.getByTestId("cta-banner-toggle");
const body = () => screen.getByTestId("cta-banner-body");

// `inert` and `aria-hidden` are DISTINCT contracts — `inert` removes the body
// from tab order + interaction, `aria-hidden` silences it for assistive tech.
// Assert each separately so dropping one (a half-regression) cannot pass green.
const expectBodyHidden = (hidden: boolean) => {
  expect(body().hasAttribute("inert")).toBe(hidden);
  expect(body().getAttribute("aria-hidden")).toBe(hidden ? "true" : null);
};

beforeEach(() => {
  sessionStorage.clear();
});

afterEach(() => {
  cleanup();
  sessionStorage.clear();
  vi.restoreAllMocks();
});

describe("CtaBanner single-toggle collapse / reopen", () => {
  it("renders the waitlist form and a single toggle (expanded) by default", () => {
    render(<CtaBanner />);
    expect(formPresent()).toBeTruthy();
    expect(toggle().getAttribute("aria-expanded")).toBe("true");
    expect(toggle().getAttribute("aria-label")).toBe("Collapse signup banner");
    // The body is open (neither inert nor aria-hidden) when expanded.
    expectBodyHidden(false);
  });

  it("clicking the toggle collapses — banner persists, body hidden, header stays", () => {
    render(<CtaBanner />);
    fireEvent.click(toggle());

    // The toggle is still present (persistent) and now signals "reopen".
    expect(toggle().getAttribute("aria-expanded")).toBe("false");
    expect(toggle().getAttribute("aria-label")).toMatch(
      /reopen soleur signup banner/i,
    );
    // The brand header survives (persistent header row).
    expect(screen.getByText(/built with/i)).toBeTruthy();
    // The collapsible body is inert AND aria-hidden — but NOT removed from the DOM.
    expectBodyHidden(true);
    expect(formPresent()).toBeTruthy(); // still in the DOM, just height-collapsed
  });

  it("clicking again re-expands — aria + body restored", () => {
    render(<CtaBanner />);
    fireEvent.click(toggle()); // collapse
    fireEvent.click(toggle()); // re-expand

    expect(toggle().getAttribute("aria-expanded")).toBe("true");
    expect(toggle().getAttribute("aria-label")).toBe("Collapse signup banner");
    expectBodyHidden(false);
    expect(formPresent()).toBeTruthy();
  });

  it("the toggle is the SAME persistent <button> node across both states", () => {
    render(<CtaBanner />);
    const before = toggle();
    expect(before.tagName).toBe("BUTTON");

    fireEvent.click(before);
    // Same DOM node after collapse — proves it did not unmount/remount (which is
    // what makes the 180° rotation animate rather than snap).
    expect(Object.is(toggle(), before)).toBe(true);
  });

  it("does NOT persist collapsed state — no sessionStorage write occurs on toggle", () => {
    // Spy directly so the assertion is non-vacuous: it proves the component
    // issues zero writes, independent of the beforeEach clear.
    const setItemSpy = vi.spyOn(Storage.prototype, "setItem");
    render(<CtaBanner />);
    fireEvent.click(toggle());

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
    expect(toggle().getAttribute("aria-expanded")).toBe("true");
  });
});
