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

// The README branch renders through MarkdownRenderer. Stub it so the test can
// assert (a) it rendered with the README content and (b) the CodeMirror mock
// did NOT render in the same state — without pulling react-markdown.
vi.mock("@/components/ui/markdown-renderer", () => ({
  MarkdownRenderer: ({ content }: { content: string }) => (
    <div data-testid="md">{content}</div>
  ),
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

// Multi-file fixture (spec.c4 / model.c4 / views.c4 / README.md) for the
// dropdown + README-surfacing tests. Default selection must still land on
// model.c4 even though it is not first in key order.
function fakeMultiFileProject(): ProjectResponse {
  return {
    dir: "knowledge-base/diagrams",
    sources: {
      "spec.c4": "specification {\n  element system\n}",
      "model.c4": "model {\n  user = element\n}",
      "views.c4": "views {\n  view index {}\n}",
      "README.md": "# Diagrams\n\nThis directory holds the C4 sources.",
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

function renderPanelWith(
  data: ProjectResponse,
  theme: "light" | "dark" = "dark",
) {
  document.documentElement.setAttribute("data-theme", theme);
  return render(
    <C4CodePanel
      data={data}
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
  // Exception-safe restore of any globalThis.fetch spy — a mid-test assertion
  // throw would otherwise leak the spy into sibling tests.
  vi.restoreAllMocks();
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

describe("C4CodePanel — dropdown file selector (AC2/AC3)", () => {
  it("AC2: renders a single accessible <select> listing every source key", () => {
    renderPanelWith(fakeMultiFileProject());
    const select = screen.getByRole("combobox", {
      name: /select c4 source file/i,
    }) as HTMLSelectElement;
    const optionValues = Array.from(select.options).map((o) => o.value);
    expect(optionValues).toEqual([
      "spec.c4",
      "model.c4",
      "views.c4",
      "README.md",
    ]);
  });

  it("AC3: the selector defaults to model.c4 even when not first in key order", () => {
    renderPanelWith(fakeMultiFileProject());
    const select = screen.getByRole("combobox", {
      name: /select c4 source file/i,
    }) as HTMLSelectElement;
    expect(select.value).toBe("model.c4");
  });

  it("AC2: changing the selection loads the chosen source into the editor", () => {
    renderPanelWith(fakeMultiFileProject());
    const select = screen.getByRole("combobox", {
      name: /select c4 source file/i,
    });
    fireEvent.change(select, { target: { value: "views.c4" } });
    expect((screen.getByTestId("cm") as HTMLTextAreaElement).value).toBe(
      "views {\n  view index {}\n}",
    );
  });

  it("AC1: the header no longer wraps (single non-wrapping row)", () => {
    const { container } = renderPanelWith(fakeMultiFileProject());
    const header = container.querySelector("div.flex.items-center");
    expect(header).not.toBeNull();
    expect(header?.className).not.toContain("flex-wrap");
  });
});

describe("C4CodePanel — README surfaced read-only (AC7)", () => {
  it("selecting README.md renders MarkdownRenderer, not the editor, with no Save", () => {
    renderPanelWith(fakeMultiFileProject());
    fireEvent.change(
      screen.getByRole("combobox", { name: /select c4 source file/i }),
      { target: { value: "README.md" } },
    );
    // README content is rendered via the markdown renderer…
    const md = screen.getByTestId("md");
    expect(md.textContent).toContain("This directory holds the C4 sources.");
    // …the CodeMirror editor is NOT mounted…
    expect(screen.queryByTestId("cm")).toBeNull();
    // …and there is no Save button for the read-only doc.
    expect(screen.queryByRole("button", { name: /^save$/i })).toBeNull();
  });

  it("switching back to a .c4 file restores the editor and Save", () => {
    renderPanelWith(fakeMultiFileProject());
    const select = screen.getByRole("combobox", {
      name: /select c4 source file/i,
    });
    fireEvent.change(select, { target: { value: "README.md" } });
    expect(screen.queryByTestId("cm")).toBeNull();
    fireEvent.change(select, { target: { value: "spec.c4" } });
    expect(screen.getByTestId("cm")).toBeTruthy();
    expect(screen.getByRole("button", { name: /^save$/i })).toBeTruthy();
  });
});

const OLD_SOURCE = "model {\n  // a note\n  user = element\n}";
const NEW_SOURCE = "model {\n  // a note\n  user = element TEST\n}";
const EXTERNAL_SOURCE = "model {\n  // edited elsewhere\n  user = element X\n}";

function mockFetchOnce(status: number, body: Record<string, unknown>) {
  return vi.spyOn(globalThis, "fetch").mockResolvedValue({
    ok: status >= 200 && status < 300,
    status,
    json: async () => body,
  } as Response);
}

function project(source: string): ProjectResponse {
  return {
    dir: "knowledge-base/diagrams",
    sources: { "model.c4": source },
    dump: null,
    viewIds: [],
    diagnostics: [],
  };
}

// F-A1 + F-B: a successful Save must NOT be reverted by a subsequent stale
// reload(), and a failed Save must surface honestly without discarding the edit.
// The revert mechanism is the [data, activeFile] effect re-seeding `draft` from
// `data.sources` — when the on-disk clone GET /project reads is stale (diverged
// clone / Contents-API→fetch replica lag), that source is the PRE-edit text.
describe("C4CodePanel — save persistence (F-A1 / F-B)", () => {
  it("F-A1: a 200 save survives a stale reload(), then external edits apply once the clone catches up", async () => {
    mockFetchOnce(200, { rerendered: true, commitSha: "abc" });
    const onSaved = vi.fn();
    // The parent re-fetches after onSaved; each render gets a fresh object so the
    // [data, activeFile] effect re-fires (mirrors useC4Project's setData).
    const { rerender } = render(
      <C4CodePanel
        data={project(OLD_SOURCE)}
        dirPath="knowledge-base/diagrams"
        onSaved={onSaved}
      />,
    );
    fireEvent.change(screen.getByTestId("cm"), {
      target: { value: NEW_SOURCE },
    });
    fireEvent.click(screen.getByRole("button", { name: /save/i }));
    await screen.findByText(/Saved/);
    // Positive control: the 200 path called onSaved(true) — proves the spy is
    // wired, so F-B's `not.toHaveBeenCalled()` is a meaningful assertion.
    expect(onSaved).toHaveBeenCalledWith(true);

    // Parent reload returns the STALE clone (new object ref, pre-edit content).
    rerender(
      <C4CodePanel
        data={project(OLD_SOURCE)}
        dirPath="knowledge-base/diagrams"
        onSaved={onSaved}
      />,
    );
    // The editor must still show the saved text, not snap back to OLD_SOURCE.
    expect((screen.getByTestId("cm") as HTMLTextAreaElement).value).toBe(
      NEW_SOURCE,
    );
    // And the just-saved content is no longer "dirty" — Save re-disables.
    expect(
      (screen.getByRole("button", { name: /save/i }) as HTMLButtonElement)
        .disabled,
    ).toBe(true);

    // Clone catches up (incoming === optimistic) → the marker clears (c4-shared
    // :419). A SUBSEQUENT external edit must now apply normally rather than being
    // masked by the stale optimistic value.
    rerender(
      <C4CodePanel
        data={project(NEW_SOURCE)}
        dirPath="knowledge-base/diagrams"
        onSaved={onSaved}
      />,
    );
    rerender(
      <C4CodePanel
        data={project(EXTERNAL_SOURCE)}
        dirPath="knowledge-base/diagrams"
        onSaved={onSaved}
      />,
    );
    expect((screen.getByTestId("cm") as HTMLTextAreaElement).value).toBe(
      EXTERNAL_SOURCE,
    );
  });

  it("F-B: a 500 SYNC_FAILED shows the error and keeps the edited draft", async () => {
    mockFetchOnce(500, {
      error: "Workspace sync failed",
      code: "SYNC_FAILED",
    });
    const onSaved = vi.fn();
    render(
      <C4CodePanel
        data={project(OLD_SOURCE)}
        dirPath="knowledge-base/diagrams"
        onSaved={onSaved}
      />,
    );
    fireEvent.change(screen.getByTestId("cm"), {
      target: { value: NEW_SOURCE },
    });
    fireEvent.click(screen.getByRole("button", { name: /save/i }));
    // The error only renders in the catch block — i.e. AFTER the save await
    // chain has fully settled, so a synchronous assertion below is not racy.
    await screen.findByText(/Workspace sync failed/);
    // The edited draft is retained (no revert) and onSaved (which triggers the
    // reload) is never called on a non-2xx.
    expect((screen.getByTestId("cm") as HTMLTextAreaElement).value).toBe(
      NEW_SOURCE,
    );
    expect(onSaved).not.toHaveBeenCalled();
  });
});
