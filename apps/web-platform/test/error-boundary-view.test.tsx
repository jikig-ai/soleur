import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen, cleanup } from "@testing-library/react";

const { reportSilentFallbackSpy } = vi.hoisted(() => ({
  reportSilentFallbackSpy: vi.fn(),
}));

vi.mock("@/lib/client-observability", () => ({
  reportSilentFallback: reportSilentFallbackSpy,
  warnSilentFallback: vi.fn(),
}));

import { ErrorBoundaryView } from "@/components/error-boundary-view";
import RootError from "@/app/error";
import DashboardSegmentError from "@/app/(dashboard)/error";

const sampleError = Object.assign(new Error("boom"), { digest: "abc123" });

describe("ErrorBoundaryView", () => {
  beforeEach(() => {
    reportSilentFallbackSpy.mockClear();
  });

  afterEach(() => {
    cleanup();
  });

  it("emits the structured `data-error-boundary` attribute (defaults to 'root')", () => {
    const { container } = render(
      <ErrorBoundaryView
        error={sampleError}
        reset={() => {}}
        feature="root-error-boundary"
      />,
    );
    expect(
      container.querySelector('[data-error-boundary="root"]'),
    ).not.toBeNull();
  });

  it("emits `data-error-boundary='dashboard'` when segment='dashboard'", () => {
    const { container } = render(
      <ErrorBoundaryView
        error={sampleError}
        reset={() => {}}
        feature="dashboard-error-boundary"
        segment="dashboard"
      />,
    );
    expect(
      container.querySelector('[data-error-boundary="dashboard"]'),
    ).not.toBeNull();
  });

  it("calls reportSilentFallback with the per-boundary feature tag", () => {
    render(
      <ErrorBoundaryView
        error={sampleError}
        reset={() => {}}
        feature="root-error-boundary"
      />,
    );
    expect(reportSilentFallbackSpy).toHaveBeenCalledTimes(1);
    const [errArg, options] = reportSilentFallbackSpy.mock.calls[0]!;
    expect(errArg).toBe(sampleError);
    expect(options).toMatchObject({
      feature: "root-error-boundary",
      op: "render",
      extra: { digest: "abc123" },
    });
    // root boundary must NOT include `segment`
    expect(options.extra).not.toHaveProperty("segment");
  });

  it("dashboard segment boundary attaches segment='dashboard' extra", () => {
    render(
      <ErrorBoundaryView
        error={sampleError}
        reset={() => {}}
        feature="dashboard-error-boundary"
        segment="dashboard"
      />,
    );
    const [, options] = reportSilentFallbackSpy.mock.calls[0]!;
    expect(options).toMatchObject({
      feature: "dashboard-error-boundary",
      extra: { segment: "dashboard", digest: "abc123" },
    });
  });
});

// Renders the actual route boundary files end-to-end so the (dashboard) and
// root boundaries get distinct `feature` tags + segment extras. Acts as a
// regression test for the user-impact F7 finding (root must not mis-tag
// itself as 'dashboard-error-boundary').
describe("Route-segment error boundaries", () => {
  beforeEach(() => {
    reportSilentFallbackSpy.mockClear();
  });

  afterEach(() => {
    cleanup();
  });

  it("`app/error.tsx` tags feature='root-error-boundary' (no segment extra)", () => {
    render(<RootError error={sampleError} reset={() => {}} />);
    const [, options] = reportSilentFallbackSpy.mock.calls[0]!;
    expect(options.feature).toBe("root-error-boundary");
    expect(options.extra).not.toHaveProperty("segment");
  });

  it("`app/(dashboard)/error.tsx` tags feature='dashboard-error-boundary' + segment='dashboard'", () => {
    render(<DashboardSegmentError error={sampleError} reset={() => {}} />);
    const [, options] = reportSilentFallbackSpy.mock.calls[0]!;
    expect(options.feature).toBe("dashboard-error-boundary");
    expect(options.extra).toMatchObject({ segment: "dashboard" });
  });
});

describe("Sentinel: NO error-boundary marker on healthy pages", () => {
  it("a generic component without the boundary does NOT render `data-error-boundary`", () => {
    const { container } = render(<div>healthy content</div>);
    expect(
      container.querySelector("[data-error-boundary]"),
    ).toBeNull();
  });
});
