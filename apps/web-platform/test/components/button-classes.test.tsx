import { describe, it, expect } from "vitest";
import { render, screen } from "@testing-library/react";
import { Button } from "@/components/ui/button";

// Guard 2 (caller-utilities-win contract), render half. The compiled-CSS half
// lives in button-layer.test.ts. happy-dom has no layout, so this asserts the
// class CONTRACT only; the Playwright bounding-box e2e is the layout gate.
//
// Match whole class tokens (split on whitespace), never substrings: `px-6` must
// not be satisfied by `md:px-6` or `min-px-6-foo`, and `soleur-btn` must not be
// satisfied by `soleur-btn-pad`.
function tokens(el: HTMLElement): string[] {
  return el.className.split(/\s+/).filter(Boolean);
}

// Classes the primitive must NEVER emit itself: as ordinary utilities they sit
// in the same cascade layer as a caller's `px-3` / `flex` / `rounded-md` and
// race it on emit order. They live in `@layer components` (globals.css).
const BASE_BOX_DENYLIST = [
  "px-6",
  "py-3",
  "rounded-lg",
  "text-sm",
  "gap-2",
  "inline-flex",
];

describe("Button class contract (caller utilities win)", () => {
  it("icon-only Button with a caller size gets the base box but NO padding", () => {
    render(
      <Button className="h-[36px] w-[36px]" aria-label="Attach file">
        <svg data-testid="glyph" />
      </Button>,
    );
    const t = tokens(screen.getByRole("button", { name: "Attach file" }));
    expect(t).toContain("soleur-btn");
    expect(t).not.toContain("soleur-btn-pad");
    expect(t).not.toContain("px-6");
    expect(t).not.toContain("py-3");
    // Caller classes are forwarded untouched.
    expect(t).toContain("h-[36px]");
    expect(t).toContain("w-[36px]");
  });

  it("text Button renders both the base box and the padding class", () => {
    render(<Button>Save</Button>);
    const t = tokens(screen.getByRole("button", { name: "Save" }));
    expect(t).toContain("soleur-btn");
    expect(t).toContain("soleur-btn-pad");
  });

  it("text Button with a caller padding class still emits soleur-btn-pad (layer order lets px-3 win)", () => {
    render(<Button className="px-3 py-1.5">Save</Button>);
    const t = tokens(screen.getByRole("button", { name: "Save" }));
    expect(t).toContain("soleur-btn-pad");
    expect(t).toContain("px-3");
    expect(t).toContain("py-1.5");
  });

  it("icon-only detection ignores whitespace-only text and nested svg", () => {
    render(
      <Button aria-label="Close">
        {"  "}
        <span>
          <svg />
        </span>
      </Button>,
    );
    const t = tokens(screen.getByRole("button", { name: "Close" }));
    expect(t).toContain("soleur-btn");
    expect(t).not.toContain("soleur-btn-pad");
  });

  it("nested text child keeps the text padding", () => {
    render(
      <Button>
        <span>Label</span>
      </Button>,
    );
    const t = tokens(screen.getByRole("button", { name: "Label" }));
    expect(t).toContain("soleur-btn-pad");
  });

  it.each(BASE_BOX_DENYLIST)(
    "the primitive itself never emits `%s` (text and icon-only)",
    (denied) => {
      render(
        <>
          <Button>Text</Button>
          <Button aria-label="Icon">
            <svg />
          </Button>
        </>,
      );
      for (const btn of screen.getAllByRole("button")) {
        expect(tokens(btn)).not.toContain(denied);
      }
    },
  );

  it("does not strip a caller's own padding/size/radius/typography/display classes", () => {
    render(
      <Button className="flex rounded-md px-2 py-1 text-xs gap-1">Go</Button>,
    );
    const t = tokens(screen.getByRole("button", { name: "Go" }));
    for (const c of ["flex", "rounded-md", "px-2", "py-1", "text-xs", "gap-1"]) {
      expect(t).toContain(c);
    }
  });
});
