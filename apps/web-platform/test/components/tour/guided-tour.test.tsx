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
    // A spotlight step (stepIndex 1 → /dashboard) with a measurable target.
    const a = document.createElement("a");
    a.setAttribute("data-tour-id", "/dashboard");
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
});
