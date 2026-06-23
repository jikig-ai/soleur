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

vi.mock("next/navigation", () => ({
  useRouter: () => ({ push: vi.fn(), replace: vi.fn(), prefetch: vi.fn() }),
}));

function renderHelp() {
  return render(
    <ShortcutsProvider enabled isAdmin={false} onToggleSidebar={() => {}}>
      <input data-testid="outside-input" />
      <HelpOverlay />
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
