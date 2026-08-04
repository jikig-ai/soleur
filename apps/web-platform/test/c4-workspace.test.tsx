import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { useState } from "react";
import { render, screen, fireEvent, waitFor } from "@testing-library/react";
import {
  KbChatContext,
  type KbChatContextValue,
} from "@/components/kb/kb-chat-context";
import { KbChatTrigger } from "@/components/kb/kb-chat-trigger";
import { FeatureFlagProvider } from "@/components/feature-flags/provider";
import type { FlagName } from "@/lib/feature-flags/server";

/** Full TS-exhaustive flag snapshot with only `c4-edit` parametrized. */
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
  };
}

// react-resizable-panels (this fork) needs real layout/ResizeObserver; mock it
// to plain divs so the collapse/reveal *logic* (conditional render driven by
// context state) is what's under test, not the library's flex math.
vi.mock("react-resizable-panels", () => ({
  Group: ({ children }: { children: React.ReactNode }) => <div>{children}</div>,
  Panel: ({ children }: { children: React.ReactNode }) => <div>{children}</div>,
  Separator: ({ children }: { children?: React.ReactNode }) => (
    <div data-testid="resize-handle">{children}</div>
  ),
}));

// next/navigation is pulled in transitively via the real KbChatTrigger →
// (none directly) but mock defensively incl. useSearchParams per session-state
// learning, so the component tree never reaches a real router.
vi.mock("next/navigation", () => ({
  useRouter: () => ({ push: vi.fn(), replace: vi.fn(), prefetch: vi.fn() }),
  usePathname: () => "/dashboard/kb/diagrams/c4-model.md",
  useSearchParams: () => new URLSearchParams(),
}));

// KbChatContent → ChatSurface pulls next/navigation + server hooks; mock it to a
// stub that exposes the contextPath it was mounted with and an onClose button
// mirroring the real "Close panel" affordance (kb-chat-content.tsx:158-168).
// The real KbChatContent renders the unique [data-kb-chat] marker, so the stub
// reproduces it for the single-mount assertion (C4-C1).
vi.mock("@/components/chat/kb-chat-content", () => ({
  KbChatContent: ({
    contextPath,
    onClose,
  }: {
    contextPath: string;
    onClose: () => void;
    visible: boolean;
  }) => (
    <div
      data-kb-chat
      data-testid="kb-chat-content"
      data-context-path={contextPath}
    >
      <button type="button" aria-label="Close panel" onClick={onClose}>
        close
      </button>
    </div>
  ),
}));

vi.mock("@/components/ui/markdown-renderer", () => ({
  MarkdownRenderer: () => <div data-testid="markdown" />,
}));

vi.mock("@/components/kb/c4-shared", () => ({
  Spinner: () => <div>loading</div>,
  useC4Project: () => ({
    data: { dump: { foo: 1 }, diagnostics: [], sources: { "model.c4": "x" } },
    error: null,
    loading: false,
    reload: vi.fn(),
  }),
  C4Canvas: () => <div data-testid="c4-canvas" />,
  // Expose the `stale` prop so the staleness-wiring test can assert C4Workspace
  // flips it to true after a save (the lifted-state honesty signal).
  C4Diagnostics: ({ stale }: { stale?: boolean }) => (
    <div data-testid="c4-diagnostics" data-stale={stale ? "true" : "false"} />
  ),
  // Surface onSaved as two affordances so the test can drive a save whose
  // server re-render succeeded (rerendered:true) or failed (false), without the
  // real PUT/CodeMirror plumbing.
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

const CONTEXT_PATH = "knowledge-base/diagrams/c4-model.md";

/**
 * Mounts C4Workspace under a real-ish KbChatContext provider that models the
 * C4 page wiring: suppressSidebar=true (side panel suppressed) + a lifted
 * embeddedConciergeOpen signal the SHARED header trigger drives via
 * revealEmbeddedConcierge. The header KbChatTrigger is rendered alongside so
 * the test exercises the SAME top-bar control the markdown viewer uses.
 */
function ProviderHarness({
  suppressSidebar,
  children,
}: {
  suppressSidebar: boolean;
  children: React.ReactNode;
}) {
  const [embeddedConciergeOpen, setEmbedded] = useState(true);
  const [sidebarOpen, setSidebarOpen] = useState(false);
  const value: KbChatContextValue = {
    open: sidebarOpen,
    openSidebar: () => setSidebarOpen(true),
    closeSidebar: () => setSidebarOpen(false),
    contextPath: CONTEXT_PATH,
    enabled: true,
    messageCount: 0,
    setMessageCount: () => {},
    suppressSidebar,
    setSuppressSidebar: () => {},
    embeddedConciergeOpen,
    revealEmbeddedConcierge: () => setEmbedded(true),
    collapseEmbeddedConcierge: () => setEmbedded(false),
  };
  return <KbChatContext.Provider value={value}>{children}</KbChatContext.Provider>;
}

async function renderC4WithHeader(suppressSidebar = true, c4Edit = true) {
  const { default: C4Workspace } = await import("@/components/kb/c4-workspace");
  return render(
    <FeatureFlagProvider flags={flagSnapshot(c4Edit)}>
      <ProviderHarness suppressSidebar={suppressSidebar}>
        {/* The shared top-bar trigger (as KbContentHeader renders it on C4). */}
        <KbChatTrigger fallbackHref="/dashboard/chat/new" />
        <C4Workspace
          viewId="index"
          dirPath="knowledge-base/diagrams"
          contextPath={CONTEXT_PATH}
        />
      </ProviderHarness>
    </FeatureFlagProvider>,
  );
}

/**
 * #7222 — C4Workspace picks its topology from a live matchMedia read (it is
 * `ssr: false`-loaded, so there is no hydration seam to protect). happy-dom
 * defaults to 1024px, which is why every test above exercises the DESKTOP
 * split without stubbing anything; the mobile arm has to say so explicitly.
 */
function stubViewport(mobile: boolean) {
  vi.stubGlobal("matchMedia", (query: string) => ({
    matches: query.includes("max-width") ? mobile : !mobile,
    media: query,
    addEventListener: () => {},
    removeEventListener: () => {},
  }));
}

beforeEach(() => {
  vi.clearAllMocks();
});

afterEach(() => {
  vi.unstubAllGlobals();
});

describe("C4Workspace — header-driven Concierge consistency (Workstream C)", () => {
  it("C4-C1: exactly one [data-kb-chat] mounts on a C4 doc (no double-mount)", async () => {
    const { container } = await renderC4WithHeader();
    expect(container.querySelectorAll("[data-kb-chat]")).toHaveLength(1);
  });

  it("C4-C2: the floating 'Open Concierge' pill is gone", async () => {
    await renderC4WithHeader();
    expect(screen.queryByLabelText("Open Concierge")).toBeNull();
  });

  it("C4-C3: the header trigger reveals a collapsed Concierge", async () => {
    await renderC4WithHeader();
    // Collapse via the chevron, then reveal via the SHARED top-bar trigger.
    fireEvent.click(screen.getByLabelText("Collapse Concierge"));
    expect(screen.queryByTestId("kb-chat-content")).toBeNull();

    fireEvent.click(screen.getByRole("button", { name: /ask about this document/i }));
    const chat = screen.getByTestId("kb-chat-content");
    expect(chat).toBeTruthy();
    expect(chat.getAttribute("data-context-path")).toBe(CONTEXT_PATH);
  });

  it("C4-C4: the chevron AND the KbChatContent X both collapse it", async () => {
    await renderC4WithHeader();
    // Chevron collapse.
    fireEvent.click(screen.getByLabelText("Collapse Concierge"));
    expect(screen.queryByTestId("kb-chat-content")).toBeNull();
    expect(screen.queryByTestId("resize-handle")).toBeNull();

    // Reveal then collapse via the X (Close panel) in KbChatContent's header.
    fireEvent.click(screen.getByRole("button", { name: /ask about this document/i }));
    fireEvent.click(screen.getByLabelText("Close panel"));
    expect(screen.queryByTestId("kb-chat-content")).toBeNull();
  });

  it("C4-C4b: Concierge stays mounted across the Concierge/Code tab toggle", async () => {
    await renderC4WithHeader();
    // Toggle to Code and back; the Concierge thread mount persists (CSS-hidden,
    // not unmounted) so the [data-kb-chat] marker survives the tab switch.
    fireEvent.click(screen.getByRole("button", { name: "Code" }));
    fireEvent.click(screen.getByRole("button", { name: "Concierge" }));
    expect(screen.getByTestId("kb-chat-content")).toBeTruthy();
  });

  it("C4-C6: a successful re-render does NOT flag stale; a failed re-render does (Layer 2)", async () => {
    await renderC4WithHeader();
    // Fresh load — no edit yet, banner absent.
    expect(
      screen.getByTestId("c4-diagnostics").getAttribute("data-stale"),
    ).toBe("false");

    fireEvent.click(screen.getByRole("button", { name: "Code" }));

    // Save where the server re-rendered (rerendered:true) → diagram is fresh, no banner.
    fireEvent.click(screen.getByTestId("c4-save-ok"));
    await waitFor(() =>
      expect(
        screen.getByTestId("c4-diagnostics").getAttribute("data-stale"),
      ).toBe("false"),
    );

    // Save where the re-render failed (rerendered:false) → stale banner shows.
    fireEvent.click(screen.getByTestId("c4-save-fail"));
    await waitFor(() =>
      expect(
        screen.getByTestId("c4-diagnostics").getAttribute("data-stale"),
      ).toBe("true"),
    );
  });

  it("C4-C5: markdown viewer (no suppressSidebar) — trigger opens the SIDE panel, not the embedded reveal", async () => {
    // When suppressSidebar is false (markdown viewer), the same trigger calls
    // openSidebar (the side-panel path) — the C4 embedded reveal is untouched.
    // Render only the header trigger under a non-suppressed provider.
    let openedSide = false;
    const value: KbChatContextValue = {
      open: false,
      openSidebar: () => {
        openedSide = true;
      },
      closeSidebar: () => {},
      contextPath: CONTEXT_PATH,
      enabled: true,
      messageCount: 0,
      setMessageCount: () => {},
      suppressSidebar: false,
      setSuppressSidebar: () => {},
      embeddedConciergeOpen: true,
      revealEmbeddedConcierge: () => {
        throw new Error("must not reveal embedded on the markdown path");
      },
      collapseEmbeddedConcierge: () => {},
    };
    render(
      <KbChatContext.Provider value={value}>
        <KbChatTrigger fallbackHref="/dashboard/chat/new" />
      </KbChatContext.Provider>,
    );
    fireEvent.click(screen.getByRole("button", { name: /ask about this document/i }));
    expect(openedSide).toBe(true);
  });
});

describe("C4Workspace — c4-edit flag gates the Code tab (AC3/AC10)", () => {
  it("AC3: flag OFF ⇒ no Code tab button, C4CodePanel never mounts, Concierge is default", async () => {
    await renderC4WithHeader(true, false);
    // No "Code" tab button.
    expect(screen.queryByRole("button", { name: "Code" })).toBeNull();
    // The C4CodePanel save affordances never render (panel not mounted).
    expect(screen.queryByTestId("c4-save-ok")).toBeNull();
    expect(screen.queryByTestId("c4-save-fail")).toBeNull();
    // The Concierge is present and is the default surface.
    expect(screen.getByTestId("kb-chat-content")).toBeTruthy();
  });

  it("AC3: flag ON ⇒ the Code tab button is present", async () => {
    await renderC4WithHeader(true, true);
    expect(screen.getByRole("button", { name: "Code" })).toBeTruthy();
  });

  it("AC10: flag OFF ⇒ a discoverability hint points users to the Concierge", async () => {
    await renderC4WithHeader(true, false);
    expect(
      screen.getByText(/ask the Concierge/i),
    ).toBeTruthy();
  });

  it("AC10: flag ON ⇒ the discoverability hint is absent (Code tab handles editing)", async () => {
    await renderC4WithHeader(true, true);
    expect(screen.queryByText(/ask the Concierge/i)).toBeNull();
  });
});

describe("#7222 — C4Workspace Concierge topology below `md`", () => {
  it("renders the revealed Concierge as a full-screen overlay, not a split column", async () => {
    stubViewport(true);
    await renderC4WithHeader();

    // The overlay host exists and the resizable split does NOT: a splitter with
    // nothing on its far side is the compressed-panes layout the operator hit.
    expect(screen.getByTestId("c4-concierge-overlay")).toBeTruthy();
    expect(screen.queryByTestId("resize-handle")).toBeNull();
  });

  it("keeps the desktop split column and no overlay above `md`", async () => {
    stubViewport(false);
    await renderC4WithHeader();

    // The discriminator for the test above.
    expect(screen.queryByTestId("c4-concierge-overlay")).toBeNull();
    expect(screen.getByTestId("resize-handle")).toBeTruthy();
  });

  it("still mounts exactly one Concierge on mobile (the two hosts share one window)", async () => {
    stubViewport(true);
    const { container } = await renderC4WithHeader();

    // Building the window once and choosing its HOST — rather than writing two
    // breakpoint branches — is what makes this structural. A CSS dual-render
    // would put two ChatSurfaces on the same contextPath.
    expect(container.querySelectorAll("[data-kb-chat]")).toHaveLength(1);
    expect(screen.getAllByTestId("kb-chat-content")).toHaveLength(1);
  });

  it("the overlay's close control dismisses it and leaves the diagram full-width", async () => {
    stubViewport(true);
    await renderC4WithHeader();

    fireEvent.click(screen.getByLabelText("Close Concierge"));
    expect(screen.queryByTestId("c4-concierge-overlay")).toBeNull();
    expect(screen.queryByTestId("kb-chat-content")).toBeNull();
    // The diagram is never unmounted by the overlay — it sits underneath.
    expect(screen.getByTestId("c4-canvas")).toBeTruthy();
  });

  it("the shared header trigger re-opens it as an overlay after a dismiss", async () => {
    stubViewport(true);
    await renderC4WithHeader();

    fireEvent.click(screen.getByLabelText("Close Concierge"));
    fireEvent.click(
      screen.getByRole("button", { name: /ask about this document/i }),
    );
    expect(screen.getByTestId("c4-concierge-overlay")).toBeTruthy();
  });
});
