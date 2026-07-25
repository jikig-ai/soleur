"use client";

import { SearchIcon } from "@/components/icons";
import { useShortcuts } from "./use-shortcuts";

/**
 * A visible tap target that opens the command palette on touch devices.
 *
 * The palette is otherwise reachable ONLY via keyboard (`⌘K`/`Ctrl+K`, the
 * `g`-leader sequences, or the `?` help overlay row) — all of which a
 * touch-only phone/tablet user can never fire. This button, mounted in the
 * mobile top bar (`md:hidden`), is the sole non-keyboard entry point.
 *
 * Gated on `enabled` (the `command-palette` Flagsmith flag, threaded through
 * `ShortcutsProvider`) so it appears exactly when the keyboard path does — when
 * the flag is off the whole command layer is inert and this renders nothing.
 */
export function MobilePaletteTrigger() {
  const { enabled, openPalette } = useShortcuts();

  if (!enabled) return null;

  return (
    <button
      type="button"
      onClick={openPalette}
      aria-label="Open command menu"
      className="ml-auto flex h-11 w-11 shrink-0 items-center justify-center rounded-lg text-soleur-text-muted hover:bg-soleur-bg-surface-2 hover:text-soleur-text-primary"
    >
      <SearchIcon className="h-5 w-5" />
    </button>
  );
}
