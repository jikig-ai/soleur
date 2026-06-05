import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, screen, fireEvent, waitFor } from "@testing-library/react";

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
  type ProjectResponse,
} from "@/components/kb/c4-shared";

beforeEach(() => {
  vi.restoreAllMocks();
});

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

describe("C4CodePanel — honest save copy (Layer 1)", () => {
  const data: ProjectResponse = {
    dir: "knowledge-base/diagrams",
    sources: { "model.c4": "specification {}" },
    dump: { foo: 1 },
    viewIds: ["index"],
    diagnostics: [],
  };

  it("does NOT claim the diagram re-renders after a successful save", async () => {
    global.fetch = vi
      .fn()
      .mockResolvedValue({ ok: true, json: async () => ({}) }) as unknown as typeof fetch;
    const onSaved = vi.fn().mockResolvedValue(undefined);

    render(
      <C4CodePanel
        data={data}
        dirPath="knowledge-base/diagrams"
        onSaved={onSaved}
      />,
    );

    // Make the draft dirty so Save enables, then save.
    fireEvent.change(screen.getByTestId("cm"), {
      target: { value: "specification { edited }" },
    });
    fireEvent.click(screen.getByRole("button", { name: /^save$/i }));

    await waitFor(() => expect(onSaved).toHaveBeenCalled());
    // The source PUT still fires (no regression to the write path).
    expect(global.fetch).toHaveBeenCalledWith(
      "/api/kb/c4/knowledge-base/diagrams/model.c4",
      expect.objectContaining({ method: "PUT" }),
    );
    // The old lie is gone; honest copy is shown.
    expect(screen.queryByText(/re-rendering/i)).toBeNull();
    expect(screen.getByText(/saved/i)).toBeTruthy();
  });
});
