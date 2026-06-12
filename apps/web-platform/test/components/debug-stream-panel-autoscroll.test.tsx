/**
 * Plan 2026-06-12-fix-concierge-stream-timeout-debug-scroll-plan.md, Phase 2 —
 * Debug stream sticky autoscroll-to-bottom.
 *
 * The panel pins the newest entry into view as events arrive, but stops
 * auto-scrolling the moment the operator scrolls up to read history, and
 * resumes once they scroll back to the bottom.
 *
 * happy-dom does NOT implement `scrollTop` / `scrollHeight` / `clientHeight`,
 * so each test installs them on the `<ul>` via `Object.defineProperty`
 * (get/set backed by a mutable closure var) so it can drive `scrollTop` and
 * assert the post-effect value.
 */
import { describe, it, expect, beforeEach, afterEach } from "vitest";
import { render, fireEvent, act } from "@testing-library/react";
import { DebugStreamPanel } from "@/components/chat/debug-stream-panel";
import type { ChatDebugEventMessage } from "@/lib/chat-state-machine";

function ev(partial: Partial<ChatDebugEventMessage> & { id: string }): ChatDebugEventMessage {
  return {
    role: "assistant",
    content: "",
    type: "debug_event",
    debugKind: "tool_use",
    body: "",
    label: `event ${partial.id}`,
    ...partial,
  };
}

// The scroll geometry the test drives. `scrollHeight`/`clientHeight` model a
// list taller than its viewport; `scrollTop` is mutable so an autoscroll
// effect can write it and the test can read the post-effect value.
const SCROLL_HEIGHT = 1000;
const CLIENT_HEIGHT = 300;

/**
 * Installs mutable scroll geometry on the rendered `<ul>`. happy-dom returns
 * 0 for all three by default; without this the effect's threshold math and
 * the `scrollTop = scrollHeight` write are unobservable.
 */
function instrumentList(ul: HTMLUListElement, initialScrollTop: number): { get scrollTop(): number } {
  let scrollTop = initialScrollTop;
  Object.defineProperty(ul, "scrollTop", {
    configurable: true,
    get: () => scrollTop,
    set: (v: number) => {
      scrollTop = v;
    },
  });
  Object.defineProperty(ul, "scrollHeight", {
    configurable: true,
    get: () => SCROLL_HEIGHT,
  });
  Object.defineProperty(ul, "clientHeight", {
    configurable: true,
    get: () => CLIENT_HEIGHT,
  });
  return {
    get scrollTop() {
      return scrollTop;
    },
  };
}

function getList(container: HTMLElement): HTMLUListElement {
  const ul = container.querySelector("ul");
  if (!ul) throw new Error("debug stream <ul> not found (panel not expanded or no events)");
  return ul as HTMLUListElement;
}

describe("DebugStreamPanel sticky autoscroll", () => {
  beforeEach(() => {
    // Effects use the real scheduler; nothing to fake-time here.
  });
  afterEach(() => {
    // RTL auto-cleanup via setup-dom.
  });

  it("AC4: a new entry arriving while pinned at the bottom scrolls the newest entry into view (scrollTop = scrollHeight)", () => {
    const initial = [ev({ id: "1" })];
    const { container, rerender, getByRole } = render(
      <DebugStreamPanel available events={initial} connected />,
    );
    // Expand the collapsed drawer so the <ul> mounts.
    fireEvent.click(getByRole("button", { name: /debug stream/i }));

    // Start pinned at the bottom: scrollTop already at (scrollHeight - clientHeight).
    const ul = getList(container);
    const probe = instrumentList(ul, SCROLL_HEIGHT - CLIENT_HEIGHT);

    // A new entry arrives → effect must snap scrollTop to scrollHeight.
    act(() => {
      rerender(<DebugStreamPanel available events={[...initial, ev({ id: "2" })]} connected />);
    });

    expect(probe.scrollTop).toBe(SCROLL_HEIGHT);
  });

  it("AC5: a new entry arriving while the user has scrolled up does NOT move the scroll position (no yank)", () => {
    const initial = [ev({ id: "1" })];
    const { container, rerender, getByRole } = render(
      <DebugStreamPanel available events={initial} connected />,
    );
    fireEvent.click(getByRole("button", { name: /debug stream/i }));

    const ul = getList(container);
    // User scrolled up to read history: scrollTop well above the bottom.
    const SCROLLED_UP = 100;
    const probe = instrumentList(ul, SCROLLED_UP);
    // Fire the scroll event so the component records "not at bottom".
    fireEvent.scroll(ul);

    act(() => {
      rerender(<DebugStreamPanel available events={[...initial, ev({ id: "2" })]} connected />);
    });

    // Position not yanked — autoscroll stayed off.
    expect(probe.scrollTop).toBe(SCROLLED_UP);
  });

  it("AC6: scrolling back to the bottom re-enables sticky autoscroll on the next entry", () => {
    const initial = [ev({ id: "1" })];
    const { container, rerender, getByRole } = render(
      <DebugStreamPanel available events={initial} connected />,
    );
    fireEvent.click(getByRole("button", { name: /debug stream/i }));

    const ul = getList(container);
    const probe = instrumentList(ul, 100); // scrolled up

    // 1) Scroll up → autoscroll suppressed.
    fireEvent.scroll(ul);
    act(() => {
      rerender(<DebugStreamPanel available events={[...initial, ev({ id: "2" })]} connected />);
    });
    expect(probe.scrollTop).toBe(100);

    // 2) User scrolls back to the bottom and fires scroll → sticky re-enabled.
    ul.scrollTop = SCROLL_HEIGHT - CLIENT_HEIGHT;
    fireEvent.scroll(ul);

    // 3) Next entry → autoscroll resumes (scrollTop snaps to scrollHeight).
    act(() => {
      rerender(
        <DebugStreamPanel
          available
          events={[...initial, ev({ id: "2" }), ev({ id: "3" })]}
          connected
        />,
      );
    });
    expect(probe.scrollTop).toBe(SCROLL_HEIGHT);
  });
});
