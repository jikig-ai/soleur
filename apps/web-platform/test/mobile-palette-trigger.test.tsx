import { describe, it, expect, afterEach, vi } from "vitest";
import { render, screen, fireEvent, cleanup } from "@testing-library/react";
import {
  ShortcutsProvider,
  useShortcuts,
} from "@/components/command-palette/use-shortcuts";
import { MobilePaletteTrigger } from "@/components/command-palette/mobile-palette-trigger";

// ShortcutsProvider calls useRouter() at mount; provide the app-router mock.
const routerPush = vi.hoisted(() => vi.fn());
vi.mock("next/navigation", () => ({
  useRouter: () => ({ push: routerPush, replace: vi.fn(), prefetch: vi.fn() }),
}));

// A minimal consumer so the test can observe the palette open-state that the
// trigger flips — avoids mounting the full CommandPalette (and its fetch /
// next-navigation mocks) just to assert the trigger's contract.
function PaletteState() {
  const { paletteOpen } = useShortcuts();
  return <div data-testid="palette-open">{String(paletteOpen)}</div>;
}

function renderTrigger(enabled: boolean) {
  return render(
    <ShortcutsProvider enabled={enabled} isAdmin={false} onToggleSidebar={() => {}}>
      <MobilePaletteTrigger />
      <PaletteState />
    </ShortcutsProvider>,
  );
}

afterEach(() => cleanup());

describe("MobilePaletteTrigger", () => {
  it("opens the command palette on tap (the only non-keyboard entry point)", () => {
    renderTrigger(true);

    expect(screen.getByTestId("palette-open").textContent).toBe("false");
    const button = screen.getByRole("button", { name: "Open command menu" });
    fireEvent.click(button);
    expect(screen.getByTestId("palette-open").textContent).toBe("true");
  });

  it("exposes a >=44px touch target", () => {
    renderTrigger(true);
    const button = screen.getByRole("button", { name: "Open command menu" });
    expect(button.className).toContain("h-11");
    expect(button.className).toContain("w-11");
  });

  it("renders nothing when the command-palette flag is off", () => {
    renderTrigger(false);
    expect(
      screen.queryByRole("button", { name: "Open command menu" }),
    ).toBeNull();
  });
});
