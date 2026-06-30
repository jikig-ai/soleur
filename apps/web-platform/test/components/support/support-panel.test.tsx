import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen, fireEvent, cleanup, within } from "@testing-library/react";

const flagState = vi.hoisted(() => ({ support: true }));
vi.mock("@/components/feature-flags/provider", () => ({
  useOptionalFeatureFlag: (name: string) =>
    name === "support" ? flagState.support : false,
}));

const routerPush = vi.hoisted(() => vi.fn());
vi.mock("next/navigation", () => ({
  useRouter: () => ({ push: routerPush, replace: vi.fn(), prefetch: vi.fn() }),
}));

import { SupportLauncher } from "@/components/support/support-launcher";
import { SUPPORT_STARTER_CHIPS } from "@/components/support/support-persona";

function openPanel() {
  render(<SupportLauncher />);
  fireEvent.click(screen.getByLabelText("Open support"));
  return screen.getByRole("dialog");
}

describe("SupportPanel — interface shell", () => {
  beforeEach(() => {
    flagState.support = true;
    routerPush.mockClear();
  });
  afterEach(() => cleanup());

  it("shows the empty state: greeting, preview note, and 3 starter chips", () => {
    const dialog = openPanel();
    expect(within(dialog).getByText(/I'm Soleur Support/i)).toBeTruthy();
    expect(
      within(dialog).getByText(/live support chat is coming soon/i),
    ).toBeTruthy();
    for (const chip of SUPPORT_STARTER_CHIPS) {
      expect(within(dialog).getByText(chip.label)).toBeTruthy();
    }
  });

  it("send disabled on empty/whitespace input; no message rendered", () => {
    const dialog = openPanel();
    const sendBtn = within(dialog).getByLabelText("Send message") as HTMLButtonElement;
    expect(sendBtn.disabled).toBe(true);
    const textarea = within(dialog).getByPlaceholderText("Ask a question…");
    fireEvent.change(textarea, { target: { value: "   " } });
    expect(sendBtn.disabled).toBe(true);
  });

  it("typing + send renders a user bubble and a canned PREVIEW reply, with NO network call", () => {
    const fetchSpy = vi.fn();
    vi.stubGlobal("fetch", fetchSpy);
    const dialog = openPanel();
    const textarea = within(dialog).getByPlaceholderText("Ask a question…");
    fireEvent.change(textarea, { target: { value: "where do I start?" } });
    fireEvent.click(within(dialog).getByLabelText("Send message"));

    expect(within(dialog).getByText("where do I start?")).toBeTruthy();
    // Support reply carries the PREVIEW badge.
    expect(within(dialog).getByText("Preview")).toBeTruthy();
    expect(fetchSpy).not.toHaveBeenCalled();
    vi.unstubAllGlobals();
  });

  it("tapping a starter chip sends that question and produces a reply", () => {
    const dialog = openPanel();
    const chip = SUPPORT_STARTER_CHIPS[0];
    fireEvent.click(within(dialog).getByText(chip.label));
    // The chip text now appears as a user bubble (and chips are gone).
    expect(within(dialog).getAllByText(chip.label).length).toBeGreaterThan(0);
    expect(within(dialog).getByText("Preview")).toBeTruthy();
    // Reply renders as markdown: bold renders as <strong>, no literal "**".
    expect(dialog.querySelector("strong")).toBeTruthy();
    expect(dialog.textContent ?? "").not.toContain("**");
  });

  it("clicking an internal reply link navigates in-app (router.push) + closes, not a new tab", () => {
    const dialog = openPanel();
    fireEvent.click(within(dialog).getByText(SUPPORT_STARTER_CHIPS[0].label));
    const kbLink = within(dialog).getByText("knowledge base").closest("a");
    expect(kbLink?.getAttribute("href")).toBe("/dashboard/kb");
    fireEvent.click(kbLink as Element);
    expect(routerPush).toHaveBeenCalledWith("/dashboard/kb");
    // Panel closed so the user lands on the KB (not the dimmed overlay).
    expect(screen.queryByRole("dialog")).toBeNull();
  });

  it("Escape closes the panel", () => {
    openPanel();
    fireEvent.keyDown(document, { key: "Escape" });
    expect(screen.queryByRole("dialog")).toBeNull();
    // Launcher bubble returns after close.
    expect(screen.getByLabelText("Open support")).toBeTruthy();
  });

  it("X button closes the panel", () => {
    const dialog = openPanel();
    fireEvent.click(within(dialog).getByLabelText("Close support"));
    expect(screen.queryByRole("dialog")).toBeNull();
  });

  it("backdrop click closes the panel", () => {
    openPanel();
    const backdrop = document.querySelector('[role="presentation"]');
    expect(backdrop).toBeTruthy();
    fireEvent.click(backdrop as Element);
    expect(screen.queryByRole("dialog")).toBeNull();
  });
});
