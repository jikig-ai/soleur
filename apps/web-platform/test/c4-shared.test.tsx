import { describe, it, expect, vi, beforeEach } from "vitest";
import { act, render, renderHook, screen, fireEvent, waitFor } from "@testing-library/react";

// c4-shared.tsx imports browser-only deps at module top (@likec4/diagram,
// @likec4/core/model, CodeMirror). Stub them so the REAL C4Diagnostics /
// C4CodePanel logic loads under happy-dom without pulling the canvas runtime.
vi.mock("@likec4/diagram", () => ({
  LikeC4ModelProvider: ({ children }: { children: React.ReactNode }) => (
    <div>{children}</div>
  ),
  LikeC4Diagram: () => <div data-testid="likec4-diagram" />,
  useLikeC4ViewModel: () => null,
}));
vi.mock("@likec4/core/model", () => ({
  LikeC4Model: { create: () => ({}) },
}));
vi.mock("@codemirror/theme-one-dark", () => ({ oneDark: {} }));
vi.mock("@uiw/react-codemirror", () => ({
  default: ({
    value,
    onChange,
  }: {
    value: string;
    onChange?: (v: string) => void;
  }) => (
    <textarea
      data-testid="cm"
      value={value}
      onChange={(e) => onChange?.(e.target.value)}
    />
  ),
}));

import {
  C4Diagnostics,
  C4CodePanel,
  useC4Project,
  type ProjectResponse,
} from "@/components/kb/c4-shared";

beforeEach(() => {
  vi.restoreAllMocks();
});

// The no-reason line 2 (#8695). Pinned literally here: it is user-facing copy,
// and the only no-diagnostic `rerendered:false` return is a supersede, so it
// must name that and never promise a refresh the page does not perform.
const SUPERSEDED =
  "A newer change to the diagram source was saved before this one was rendered, so this save did not update the diagram. Save again to render the latest version.";
const RATE_LIMIT_DIAG =
  "diagram not updated: GitHub's rate limit for this repository was reached. Save again in a few minutes.";

describe("C4Diagnostics — staleness indicator (Layer 1)", () => {
  it("renders nothing on a fresh load (no diagnostics, not stale)", () => {
    const { container } = render(
      <C4Diagnostics diagnostics={[]} hasModel={true} stale={false} />,
    );
    expect(container).toBeEmptyDOMElement();
    // No false-positive staleness warning on a clean load.
    expect(screen.queryByText(/out of date/i)).toBeNull();
  });

  it("shows the out-of-date warning when stale, even with no diagnostics", () => {
    render(<C4Diagnostics diagnostics={[]} hasModel={true} stale={true} />);
    expect(screen.getByText(/out of date/i)).toBeTruthy();
  });

  it("still renders diagnostics when present and not stale", () => {
    render(
      <C4Diagnostics
        diagnostics={[{ message: "bad ref", line: 3, sourceFsPath: "model.c4" }]}
        hasModel={true}
        stale={false}
      />,
    );
    expect(screen.getByText(/diagram warnings/i)).toBeTruthy();
    expect(screen.getByText(/bad ref/i)).toBeTruthy();
    expect(screen.queryByText(/out of date/i)).toBeNull();
  });
});

describe("C4Diagnostics — stale line 2 states the save diagnostic (#8695)", () => {
  it("(a) with a diagnostic: shows it capitalised, no supersede line, no refresh promise", () => {
    render(
      <C4Diagnostics
        diagnostics={[]}
        hasModel={true}
        stale={true}
        staleDiagnostic={RATE_LIMIT_DIAG}
      />,
    );
    expect(screen.getByText(/out of date/i)).toBeTruthy();
    expect(
      screen.getByText(
        "Diagram not updated: GitHub's rate limit for this repository was reached. Save again in a few minutes.",
      ),
    ).toBeTruthy();
    expect(screen.queryByText(SUPERSEDED)).toBeNull();
    expect(screen.queryByText(/precomputed/i)).toBeNull();
    expect(screen.queryByText(/will refresh|refreshes/i)).toBeNull();
  });

  it("(b) without a diagnostic: shows the supersede line, no refresh promise", () => {
    render(<C4Diagnostics diagnostics={[]} hasModel={true} stale={true} />);
    expect(screen.getByText(SUPERSEDED)).toBeTruthy();
    expect(screen.queryByText(/will refresh|refreshes|precomputed/i)).toBeNull();
  });

  it("(b') an empty-string or null diagnostic falls back to the supersede line", () => {
    const { rerender } = render(
      <C4Diagnostics
        diagnostics={[]}
        hasModel={true}
        stale={true}
        staleDiagnostic=""
      />,
    );
    expect(screen.getByText(SUPERSEDED)).toBeTruthy();
    rerender(
      <C4Diagnostics
        diagnostics={[]}
        hasModel={true}
        stale={true}
        staleDiagnostic={null}
      />,
    );
    expect(screen.getByText(SUPERSEDED)).toBeTruthy();
  });

  it("(c) not stale with a leftover diagnostic: renders nothing", () => {
    const { container } = render(
      <C4Diagnostics
        diagnostics={[]}
        hasModel={true}
        stale={false}
        staleDiagnostic={RATE_LIMIT_DIAG}
      />,
    );
    expect(container).toBeEmptyDOMElement();
  });

  it("(d) a diagnostic containing markup renders as literal text, never an element", () => {
    const { container } = render(
      <C4Diagnostics
        diagnostics={[]}
        hasModel={true}
        stale={true}
        staleDiagnostic="diagram not updated: <script>alert(1)</script><img src=x onerror=alert(2)>"
      />,
    );
    expect(container.querySelector("script")).toBeNull();
    expect(container.querySelector("img")).toBeNull();
    expect(
      screen.getByText(
        "Diagram not updated: <script>alert(1)</script><img src=x onerror=alert(2)>",
      ),
    ).toBeTruthy();
  });
});

// #8740: a model-level diagnostic (the zero-view model) has no source line.
describe("C4Diagnostics — model-level diagnostics carry no line prefix", () => {
  it.each([0, -1])("S1: line %i renders the message alone under the warnings header", (line) => {
    render(
      <C4Diagnostics
        diagnostics={[{ message: "M", line, sourceFsPath: "model.likec4.json" }]}
        hasModel={true}
      />,
    );
    expect(screen.getByText("Diagram warnings")).toBeTruthy();
    expect(screen.queryByText(/Diagram has errors/)).toBeNull();
    const items = screen.getAllByRole("listitem");
    expect(items).toHaveLength(1);
    expect(items[0].textContent).toBe("M");
    expect(screen.queryByText(/line -?\d/)).toBeNull();
  });

  it("S2: a positive line keeps the `line N:` prefix", () => {
    render(
      <C4Diagnostics
        diagnostics={[{ message: "bad ref", line: 3, sourceFsPath: "model.c4" }]}
        hasModel={true}
      />,
    );
    expect(screen.getAllByRole("listitem")[0].textContent).toBe("line 3: bad ref");
  });
});

describe("C4CodePanel — honest save copy (Layer 1)", () => {
  const data: ProjectResponse = {
    dir: "knowledge-base/diagrams",
    sources: { "model.c4": "specification {}" },
    dump: { foo: 1 },
    viewIds: ["index"],
    diagnostics: [],
  };

  it("on a successful re-render: copy says diagram updated, onSaved(true) (Layer 2)", async () => {
    global.fetch = vi
      .fn()
      .mockResolvedValue({
        ok: true,
        json: async () => ({ commitSha: "x", rerendered: true }),
      }) as unknown as typeof fetch;
    const onSaved = vi.fn().mockResolvedValue(undefined);

    render(
      <C4CodePanel data={data} dirPath="knowledge-base/diagrams" onSaved={onSaved} />,
    );
    fireEvent.change(screen.getByTestId("cm"), {
      target: { value: "model { edited }" },
    });
    fireEvent.click(screen.getByRole("button", { name: /^save$/i }));

    await waitFor(() => expect(onSaved).toHaveBeenCalledWith(true));
    // The source PUT still fires (no regression to the write path).
    expect(global.fetch).toHaveBeenCalledWith(
      "/api/kb/c4/knowledge-base/diagrams/model.c4",
      expect.objectContaining({ method: "PUT" }),
    );
    expect(screen.getByText(/diagram updated/i)).toBeTruthy();
    // No "re-rendering…" present-progressive lie.
    expect(screen.queryByText(/re-rendering/i)).toBeNull();
  });

  it("on a failed re-render: copy defers, onSaved(false) (Layer 2)", async () => {
    global.fetch = vi
      .fn()
      .mockResolvedValue({
        ok: true,
        json: async () => ({ commitSha: "x", rerendered: false }),
      }) as unknown as typeof fetch;
    const onSaved = vi.fn().mockResolvedValue(undefined);

    render(
      <C4CodePanel data={data} dirPath="knowledge-base/diagrams" onSaved={onSaved} />,
    );
    fireEvent.change(screen.getByTestId("cm"), {
      target: { value: "model { edited }" },
    });
    fireEvent.click(screen.getByRole("button", { name: /^save$/i }));

    // No diagnostic → exactly ONE arg (toHaveBeenCalledWith compares all args).
    await waitFor(() => expect(onSaved).toHaveBeenCalledWith(false));
    // #8695: the only no-diagnostic failure is a supersede — say so, and do not
    // promise an update the page never performs.
    expect(
      screen.getByText(
        "Saved — a newer change was saved before this one was rendered.",
      ),
    ).toBeTruthy();
    expect(screen.queryByText(/after re-render/i)).toBeNull();
  });

  it("on a failed re-render WITH a diagnostic: copy shows the reason (#4966)", async () => {
    global.fetch = vi
      .fn()
      .mockResolvedValue({
        ok: true,
        json: async () => ({
          commitSha: "x",
          rerendered: false,
          rerenderDiagnostic:
            "Re-render failed: Could not resolve reference to ElementKind named 'container' (is spec.c4 present?)",
        }),
      }) as unknown as typeof fetch;
    const onSaved = vi.fn().mockResolvedValue(undefined);

    render(
      <C4CodePanel data={data} dirPath="knowledge-base/diagrams" onSaved={onSaved} />,
    );
    fireEvent.change(screen.getByTestId("cm"), {
      target: { value: "model { edited }" },
    });
    fireEvent.click(screen.getByRole("button", { name: /^save$/i }));

    // #8695: the diagnostic is threaded to the parent so the stale banner can
    // show it (the embedded viewer unmounts this panel on save).
    await waitFor(() =>
      expect(onSaved).toHaveBeenCalledWith(
        false,
        "Re-render failed: Could not resolve reference to ElementKind named 'container' (is spec.c4 present?)",
      ),
    );
    // The actionable diagnostic replaces the generic no-diagnostic copy.
    expect(screen.getByText(/Could not resolve reference/i)).toBeTruthy();
    expect(screen.getByText(/is spec\.c4 present/i)).toBeTruthy();
  });

  it("#8695: Save stays reachable for an unchanged file while the diagram is stale (the banner says 'Save again')", () => {
    const { rerender } = render(
      <C4CodePanel data={data} dirPath="knowledge-base/diagrams" onSaved={vi.fn()} />,
    );
    const save = () => screen.getByRole("button", { name: /^save$/i }) as HTMLButtonElement;
    // Unchanged and not stale: nothing to save.
    expect(save().disabled).toBe(true);
    rerender(
      <C4CodePanel data={data} dirPath="knowledge-base/diagrams" onSaved={vi.fn()} allowResave />,
    );
    expect(save().disabled).toBe(false);
  });
});

describe("useC4Project — a response for a folder the page has left is discarded", () => {
  it("a reload bound to folder A that resolves after navigating to B does not overwrite B's data", async () => {
    const byDir: Record<string, string> = { A: "a-source", B: "b-source" };
    global.fetch = vi.fn(async (url: string) => {
      const dir = decodeURIComponent(String(url).split("dir=")[1]);
      return { ok: true, json: async () => ({ dir, sources: { "model.c4": byDir[dir] } }) };
    }) as unknown as typeof fetch;
    const { result, rerender } = renderHook(({ dir }) => useC4Project(dir), {
      initialProps: { dir: "A" },
    });
    await waitFor(() => expect(result.current.data?.dir).toBe("A"));
    const reloadForA = result.current.reload;
    rerender({ dir: "B" });
    await waitFor(() => expect(result.current.data?.dir).toBe("B"));
    await act(async () => {
      await reloadForA();
    });
    expect(result.current.data?.dir).toBe("B");
    expect(result.current.data?.sources["model.c4"]).toBe("b-source");
  });
});
