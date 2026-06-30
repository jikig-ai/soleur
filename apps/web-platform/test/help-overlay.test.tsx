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

vi.mock("next/navigation", () => ({
  useRouter: () => ({ push: vi.fn(), replace: vi.fn(), prefetch: vi.fn() }),
}));
vi.mock("@/lib/client-observability", () => ({ reportSilentFallback: vi.fn() }));

function renderHelp() {
  return render(
    <ShortcutsProvider enabled isAdmin={false} onToggleSidebar={() => {}}>
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
  it("opens on ⌘/ and lists only the working v1 shortcuts (no G-sequence rows)", async () => {
    renderHelp();
    pressKey("/", { meta: true });
    expect(
      await screen.findByLabelText("Search keyboard shortcuts"),
    ).toBeInTheDocument();
    expect(screen.getByText("Open command palette")).toBeInTheDocument();
    expect(screen.getByText("Toggle sidebar")).toBeInTheDocument();
    // NG2-deferred nav sequences must NOT be documented.
    expect(screen.queryByText(/then/i)).not.toBeInTheDocument();
    expect(screen.queryByText(/Go to/i)).not.toBeInTheDocument();
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
