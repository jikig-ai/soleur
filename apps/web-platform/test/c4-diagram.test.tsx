import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, screen, fireEvent, waitFor } from "@testing-library/react";
import { FeatureFlagProvider } from "@/components/feature-flags/provider";
import type { FlagName } from "@/lib/feature-flags/server";

function flagSnapshot(c4Edit: boolean): Record<FlagName, boolean> {
  return {
    "dev-signin": false,
    "kb-chat-sidebar": false,
    "team-workspace-invite": false,
    "byok-delegations": false,
    "c4-visualizer": false,
    "debug-mode": false,
    "c4-edit": c4Edit,
  };
}

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
  C4CodePanel: ({
    onSaved,
  }: {
    onSaved: (rerendered: boolean) => void | Promise<void>;
  }) => (
    <>
      <button data-testid="c4-save-ok" onClick={() => void onSaved(true)}>
        save-ok
      </button>
      <button data-testid="c4-save-fail" onClick={() => void onSaved(false)}>
        save-fail
      </button>
    </>
  ),
}));

async function renderEmbed(c4Edit = true, readOnly = false) {
  const { default: C4Diagram } = await import("@/components/kb/c4-diagram");
  return render(
    <FeatureFlagProvider flags={flagSnapshot(c4Edit)}>
      <C4Diagram viewId="index" dirPath="knowledge-base/diagrams" readOnly={readOnly} />
    </FeatureFlagProvider>,
  );
}

beforeEach(() => {
  vi.clearAllMocks();
});

describe("C4Diagram (inline embed) — staleness wiring (Layer 2)", () => {
  it("does not flag stale on a fresh load (no false-positive)", async () => {
    await renderEmbed();
    expect(
      screen.getByTestId("c4-diagnostics").getAttribute("data-stale"),
    ).toBe("false");
  });

  it("a successful re-render returns to the Diagram tab WITHOUT a stale banner", async () => {
    await renderEmbed();
    fireEvent.click(screen.getByRole("button", { name: "code" }));
    fireEvent.click(screen.getByTestId("c4-save-ok"));

    // onSaved reloads, sets stale=false (re-render succeeded), switches to Diagram.
    await waitFor(() => expect(screen.getByTestId("c4-canvas")).toBeTruthy());
    expect(
      screen.getByTestId("c4-diagnostics").getAttribute("data-stale"),
    ).toBe("false");
  });

  it("a failed re-render flags stale", async () => {
    await renderEmbed();
    fireEvent.click(screen.getByRole("button", { name: "code" }));
    fireEvent.click(screen.getByTestId("c4-save-fail"));

    await waitFor(() =>
      expect(
        screen.getByTestId("c4-diagnostics").getAttribute("data-stale"),
      ).toBe("true"),
    );
  });
});

describe("C4Diagram (inline embed) — c4-edit flag gates the Code tab (AC4)", () => {
  it("AC4: flag OFF ⇒ only the Diagram tab, no Code tab, no C4CodePanel", async () => {
    await renderEmbed(false);
    expect(screen.queryByRole("button", { name: "code" })).toBeNull();
    expect(screen.getByRole("button", { name: "diagram" })).toBeTruthy();
    expect(screen.queryByTestId("c4-save-ok")).toBeNull();
  });

  it("AC4: flag ON ⇒ the Code tab is present", async () => {
    await renderEmbed(true);
    expect(screen.getByRole("button", { name: "code" })).toBeTruthy();
  });

  it("AC4: composes with readOnly — readOnly + flag ON still hides the Code tab", async () => {
    await renderEmbed(true, true);
    expect(screen.queryByRole("button", { name: "code" })).toBeNull();
  });
});
