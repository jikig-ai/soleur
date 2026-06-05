import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, screen, fireEvent, waitFor } from "@testing-library/react";

// Mock the shared building blocks so we test C4Diagram's WIRING (lifted `stale`
// state + tab switch on save), not the real canvas/CodeMirror plumbing.
vi.mock("@/components/kb/c4-shared", () => ({
  Spinner: () => <div>loading</div>,
  useC4Project: () => ({
    data: { dump: { foo: 1 }, diagnostics: [], sources: { "model.c4": "x" } },
    error: null,
    loading: false,
    reload: vi.fn(),
  }),
  C4Canvas: () => <div data-testid="c4-canvas" />,
  C4Diagnostics: ({ stale }: { stale?: boolean }) => (
    <div data-testid="c4-diagnostics" data-stale={stale ? "true" : "false"} />
  ),
  C4CodePanel: ({ onSaved }: { onSaved: () => void | Promise<void> }) => (
    <button data-testid="c4-code-panel" onClick={() => void onSaved()}>
      stub-save
    </button>
  ),
}));

async function renderEmbed() {
  const { default: C4Diagram } = await import("@/components/kb/c4-diagram");
  return render(
    <C4Diagram viewId="index" dirPath="knowledge-base/diagrams" />,
  );
}

beforeEach(() => {
  vi.clearAllMocks();
});

describe("C4Diagram (inline embed) — staleness wiring (Layer 1)", () => {
  it("does not flag stale on a fresh load (no false-positive)", async () => {
    await renderEmbed();
    expect(
      screen.getByTestId("c4-diagnostics").getAttribute("data-stale"),
    ).toBe("false");
  });

  it("flags stale and returns to the Diagram tab after a source save", async () => {
    await renderEmbed();
    // Switch to the Code tab and save via the stub panel.
    fireEvent.click(screen.getByRole("button", { name: "code" }));
    fireEvent.click(screen.getByTestId("c4-code-panel"));

    // onSaved sets stale=true, reloads, and switches back to the Diagram tab.
    await waitFor(() =>
      expect(
        screen.getByTestId("c4-diagnostics").getAttribute("data-stale"),
      ).toBe("true"),
    );
    expect(screen.getByTestId("c4-canvas")).toBeTruthy();
  });
});
