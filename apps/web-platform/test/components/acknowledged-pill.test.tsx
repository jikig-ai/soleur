import { describe, it, expect } from "vitest";
import { render } from "@testing-library/react";

import { AcknowledgedPill } from "@/components/dashboard/acknowledged-pill";

// #11212 — the `enqueue_failed` / "queued" pill variant was dead (no consumer
// passes it; the route hook narrows `degraded` to "no_artifact_in_pr_a" |
// undefined). The deletion is pinned at the type level: re-widening the prop
// makes the `@ts-expect-error` below unused, which `tsc --noEmit` rejects
// (vitest alone cannot see it). The directive must sit on the line directly
// above the offending prop line.

describe("AcknowledgedPill — removed queued variant (#11212)", () => {
  it("rejects degraded=\"enqueue_failed\" at the type level", () => {
    render(
      <AcknowledgedPill
        artifactUrl=""
        // @ts-expect-error — "enqueue_failed" is no longer a valid degraded value
        degraded="enqueue_failed"
      />,
    );
  });

  it.each([
    ["no_artifact", "", "no_artifact_in_pr_a" as const],
    ["pending", "", undefined],
    ["ack", "https://github.com/o/r/pull/1", undefined],
  ])("renders no queued pill for the %s state", (_state, artifactUrl, degraded) => {
    const { container } = render(
      <AcknowledgedPill artifactUrl={artifactUrl} degraded={degraded} />,
    );
    expect(container.querySelector('[data-pill-state="queued"]')).toBeNull();
    expect(container.querySelector('[data-pill-state="' + _state + '"]')).not.toBeNull();
  });
});
