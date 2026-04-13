import { describe, test, expect } from "vitest";
import { render } from "@testing-library/react";
import { UploadProgress } from "@/components/kb/upload-progress";

describe("UploadProgress", () => {
  const RADIUS = 4.5;
  const CIRCUMFERENCE = 2 * Math.PI * RADIUS;

  test("renders SVG with correct dimensions", () => {
    const { container } = render(<UploadProgress percent={50} />);
    const svg = container.querySelector("svg");
    expect(svg).toBeTruthy();
    expect(svg?.getAttribute("width")).toBe("12");
    expect(svg?.getAttribute("height")).toBe("12");
  });

  test("renders background track circle", () => {
    const { container } = render(<UploadProgress percent={0} />);
    const circles = container.querySelectorAll("circle");
    // Should have 2 circles: track + progress arc
    expect(circles.length).toBe(2);
  });

  test("at 0% progress, offset equals full circumference (no arc visible)", () => {
    const { container } = render(<UploadProgress percent={0} />);
    const circles = container.querySelectorAll("circle");
    const progressCircle = circles[1]; // second circle is the progress arc
    const dashoffset = Number(progressCircle?.getAttribute("stroke-dashoffset"));
    expect(dashoffset).toBeCloseTo(CIRCUMFERENCE, 1);
  });

  test("at 50% progress, offset equals half circumference", () => {
    const { container } = render(<UploadProgress percent={50} />);
    const circles = container.querySelectorAll("circle");
    const progressCircle = circles[1];
    const dashoffset = Number(progressCircle?.getAttribute("stroke-dashoffset"));
    expect(dashoffset).toBeCloseTo(CIRCUMFERENCE / 2, 1);
  });

  test("at 100% progress, offset equals 0 (full circle)", () => {
    const { container } = render(<UploadProgress percent={100} />);
    const circles = container.querySelectorAll("circle");
    const progressCircle = circles[1];
    const dashoffset = Number(progressCircle?.getAttribute("stroke-dashoffset"));
    expect(dashoffset).toBeCloseTo(0, 1);
  });

  test("progress arc has stroke-dasharray set to circumference", () => {
    const { container } = render(<UploadProgress percent={50} />);
    const circles = container.querySelectorAll("circle");
    const progressCircle = circles[1];
    const dasharray = Number(progressCircle?.getAttribute("stroke-dasharray"));
    expect(dasharray).toBeCloseTo(CIRCUMFERENCE, 1);
  });

  test("progress arc is rotated -90 degrees to start at 12 o'clock", () => {
    const { container } = render(<UploadProgress percent={50} />);
    const circles = container.querySelectorAll("circle");
    const progressCircle = circles[1];
    expect(progressCircle?.getAttribute("transform")).toBe("rotate(-90 6 6)");
  });

  test("at -1 (indeterminate), renders spinning animation", () => {
    const { container } = render(<UploadProgress percent={-1} />);
    const svg = container.querySelector("svg");
    // Indeterminate mode should use animate-spin class
    expect(svg?.className.baseVal || svg?.getAttribute("class")).toContain(
      "animate-spin",
    );
  });
});
