"use client";

// feat-web-app-shortcuts — the `?` / `⌘/` help overlay (FR4). A searchable
// cheat-sheet sharing the palette's cmdk Command.Dialog (Radix-backed focus
// trap/restore), NOT a parallel a11y impl. Lists ONLY shortcuts that actually
// DO something in v1 — the wireframe's `G`-then-I/K/R/D nav sequences are
// NG2-deferred (#5636) and would document dead keys, so they are omitted.

import { Command } from "cmdk";
import { useShortcuts } from "./use-shortcuts";
import { useTour } from "@/components/tour/tour-provider";

// Each row carries the action it performs, so selecting it (click or ↵) RUNS
// the shortcut rather than only dismissing the overlay — the overlay doubles as
// a clickable launcher, not just a cheat-sheet.
type HelpAction = "palette" | "help" | "sidebar" | "close";

const SHORTCUTS: ReadonlyArray<{
  keys: string;
  label: string;
  action: HelpAction;
}> = [
  { keys: "⌘K", label: "Open command palette", action: "palette" },
  { keys: "⌘/", label: "Open keyboard shortcuts (this overlay)", action: "help" },
  { keys: "?", label: "Open keyboard shortcuts", action: "help" },
  { keys: "⌘B", label: "Toggle sidebar", action: "sidebar" },
  { keys: "Esc", label: "Close palette / overlay / drawer", action: "close" },
];

export function HelpOverlay() {
  const { enabled, helpOpen, closeHelp, openPalette, runEffect } =
    useShortcuts();
  const tour = useTour();

  function runShortcut(action: HelpAction) {
    switch (action) {
      case "palette":
        // Dismiss the overlay first so the palette opens as the top layer.
        closeHelp();
        openPalette();
        break;
      case "sidebar":
        closeHelp();
        runEffect({ kind: "toggleSidebar" });
        break;
      case "help":
        // This overlay is already open — selecting its own row keeps it open
        // (a no-op) rather than the confusing "open shortcuts → instantly close".
        break;
      case "close":
        closeHelp();
        break;
    }
  }

  if (!enabled) return null;
  return (
    <Command.Dialog
      open={helpOpen}
      onOpenChange={(open) => {
        if (!open) closeHelp();
      }}
      label="Keyboard shortcuts"
      loop
    >
      <Command.Input
        placeholder="Search shortcuts…"
        aria-label="Search keyboard shortcuts"
      />
      <Command.List>
        <Command.Empty>No matching shortcuts.</Command.Empty>
        <Command.Group heading="Keyboard shortcuts">
          {SHORTCUTS.map((s) => (
            <Command.Item
              key={s.keys + s.label}
              value={`${s.label} ${s.keys}`}
              // Selecting a row RUNS its shortcut (open palette / toggle sidebar
              // / close), not just dismiss the overlay.
              onSelect={() => runShortcut(s.action)}
              data-testid={`help-row-${s.keys}`}
            >
              <span className="cmdk-help-label">{s.label}</span>
              <kbd className="cmdk-keys">{s.keys}</kbd>
            </Command.Item>
          ))}
        </Command.Group>
        {tour.available && (
          <Command.Group heading="Get started">
            <Command.Item
              value="Take a tour of the app guided onboarding"
              onSelect={() => {
                // Dismiss the overlay first so the tour mounts as the top layer.
                closeHelp();
                tour.startTour("help-overlay");
              }}
              data-testid="help-row-take-a-tour"
            >
              <span className="cmdk-help-label">Take a tour of the app</span>
            </Command.Item>
          </Command.Group>
        )}
      </Command.List>
    </Command.Dialog>
  );
}
