import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen, cleanup } from "@testing-library/react";
import { GuidedTour } from "@/components/tour/guided-tour";
import { TOUR_STEPS } from "@/components/tour/tour-steps";
import { NAV_DRAWER_REVEAL_EVENT } from "@/components/dashboard/nav-drawer-reveal-event";

// #7326 — the guided tour never highlighted anything on a phone.
//
// `guided-tour.tsx` blanket-nulled the spotlight rect below 768px, so all of the
// steps rendered as a centred card over a flat scrim. That rule dated from when
// every step targeted a nav-rail item; ten of them now target in-page `action:*`
// anchors that are fully on screen on a phone.
//
// EVERY test here pins a PHONE viewport (390×844). happy-dom defaults to
// 1024px — the exact cell where the old code was already correct — so a test
// that forgets to shrink the viewport passes against the bug. The desktop
// discriminators are in test/components/tour/guided-tour.test.tsx and must keep
// passing: this fix must not move desktop placement.
const PHONE_W = 390;
const PHONE_H = 844;

function phone() {
  (window as unknown as { innerWidth: number }).innerWidth = PHONE_W;
  (window as unknown as { innerHeight: number }).innerHeight = PHONE_H;
}

function target(id: string, r: Partial<DOMRect>) {
  const el = document.createElement("div");
  el.setAttribute("data-tour-id", id);
  const rect = {
    top: 0,
    left: 0,
    width: 0,
    height: 0,
    x: 0,
    y: 0,
    toJSON: () => ({}),
    ...r,
  };
  el.getBoundingClientRect = () =>
    ({
      ...rect,
      right: rect.left + rect.width,
      bottom: rect.top + rect.height,
    }) as DOMRect;
  document.body.appendChild(el);
  return el;
}

function setup(stepIndex: number) {
  render(
    <GuidedTour
      stepIndex={stepIndex}
      onNext={vi.fn()}
      onBack={vi.fn()}
      onSkip={vi.fn()}
      onFinish={vi.fn()}
    />,
  );
}

/** Index of the first step whose target is the given `data-tour-id`. */
function stepFor(tourId: string) {
  const i = TOUR_STEPS.findIndex((s) => s.target === tourId);
  if (i < 0) throw new Error(`no tour step targets ${tourId}`);
  return i;
}

const spotlight = () =>
  document.querySelector('[style*="box-shadow"]') as HTMLElement | null;

describe("#7326 — the tour spotlights on-screen targets on a phone", () => {
  beforeEach(() => phone());
  afterEach(() => {
    cleanup();
    document.querySelectorAll("[data-tour-id]").forEach((el) => el.remove());
  });

  it("spotlights an in-page action target at 390px (was blanket-nulled below md)", async () => {
    // action:new-conversation — the dashboard composer, full-bleed on a phone.
    target("action:new-conversation", {
      top: 210,
      left: 16,
      width: 358,
      height: 96,
    });
    setup(stepFor("action:new-conversation"));

    const el = await vi.waitFor(() => {
      const s = spotlight();
      if (!s) throw new Error("no spotlight yet");
      return s;
    });
    expect(el.style.boxShadow).toContain("9999px");
    // Traces the target, padded by PAD=8 on every side.
    expect(parseFloat(el.style.top)).toBe(202);
    expect(parseFloat(el.style.left)).toBe(8);
    expect(parseFloat(el.style.width)).toBe(374);
    expect(parseFloat(el.style.height)).toBe(112);
  });

  it("places the card BELOW a full-bleed target instead of on top of it", async () => {
    target("action:new-conversation", {
      top: 210,
      left: 16,
      width: 358,
      height: 96,
    });
    setup(stepFor("action:new-conversation"));

    const dialog = await vi.waitFor(() => {
      const el = screen.getByRole("dialog") as HTMLElement;
      if (!el.style.top) throw new Error("not positioned yet");
      return el;
    });
    const top = parseFloat(dialog.style.top);
    // Below the spotlight's bottom edge (210 + 96 + PAD 8 + MARGIN 12 = 326).
    expect(top).toBe(326);
    // The old right→left→clamp order had no vertical branch, so on a target this
    // wide it clamped to rect.top and covered the control the copy points at.
    expect(top).toBeGreaterThan(210 + 96);
  });

  it("falls back ABOVE the target when there is no room below", async () => {
    // Target low on the screen: 844 - 700 = 144px of room below, card is ~240.
    target("action:inbox-triage", {
      top: 700,
      left: 16,
      width: 358,
      height: 100,
    });
    setup(stepFor("action:inbox-triage"));

    const dialog = await vi.waitFor(() => {
      const el = screen.getByRole("dialog") as HTMLElement;
      if (!el.style.top) throw new Error("not positioned yet");
      return el;
    });
    const top = parseFloat(dialog.style.top);
    // Card (seeded 320×240 under happy-dom) sits clear ABOVE the target.
    expect(top).toBe(700 - 8 - 12 - 240);
    expect(top).toBeGreaterThanOrEqual(12);
  });

  it("still falls back to a centered card for an OFF-SCREEN target", async () => {
    // The closed mobile nav drawer is translated off-canvas, not unmounted — so
    // the element resolves but its rect is entirely to the left of the viewport.
    // This is the case the deleted breakpoint rule used to cover by assumption;
    // the on-screen measurement has to cover it by fact.
    target("/dashboard/inbox", {
      top: 120,
      left: -256,
      width: 256,
      height: 44,
    });
    setup(stepFor("/dashboard/inbox"));

    await new Promise((r) => setTimeout(r, 50));
    expect(spotlight()).toBeNull();
    expect(screen.getByRole("dialog").className).toContain("-translate-x-1/2");
  });

  it("keeps polling a present-but-off-screen target until it slides in", async () => {
    // The drawer's slide-in is a transform transition: it changes neither size
    // nor scroll offset, so neither the ResizeObserver nor the scroll listener
    // fires. Settling for "element present" froze the fallback card for the
    // whole animation.
    let slidIn = false;
    const el = document.createElement("div");
    el.setAttribute("data-tour-id", "/dashboard/inbox");
    el.getBoundingClientRect = () => {
      const left = slidIn ? 0 : -256;
      return {
        top: 120,
        left,
        width: 256,
        height: 44,
        right: left + 256,
        bottom: 164,
        x: left,
        y: 120,
        toJSON: () => ({}),
      } as DOMRect;
    };
    document.body.appendChild(el);

    setup(stepFor("/dashboard/inbox"));
    await new Promise((r) => setTimeout(r, 30));
    expect(spotlight()).toBeNull();

    slidIn = true; // drawer finishes its transform
    const lit = await vi.waitFor(() => {
      const s = spotlight();
      if (!s) throw new Error("still not lit");
      return s;
    });
    expect(parseFloat(lit.style.left)).toBe(-8);
  });
});

describe("#7326 — nav-tab steps reveal the drawer they talk about", () => {
  it("every step targeting a sidebar tab carries the drawer reveal", () => {
    // The seven tab steps say things like "Click the Inbox tab" — on a phone
    // that tab is inside the closed drawer. `reveal` is what opens it.
    const tabSteps = TOUR_STEPS.filter((s) => s.target?.startsWith("/dashboard"));
    expect(tabSteps.length).toBe(7);
    for (const s of tabSteps) {
      expect(s.reveal, `step "${s.title}" must reveal the nav drawer`).toBe(
        NAV_DRAWER_REVEAL_EVENT,
      );
    }
  });

  it("does NOT put the drawer reveal on in-page action steps", () => {
    // An action:* target is already on screen; opening the drawer over it would
    // hide the very control being taught.
    const actionSteps = TOUR_STEPS.filter((s) => s.target?.startsWith("action:"));
    expect(actionSteps.length).toBeGreaterThan(0);
    for (const s of actionSteps) {
      expect(s.reveal).not.toBe(NAV_DRAWER_REVEAL_EVENT);
    }
  });
});
