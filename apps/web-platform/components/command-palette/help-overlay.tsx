"use client";

// feat-web-app-shortcuts — the `?` / `⌘/` help overlay (FR4). A searchable
// cheat-sheet sharing the palette's cmdk Command.Dialog (Radix-backed focus
// trap/restore), NOT a parallel a11y impl. Lists ONLY shortcuts that actually
// DO something in v1 — the wireframe's `G`-then-I/K/R/D nav sequences are
// NG2-deferred (#5636) and would document dead keys, so they are omitted.

import { Command } from "cmdk";
import { useShortcuts } from "./use-shortcuts";

const SHORTCUTS: ReadonlyArray<{ keys: string; label: string }> = [
  { keys: "⌘K", label: "Open command palette" },
  { keys: "⌘/", label: "Open keyboard shortcuts (this overlay)" },
  { keys: "?", label: "Open keyboard shortcuts" },
  { keys: "⌘B", label: "Toggle sidebar" },
  { keys: "Esc", label: "Close palette / overlay / drawer" },
];

export function HelpOverlay() {
  const { enabled, helpOpen, closeHelp } = useShortcuts();
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
              // Informational rows — selecting simply dismisses the overlay.
              onSelect={() => closeHelp()}
              data-testid={`help-row-${s.keys}`}
            >
              <span className="cmdk-help-label">{s.label}</span>
              <kbd className="cmdk-keys">{s.keys}</kbd>
            </Command.Item>
          ))}
        </Command.Group>
      </Command.List>
    </Command.Dialog>
  );
}
