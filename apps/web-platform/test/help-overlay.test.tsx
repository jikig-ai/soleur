import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import {
  render,
  screen,
  fireEvent,
  cleanup,
  act,
} from "@testing-library/react";
import { ShortcutsProvider } from "@/components/command-palette/use-shortcuts";
import { HelpOverlay } from "@/components/command-palette/help-overlay";
import { CommandPalette } from "@/components/command-palette/command-palette";

// next/navigation router — capture push() for go-to navigate-effect assertions.
const routerPush = vi.hoisted(() => vi.fn());
vi.mock("next/navigation", () => ({
  useRouter: () => ({ push: routerPush, replace: vi.fn(), prefetch: vi.fn() }),
}));
vi.mock("@/lib/client-observability", () => ({ reportSilentFallback: vi.fn() }));

function renderHelp(props: Partial<{ isAdmin: boolean }> = {}) {
  return render(
    <ShortcutsProvider
      enabled
      isAdmin={props.isAdmin ?? false}
      onToggleSidebar={() => {}}
    >
      <input data-testid="outside-input" />
      <HelpOverlay />
    </ShortcutsProvider>,
  );
}

// For the "selecting a row runs the command" tests we mount the palette too, so
// a row that opens the palette is observable. fetch is stubbed because the
// palette lazy-fetches KB/routines on open.
function renderHelpAndPalette(onToggleSidebar = () => {}) {
  vi.stubGlobal(
    "fetch",
    vi.fn(async (input: RequestInfo | URL) => {
      const url = typeof input === "string" ? input : input.toString();
      return {
        ok: true,
        status: 200,
        json: async () =>
          url.includes("/routines")
            ? { routines: [] }
            : { tree: { children: [] }, needsReconnect: false },
      } as Response;
    }),
  );
  return render(
    <ShortcutsProvider enabled isAdmin={false} onToggleSidebar={onToggleSidebar}>
      <HelpOverlay />
      <CommandPalette />
    </ShortcutsProvider>,
  );
}

function pressKey(
  key: string,
  opts: { meta?: boolean; target?: Element | Document } = {},
) {
  act(() => {
    fireEvent.keyDown(opts.target ?? document.body, {
      key,
      metaKey: opts.meta ?? false,
    });
  });
}

beforeEach(() => {
  routerPush.mockClear();
  Element.prototype.scrollIntoView = vi.fn();
  vi.stubGlobal("fetch", vi.fn());
  try {
    localStorage.clear();
  } catch {
    /* ignore */
  }
});
afterEach(() => {
  cleanup();
  vi.unstubAllGlobals();
});

describe("HelpOverlay", () => {
  it("opens on ⌘/ and lists the chords, the go-to sequences, and the agent summon", async () => {
    renderHelp();
    pressKey("/", { meta: true });
    expect(
      await screen.findByLabelText("Search keyboard shortcuts"),
    ).toBeInTheDocument();
    expect(screen.getByText("Open command palette")).toBeInTheDocument();
    expect(screen.getByText("Toggle sidebar")).toBeInTheDocument();
    // #5636 go-to sequences are now un-deferred and documented.
    expect(screen.getByText("Go to Dashboard")).toBeInTheDocument();
    expect(screen.getByText("Go to Inbox")).toBeInTheDocument();
    expect(screen.getByText("Go to Knowledge Base")).toBeInTheDocument();
    expect(screen.getByTestId("help-row-G D")).toBeInTheDocument();
    // The agent summon is grouped as an action (G C), not navigation.
    expect(screen.getByTestId("help-row-G C")).toHaveTextContent("Ask an agent");
    // Admin-only Analytics row is absent for a non-admin.
    expect(screen.queryByText("Go to Analytics")).not.toBeInTheDocument();
  });

  it("shows the Go to Analytics row only for an admin", async () => {
    renderHelp({ isAdmin: true });
    pressKey("/", { meta: true });
    await screen.findByLabelText("Search keyboard shortcuts");
    expect(screen.getByText("Go to Analytics")).toBeInTheDocument();
    expect(screen.getByTestId("help-row-G A")).toBeInTheDocument();
  });

  it("selecting a go-to row navigates and closes the overlay", async () => {
    renderHelp();
    pressKey("/", { meta: true });
    await screen.findByLabelText("Search keyboard shortcuts");
    fireEvent.click(screen.getByTestId("help-row-G D"));
    expect(routerPush).toHaveBeenCalledWith("/dashboard");
    expect(
      screen.queryByLabelText("Search keyboard shortcuts"),
    ).not.toBeInTheDocument();
  });

  it("selecting the agent row opens chat and closes the overlay", async () => {
    renderHelp();
    pressKey("/", { meta: true });
    await screen.findByLabelText("Search keyboard shortcuts");
    fireEvent.click(screen.getByTestId("help-row-G C"));
    expect(routerPush).toHaveBeenCalledWith("/dashboard/chat/new");
    expect(
      screen.queryByLabelText("Search keyboard shortcuts"),
    ).not.toBeInTheDocument();
  });

  it("opens on a bare ? from the body", async () => {
    renderHelp();
    pressKey("?");
    expect(
      await screen.findByLabelText("Search keyboard shortcuts"),
    ).toBeInTheDocument();
  });

  it("does NOT open on ? while focus is in an editable element", () => {
    renderHelp();
    const input = screen.getByTestId("outside-input");
    pressKey("?", { target: input });
    expect(
      screen.queryByLabelText("Search keyboard shortcuts"),
    ).not.toBeInTheDocument();
  });
});

describe("HelpOverlay — rows run their command (not just close)", () => {
  it("selecting the ⌘K row opens the command palette and closes the overlay", async () => {
    renderHelpAndPalette();
    pressKey("/", { meta: true }); // open help overlay
    await screen.findByLabelText("Search keyboard shortcuts");
    fireEvent.click(screen.getByTestId("help-row-⌘K"));
    // The command palette is now open…
    expect(
      await screen.findByLabelText("Command palette search"),
    ).toBeInTheDocument();
    // …and the help overlay closed.
    expect(
      screen.queryByLabelText("Search keyboard shortcuts"),
    ).not.toBeInTheDocument();
  });

  it("selecting the ⌘B row toggles the sidebar and closes the overlay", async () => {
    const onToggleSidebar = vi.fn();
    renderHelpAndPalette(onToggleSidebar);
    pressKey("/", { meta: true });
    await screen.findByLabelText("Search keyboard shortcuts");
    fireEvent.click(screen.getByTestId("help-row-⌘B"));
    expect(onToggleSidebar).toHaveBeenCalledTimes(1);
    expect(
      screen.queryByLabelText("Search keyboard shortcuts"),
    ).not.toBeInTheDocument();
  });
});
