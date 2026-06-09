import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { CtaBanner } from "@/components/shared/cta-banner";

const STORAGE_KEY = "soleur:shared:cta-dismissed";

const formPresent = () => screen.queryByPlaceholderText(/you@company.com/i);
const toggle = () => screen.getByTestId("cta-banner-toggle");
const body = () => screen.getByTestId("cta-banner-body");

// happy-dom reflects the boolean `inert` attribute via hasAttribute, not the
// IDL property — assert on the attribute.
const isHidden = (el: HTMLElement) =>
  el.hasAttribute("inert") || el.getAttribute("aria-hidden") === "true";

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
    // The body is open (not inert/hidden) when expanded.
    expect(isHidden(body())).toBe(false);
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
    // The collapsible body is inert / aria-hidden — but NOT removed from the DOM.
    expect(isHidden(body())).toBe(true);
    expect(formPresent()).toBeTruthy(); // still in the DOM, just height-collapsed
  });

  it("clicking again re-expands — aria + body restored", () => {
    render(<CtaBanner />);
    fireEvent.click(toggle()); // collapse
    fireEvent.click(toggle()); // re-expand

    expect(toggle().getAttribute("aria-expanded")).toBe("true");
    expect(toggle().getAttribute("aria-label")).toBe("Collapse signup banner");
    expect(isHidden(body())).toBe(false);
    expect(formPresent()).toBeTruthy();
  });

  it("the toggle is a single persistent <button> present in BOTH states", () => {
    render(<CtaBanner />);
    expect(toggle().tagName).toBe("BUTTON");

    fireEvent.click(toggle());
    // Still resolvable by the same test id after collapse (it did not unmount).
    expect(toggle().tagName).toBe("BUTTON");
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
