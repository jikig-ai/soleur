import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen, fireEvent, cleanup } from "@testing-library/react";
import type { ReactCodeMirrorProps } from "@uiw/react-codemirror";

// Capture the props the editor is mounted with so we can assert wiring
// (extensions array, theme, value, onChange) without asking happy-dom to lay
// out CodeMirror's contenteditable — happy-dom does not run CodeMirror layout,
// so DOM-measured pixel sizes are meaningless. We assert PROPS, not pixels.
let lastProps: ReactCodeMirrorProps | null = null;
vi.mock("@uiw/react-codemirror", () => ({
  __esModule: true,
  default: (props: ReactCodeMirrorProps) => {
    lastProps = props;
    return (
      <textarea
        data-testid="cm"
        value={props.value}
        onChange={(e) => props.onChange?.(e.target.value, {} as never)}
      />
    );
  },
}));

// @likec4/diagram is canvas/browser-only; C4CodePanel does not use it, but it is
// imported at module scope in c4-shared.tsx. Stub it so the import is cheap.
vi.mock("@likec4/diagram", () => ({
  LikeC4ModelProvider: ({ children }: { children: React.ReactNode }) => (
    <div>{children}</div>
  ),
  LikeC4Diagram: () => <div />,
  useLikeC4ViewModel: () => null,
}));
vi.mock("@likec4/core/model", () => ({
  LikeC4Model: { create: () => null },
}));

import { C4CodePanel, type ProjectResponse } from "@/components/kb/c4-shared";
import { c4SyntaxExtensions } from "@/components/kb/c4-code-syntax";

function fakeProject(): ProjectResponse {
  return {
    dir: "knowledge-base/diagrams",
    sources: {
      "model.c4": "model {\n  // a note\n  user = element\n}",
    },
    dump: null,
    viewIds: [],
    diagnostics: [],
  };
}

function renderPanel(theme: "light" | "dark" = "dark") {
  document.documentElement.setAttribute("data-theme", theme);
  return render(
    <C4CodePanel
      data={fakeProject()}
      dirPath="knowledge-base/diagrams"
      onSaved={vi.fn()}
    />,
  );
}

beforeEach(() => {
  lastProps = null;
  vi.clearAllMocks();
});
afterEach(() => {
  cleanup();
  document.documentElement.removeAttribute("data-theme");
});

describe("C4CodePanel — zoom controls (AC1/AC2/AC3)", () => {
  it("AC2: renders zoom out / reset / zoom in controls with aria-labels", () => {
    renderPanel();
    expect(screen.getByLabelText("Decrease code font size")).toBeTruthy();
    expect(screen.getByLabelText("Increase code font size")).toBeTruthy();
    expect(screen.getByLabelText("Reset code font size")).toBeTruthy();
  });

  it("AC1: the size label defaults to 12px", () => {
    renderPanel();
    expect(screen.getByLabelText("Reset code font size").textContent).toBe(
      "12px",
    );
  });

  it("AC2: clicking increase steps the size label up by 1px", () => {
    renderPanel();
    fireEvent.click(screen.getByLabelText("Increase code font size"));
    expect(screen.getByLabelText("Reset code font size").textContent).toBe(
      "13px",
    );
  });

  it("AC2: reset returns the size to 12px", () => {
    renderPanel();
    fireEvent.click(screen.getByLabelText("Increase code font size"));
    fireEvent.click(screen.getByLabelText("Increase code font size"));
    expect(screen.getByLabelText("Reset code font size").textContent).toBe(
      "14px",
    );
    fireEvent.click(screen.getByLabelText("Reset code font size"));
    expect(screen.getByLabelText("Reset code font size").textContent).toBe(
      "12px",
    );
  });

  it("AC3: decrease clamps at 10px and disables the button", () => {
    renderPanel();
    const dec = screen.getByLabelText(
      "Decrease code font size",
    ) as HTMLButtonElement;
    // 12 → 11 → 10, then floor.
    for (let i = 0; i < 6; i++) fireEvent.click(dec);
    expect(screen.getByLabelText("Reset code font size").textContent).toBe(
      "10px",
    );
    expect(dec.disabled).toBe(true);
  });

  it("AC3: increase clamps at 24px and disables the button", () => {
    renderPanel();
    const inc = screen.getByLabelText(
      "Increase code font size",
    ) as HTMLButtonElement;
    for (let i = 0; i < 20; i++) fireEvent.click(inc);
    expect(screen.getByLabelText("Reset code font size").textContent).toBe(
      "24px",
    );
    expect(inc.disabled).toBe(true);
  });
});

describe("C4CodePanel — editor wiring (AC4/AC6)", () => {
  it("AC4: passes the syntax extension + font-size theme to CodeMirror", () => {
    renderPanel();
    const exts = (lastProps?.extensions ?? []) as unknown[];
    // Assert the real syntax extension is wired (by reference) — not just that
    // *some* array of length 2 was passed, which would survive two stub entries.
    expect(exts).toContain(c4SyntaxExtensions);
    expect(exts.length).toBe(2); // syntax extension + font-size theme
  });

  it("AC4: zooming rebuilds the extensions (font theme tracks zoom)", () => {
    renderPanel();
    const before = lastProps?.extensions;
    fireEvent.click(screen.getByLabelText("Increase code font size"));
    expect(lastProps?.extensions).not.toBe(before);
  });

  it("AC6: chrome theme flips with data-theme; syntax extensions apply in both", () => {
    renderPanel("light");
    // Light → default chrome (no oneDark), but syntax/font extensions still apply.
    expect(lastProps?.theme).toBeUndefined();
    expect((lastProps?.extensions ?? []) as unknown[]).toContain(
      c4SyntaxExtensions,
    );
    cleanup();
    renderPanel("dark");
    // Dark → oneDark chrome theme is passed; extensions are theme-independent.
    expect(lastProps?.theme).toBeTruthy();
    expect((lastProps?.extensions ?? []) as unknown[]).toContain(
      c4SyntaxExtensions,
    );
  });
});

describe("C4CodePanel — save path unchanged (AC7)", () => {
  it("edit enables Save; pristine state keeps it disabled", () => {
    renderPanel();
    const save = screen.getByRole("button", {
      name: /save/i,
    }) as HTMLButtonElement;
    expect(save.disabled).toBe(true);
    fireEvent.change(screen.getByTestId("cm"), {
      target: { value: "model { changed }" },
    });
    expect(save.disabled).toBe(false);
  });
});
