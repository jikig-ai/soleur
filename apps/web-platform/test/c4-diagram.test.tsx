import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, screen, fireEvent, waitFor, act } from "@testing-library/react";
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
    "command-palette": false,
    support: false,
    "support-live": false,
    "guided-tour": false,
    "codex-engine": false,
  };
}

// Shared spy so the #8739 event tests can assert refetch.
const embedReload = vi.hoisted(() => vi.fn(async () => {}));

// Mock the shared building blocks so we test C4Diagram's WIRING (lifted `stale`
// state + tab switch on save), not the real canvas/CodeMirror plumbing.
vi.mock("@/components/kb/c4-shared", async () => {
  // #8695: the REAL banner (light module, no canvas/CodeMirror) wrapped in a div
  // that exposes the lifted props — attributes for wiring, real text for copy.
  const { C4Diagnostics: RealC4Diagnostics } = await import(
    "@/components/kb/c4-diagnostics"
  );
  return {
    Spinner: () => <div>loading</div>,
    useC4Project: () => ({
      data: { dump: { foo: 1 }, diagnostics: [], sources: { "model.c4": "x" } },
      error: null,
      loading: false,
      reload: embedReload,
    }),
    C4Canvas: () => <div data-testid="c4-canvas" />,
    C4Diagnostics: (props: React.ComponentProps<typeof RealC4Diagnostics>) => (
      <div
        data-testid="c4-diagnostics"
        data-stale={props.stale ? "true" : "false"}
        data-stale-diagnostic={props.staleDiagnostic ?? ""}
      >
        <RealC4Diagnostics {...props} />
      </div>
    ),
    C4CodePanel: ({
      onSaved,
    }: {
      onSaved: (
        rerendered: boolean,
        diagnostic?: string,
      ) => void | Promise<void>;
    }) => (
      <>
        <button data-testid="c4-save-ok" onClick={() => void onSaved(true)}>
          save-ok
        </button>
        <button data-testid="c4-save-fail" onClick={() => void onSaved(false)}>
          save-fail
        </button>
        <button
          data-testid="c4-save-fail-diag"
          onClick={() => void onSaved(false, "diagram not updated: x")}
        >
          save-fail-diag
        </button>
      </>
    ),
  };
});

// The copy itself is pinned literally in c4-shared.test.tsx.
const { SUPERSEDED_LINE: SUPERSEDED } = await import("@/components/kb/c4-diagnostics");

async function renderEmbed(c4Edit = true, readOnly = false, dirPath = DIR) {
  const { default: C4Diagram } = await import("@/components/kb/c4-diagram");
  return render(
    <FeatureFlagProvider flags={flagSnapshot(c4Edit)}>
      <C4Diagram viewId="index" dirPath={dirPath} readOnly={readOnly} />
    </FeatureFlagProvider>,
  );
}

// Production dirPath shape: KB-relative dirname, no `knowledge-base/` prefix.
const DIR = "engineering/architecture/diagrams";
// The DOM event ws-client re-broadcasts on a c4_diagram_saved frame (#8739).
const { C4_DIAGRAM_SAVED_EVENT } = await import("@/lib/c4-constants");

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

describe("C4Diagram (inline embed) — stale reason survives the tab switch (#8695)", () => {
  it("after a failed save WITH a reason, the Diagram tab's banner shows it; later saves clear/replace it", async () => {
    await renderEmbed();
    const banner = () => screen.getByTestId("c4-diagnostics");

    fireEvent.click(screen.getByRole("button", { name: "code" }));
    fireEvent.click(screen.getByTestId("c4-save-fail-diag"));
    // onSaved switches to the Diagram tab, unmounting C4CodePanel and its
    // `Saved — <diagnostic>` message: the banner is the only surface left.
    await waitFor(() => expect(screen.getByTestId("c4-canvas")).toBeTruthy());
    await waitFor(() =>
      expect(screen.getByText("Diagram not updated: x")).toBeTruthy(),
    );
    expect(screen.queryByTestId("c4-save-ok")).toBeNull();
    expect(banner().getAttribute("data-stale")).toBe("true");
    expect(banner().getAttribute("data-stale-diagnostic")).toBe(
      "diagram not updated: x",
    );

    // A following successful save clears it.
    fireEvent.click(screen.getByRole("button", { name: "code" }));
    fireEvent.click(screen.getByTestId("c4-save-ok"));
    await waitFor(() =>
      expect(banner().getAttribute("data-stale")).toBe("false"),
    );
    expect(banner().getAttribute("data-stale-diagnostic")).toBe("");
    expect(screen.queryByText("Diagram not updated: x")).toBeNull();

    // Reason again, then a no-reason failure replaces it with the supersede line.
    fireEvent.click(screen.getByRole("button", { name: "code" }));
    fireEvent.click(screen.getByTestId("c4-save-fail-diag"));
    await waitFor(() =>
      expect(screen.getByText("Diagram not updated: x")).toBeTruthy(),
    );
    fireEvent.click(screen.getByRole("button", { name: "code" }));
    fireEvent.click(screen.getByTestId("c4-save-fail"));
    await waitFor(() => expect(screen.getByText(SUPERSEDED)).toBeTruthy());
    expect(screen.getByTestId("c4-canvas")).toBeTruthy();
    expect(banner().getAttribute("data-stale-diagnostic")).toBe("");
    expect(screen.queryByText("Diagram not updated: x")).toBeNull();
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

describe("C4Diagram (inline embed) — c4_diagram_saved notice (#8739)", () => {
  async function fireSaved(detail: {
    dirPath: string;
    rerendered: boolean;
    diagnostic?: string | null;
  }) {
    await act(async () => {
      window.dispatchEvent(new CustomEvent(C4_DIAGRAM_SAVED_EVENT, { detail }));
    });
  }

  it("a matching rerendered frame refetches SILENTLY and clears the stale banner", async () => {
    await renderEmbed();
    // Drive a stale state first via the Code-tab save path.
    fireEvent.click(screen.getByRole("button", { name: "code" }));
    fireEvent.click(screen.getByTestId("c4-save-fail-diag"));
    const banner = () => screen.getByTestId("c4-diagnostics");
    await waitFor(() =>
      expect(banner().getAttribute("data-stale")).toBe("true"),
    );
    embedReload.mockClear();

    await fireSaved({ dirPath: DIR, rerendered: true, diagnostic: null });

    await waitFor(() =>
      expect(banner().getAttribute("data-stale")).toBe("false"),
    );
    expect(embedReload).toHaveBeenCalledWith({ silent: true });
  });

  it("a matching failed-render frame sets the banner with the server diagnostic", async () => {
    await renderEmbed();
    embedReload.mockClear();

    await fireSaved({
      dirPath: DIR,
      rerendered: false,
      diagnostic: "render failed: likec4 parse error",
    });

    const banner = () => screen.getByTestId("c4-diagnostics");
    await waitFor(() =>
      expect(banner().getAttribute("data-stale")).toBe("true"),
    );
    expect(banner().getAttribute("data-stale-diagnostic")).toBe(
      "render failed: likec4 parse error",
    );
    expect(embedReload).toHaveBeenCalledWith({ silent: true });
  });

  it("a frame for another folder is a no-op", async () => {
    await renderEmbed();
    embedReload.mockClear();

    await fireSaved({
      dirPath: "engineering/other-diagrams",
      rerendered: true,
      diagnostic: null,
    });
    await new Promise((r) => setTimeout(r, 0));

    expect(embedReload).not.toHaveBeenCalled();
    expect(
      screen.getByTestId("c4-diagnostics").getAttribute("data-stale"),
    ).toBe("false");
  });
});
