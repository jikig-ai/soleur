/**
 * feat-debug-mode-stream — Phase 5.2 client-render tests (AC8).
 *   - the panel is HIDDEN for the non-dev cohort (available=false)
 *   - render RE-REDACTION: a frame whose body still carries a secret is
 *     redacted in the DOM (dual-gate, mirroring message-bubble)
 *   - withheld + disconnected affordances
 *   - the settings toggle is read-only (disabled) for a non-owner dev
 */
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen, fireEvent, within } from "@testing-library/react";
import { DebugStreamPanel } from "@/components/chat/debug-stream-panel";
import { DebugModeToggle } from "@/components/settings/debug-mode-toggle";
import type { ChatDebugEventMessage } from "@/lib/chat-state-machine";

// Split across concatenation so GitHub secret-scanning push-protection does not
// flag the (fake) token (cq-test-fixtures-synthesized-only).
const ANTHROPIC = "sk-" + "ant-api03AAAABBBBCCCCDDDDEEEEFFFF1111";

function ev(partial: Partial<ChatDebugEventMessage> & { id: string }): ChatDebugEventMessage {
  return {
    role: "assistant",
    content: "",
    type: "debug_event",
    debugKind: "tool_use",
    body: "",
    ...partial,
  };
}

describe("DebugStreamPanel (AC8)", () => {
  it("renders nothing for the non-dev cohort (available=false)", () => {
    const { container } = render(
      <DebugStreamPanel available={false} events={[]} connected />,
    );
    expect(container.firstChild).toBeNull();
  });

  it("re-redacts a leaked secret in the body at render (dual-gate)", () => {
    const events = [ev({ id: "1", body: `{"x":"${ANTHROPIC}"}`, label: "Running command..." })];
    render(<DebugStreamPanel available events={events} connected />);
    // Expand the collapsed drawer.
    fireEvent.click(screen.getByRole("button", { name: /debug stream/i }));
    const panel = screen.getByTestId("debug-stream-panel");
    expect(panel.textContent).not.toContain(ANTHROPIC);
    expect(panel.textContent).toContain("[redacted-key]");
  });

  it("shows a withheld count for dropped tool inputs", () => {
    const events = [
      ev({ id: "1", body: "[input withheld: failed redaction probe]", label: "Working..." }),
    ];
    render(<DebugStreamPanel available events={events} connected />);
    fireEvent.click(screen.getByRole("button", { name: /debug stream/i }));
    expect(screen.getByTestId("debug-stream-withheld").textContent).toMatch(/1 event withheld/);
  });

  it("surfaces a disconnected affordance when the WS is down", () => {
    render(<DebugStreamPanel available events={[]} connected={false} />);
    expect(screen.getByTestId("debug-stream-disconnected")).toBeTruthy();
  });

  it("empty state distinguishes completed-turn from no-activity", () => {
    render(<DebugStreamPanel available events={[]} connected hadCompletedTurn />);
    fireEvent.click(screen.getByRole("button", { name: /debug stream/i }));
    expect(screen.getByTestId("debug-stream-empty").textContent).toMatch(/gate is unavailable/i);
  });
});

describe("DebugStreamPanel — Copy control", () => {
  const writeText = vi.fn().mockResolvedValue(undefined);

  const originalClipboard = Object.getOwnPropertyDescriptor(navigator, "clipboard");

  beforeEach(() => {
    Object.defineProperty(navigator, "clipboard", {
      value: { writeText },
      configurable: true,
      writable: true,
    });
    writeText.mockClear();
  });

  afterEach(() => {
    // Restore so the mocked clipboard does not leak into sibling suites.
    if (originalClipboard) {
      Object.defineProperty(navigator, "clipboard", originalClipboard);
    } else {
      delete (navigator as { clipboard?: unknown }).clipboard;
    }
  });

  it("copies the REDACTED body, never the raw secret, and flips to Copied (AC1/AC2/AC5)", async () => {
    const events = [
      ev({ id: "1", body: `{"x":"${ANTHROPIC}"}`, label: "Running command..." }),
    ];
    render(<DebugStreamPanel available events={events} connected />);
    const copy = screen.getByTestId("debug-stream-copy");
    expect(copy.textContent).toBe("Copy");
    fireEvent.click(copy);
    await vi.waitFor(() => expect(writeText).toHaveBeenCalledTimes(1));
    const written = writeText.mock.calls[0][0] as string;
    expect(written).toContain("[redacted-key]");
    expect(written).not.toContain(ANTHROPIC);
    // The success affordance: the label flips to "Copied" after the write.
    await vi.waitFor(() => expect(copy.textContent).toBe("Copied"));
  });

  it("copies a withheld placeholder verbatim (AC3)", async () => {
    const placeholder = "[input withheld: failed redaction probe]";
    const events = [ev({ id: "1", body: placeholder, label: "Working..." })];
    render(<DebugStreamPanel available events={events} connected />);
    fireEvent.click(screen.getByTestId("debug-stream-copy"));
    await vi.waitFor(() => expect(writeText).toHaveBeenCalledTimes(1));
    expect(writeText.mock.calls[0][0] as string).toContain(placeholder);
  });

  it("does NOT toggle the panel expand state when clicked (AC4/AC6)", () => {
    const events = [ev({ id: "1", body: "ls", label: "Running command..." })];
    render(<DebugStreamPanel available events={events} connected />);
    const toggle = screen.getByRole("button", { name: /debug stream/i });
    expect(toggle.getAttribute("aria-expanded")).toBe("false");
    // Copy must be a SIBLING, not a descendant of the toggle button.
    expect(toggle.querySelector('[data-testid="debug-stream-copy"]')).toBeNull();
    fireEvent.click(screen.getByTestId("debug-stream-copy"));
    expect(toggle.getAttribute("aria-expanded")).toBe("false");
  });

  it("is disabled with no events and does not write (AC5)", () => {
    render(<DebugStreamPanel available events={[]} connected />);
    const copy = screen.getByTestId("debug-stream-copy") as HTMLButtonElement;
    expect(copy.disabled).toBe(true);
    fireEvent.click(copy);
    expect(writeText).not.toHaveBeenCalled();
  });

  it("uses the AA-safe gold resting token, not the sub-AA -fg gold", () => {
    // -text gold (5.56:1 light) passes AA 4.5:1 at 10px; -fg gold (3.66:1) does
    // not. A future revert of the resting color to text-soleur-accent-gold-fg
    // reintroduces a light-theme sub-AA failure and fails this guard.
    const events = [ev({ id: "1", body: "ls", label: "Running command..." })];
    render(<DebugStreamPanel available events={events} connected />);
    const copy = screen.getByTestId("debug-stream-copy");
    expect(copy.className).toContain("text-soleur-accent-gold-text");
  });
});

describe("DebugStreamPanel — Show/Hide toggle affordance (regression #5241)", () => {
  it("renders the Show/Hide label INSIDE the toggle button and clicking it toggles (AC1)", () => {
    const events = [ev({ id: "1", body: "ls", label: "Running command..." })];
    render(<DebugStreamPanel available events={events} connected />);
    const toggle = screen.getByRole("button", { name: /debug stream/i });
    // (a) collapsed → the toggle button's own text carries the "Show" affordance
    //     (#5241 had moved it into an inert sibling span outside the button).
    expect(toggle.getAttribute("aria-expanded")).toBe("false");
    expect(within(toggle).getByText("Show")).toBeTruthy();
    // (b) clicking the word "Show" (inside the toggle) flips expanded false→true.
    fireEvent.click(within(toggle).getByText("Show"));
    expect(toggle.getAttribute("aria-expanded")).toBe("true");
    // …and the label swaps to "Hide" (still inside the toggle).
    expect(within(toggle).getByText("Hide")).toBeTruthy();
    // (c) clicking "Hide" collapses again.
    fireEvent.click(within(toggle).getByText("Hide"));
    expect(toggle.getAttribute("aria-expanded")).toBe("false");
  });
  // The "Copy is NOT a descendant of the toggle / does not toggle" invariant is
  // already owned by the AC4/AC6 test above — not duplicated here.
});

describe("DebugModeToggle (AC8 — owner-write, member read-only)", () => {
  it("a non-owner dev sees the switch but cannot flip it (read-only)", () => {
    render(<DebugModeToggle initialDebugMode={false} isOwner={false} />);
    const sw = screen.getByRole("switch", { name: /debug mode/i }) as HTMLButtonElement;
    expect(sw.disabled).toBe(true);
  });

  it("an owner can flip it (enabled control)", () => {
    render(<DebugModeToggle initialDebugMode={false} isOwner />);
    const sw = screen.getByRole("switch", { name: /debug mode/i }) as HTMLButtonElement;
    expect(sw.disabled).toBe(false);
  });
});
