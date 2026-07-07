import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen, fireEvent, cleanup, within } from "@testing-library/react";
import { GuidedTour } from "@/components/tour/guided-tour";
import { TOUR_STEP_COUNT } from "@/components/tour/tour-steps";

function setup(stepIndex: number) {
  const onNext = vi.fn();
  const onBack = vi.fn();
  const onSkip = vi.fn();
  const onFinish = vi.fn();
  render(
    <GuidedTour
      stepIndex={stepIndex}
      onNext={onNext}
      onBack={onBack}
      onSkip={onSkip}
      onFinish={onFinish}
    />,
  );
  return { onNext, onBack, onSkip, onFinish };
}

describe("GuidedTour overlay", () => {
  beforeEach(() => {
    (window as unknown as { innerWidth: number }).innerWidth = 1200;
  });
  afterEach(() => cleanup());

  it("Welcome step: centered card, no Back, Next + Skip, progress 1 of N", () => {
    const { onNext } = setup(0);
    const dialog = screen.getByRole("dialog");
    expect(within(dialog).getByText(/Welcome to Soleur/i)).toBeTruthy();
    expect(within(dialog).getByText(`1 of ${TOUR_STEP_COUNT}`)).toBeTruthy();
    expect(within(dialog).queryByText("Back")).toBeNull();
    expect(within(dialog).getByText("Skip")).toBeTruthy();
    fireEvent.click(within(dialog).getByText("Next"));
    expect(onNext).toHaveBeenCalledTimes(1);
  });

  it("Last step: Finish (not Next), Back present, Skip hidden", () => {
    const { onFinish, onBack } = setup(TOUR_STEP_COUNT - 1);
    const dialog = screen.getByRole("dialog");
    expect(within(dialog).getByText(`${TOUR_STEP_COUNT} of ${TOUR_STEP_COUNT}`)).toBeTruthy();
    expect(within(dialog).queryByText("Next")).toBeNull();
    expect(within(dialog).queryByText("Skip")).toBeNull();
    expect(within(dialog).getByText("Finish")).toBeTruthy();
    fireEvent.click(within(dialog).getByText("Back"));
    expect(onBack).toHaveBeenCalledTimes(1);
    fireEvent.click(within(dialog).getByText("Finish"));
    expect(onFinish).toHaveBeenCalledTimes(1);
  });

  it("Escape key calls onSkip", () => {
    const { onSkip } = setup(2);
    fireEvent.keyDown(document, { key: "Escape" });
    expect(onSkip).toHaveBeenCalledTimes(1);
  });

  it("Escape uses the LIVE onSkip after a step change (no stale closure)", () => {
    const onSkip1 = vi.fn();
    const onSkip3 = vi.fn();
    const { rerender } = render(
      <GuidedTour stepIndex={1} onNext={vi.fn()} onBack={vi.fn()} onSkip={onSkip1} onFinish={vi.fn()} />,
    );
    // Re-render at a later step with a fresh onSkip (provider recreates it per step).
    rerender(
      <GuidedTour stepIndex={3} onNext={vi.fn()} onBack={vi.fn()} onSkip={onSkip3} onFinish={vi.fn()} />,
    );
    fireEvent.keyDown(document, { key: "Escape" });
    expect(onSkip3).toHaveBeenCalledTimes(1);
    expect(onSkip1).not.toHaveBeenCalled();
  });

  it("locks body scroll while mounted and restores on unmount", () => {
    const { unmount } = (() => {
      const r = render(
        <GuidedTour stepIndex={0} onNext={vi.fn()} onBack={vi.fn()} onSkip={vi.fn()} onFinish={vi.fn()} />,
      );
      return r;
    })();
    expect(document.body.style.overflow).toBe("hidden");
    unmount();
    expect(document.body.style.overflow).not.toBe("hidden");
  });

  it("renders a box-shadow spotlight when the target is present with a real rect", async () => {
    // A spotlight step (stepIndex 1 → start-a-conversation action) with a target.
    const a = document.createElement("a");
    a.setAttribute("data-tour-id", "action:new-conversation");
    a.getBoundingClientRect = () =>
      ({ top: 100, left: 60, width: 200, height: 44, right: 260, bottom: 144, x: 60, y: 100, toJSON: () => ({}) }) as DOMRect;
    document.body.appendChild(a);
    setup(1);
    const spotlight = await vi.waitFor(() => {
      const el = document.querySelector('[style*="box-shadow"]') as HTMLElement | null;
      if (!el) throw new Error("no spotlight yet");
      return el;
    });
    expect(spotlight.style.boxShadow).toContain("9999px");
    a.remove();
  });

  it("clamps the card inside the viewport when the target hugs an edge", async () => {
    (window as unknown as { innerWidth: number }).innerWidth = 1200;
    (window as unknown as { innerHeight: number }).innerHeight = 800;
    // Target pinned to the bottom-right corner — naive placement would push the
    // card off both the right and bottom edges (the #tour-overflow bug).
    const a = document.createElement("a");
    a.setAttribute("data-tour-id", "action:new-conversation");
    a.getBoundingClientRect = () =>
      ({ top: 760, left: 1120, width: 70, height: 40, right: 1190, bottom: 800, x: 1120, y: 760, toJSON: () => ({}) }) as DOMRect;
    document.body.appendChild(a);
    setup(1);
    const dialog = await vi.waitFor(() => {
      const el = screen.getByRole("dialog") as HTMLElement;
      if (!el.style.left) throw new Error("not positioned yet");
      return el;
    });
    const left = parseFloat(dialog.style.left);
    const top = parseFloat(dialog.style.top);
    // Card (seeded 320×240 in jsdom) stays fully within the 1200×800 viewport.
    expect(left).toBeGreaterThanOrEqual(12);
    expect(left + 320).toBeLessThanOrEqual(1200);
    expect(top).toBeGreaterThanOrEqual(12);
    expect(top + 240).toBeLessThanOrEqual(800);
    a.remove();
  });
});
