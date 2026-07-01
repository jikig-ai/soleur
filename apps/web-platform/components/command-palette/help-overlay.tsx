"use client";

// feat-web-app-shortcuts — the `?` / `⌘/` help overlay (FR4). A searchable
// cheat-sheet sharing the palette's cmdk Command.Dialog (Radix-backed focus
// trap/restore), NOT a parallel a11y impl. Lists the chords plus the direct
// "go-to" sequences (`G` `D` …) and the Ask-an-agent summon (`G` `C`) — the
// wireframe's design, un-deferred from #5636. Sequence rows derive from the
// single-source `seq` field on NAV_ITEMS/ADMIN_NAV_ITEMS, so a documented key
// can never drift from the live binding.

import { Command } from "cmdk";
import {
  useShortcuts,
  formatSeqHint,
  ASK_AGENT_SEQ,
  type CommandEffect,
} from "./use-shortcuts";
import { NAV_ITEMS, ADMIN_NAV_ITEMS } from "./nav-items";
import { useTour } from "@/components/tour/tour-provider";

// Each chord row carries the action it performs, so selecting it (click or ↵)
// RUNS the shortcut rather than only dismissing the overlay — the overlay
// doubles as a clickable launcher, not just a cheat-sheet.
type HelpAction = "palette" | "help" | "sidebar" | "close";

const CHORDS: ReadonlyArray<{
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

// "Go to" sequence rows — derived from the single-source `seq` field. Each runs
// its navigate effect. Admin rows render only when the operator is an admin.
type SeqRow = { keys: string; label: string; effect: CommandEffect };

const NAV_ROWS: readonly SeqRow[] = NAV_ITEMS.filter((i) => i.seq).map((i) => ({
  keys: formatSeqHint(i.seq as string),
  label: `Go to ${i.label}`,
  effect: { kind: "navigate", href: i.href },
}));

const ADMIN_NAV_ROWS: readonly SeqRow[] = ADMIN_NAV_ITEMS.filter((i) => i.seq).map(
  (i) => ({
    keys: formatSeqHint(i.seq as string),
    label: `Go to ${i.label}`,
    effect: { kind: "navigate", href: i.href },
  }),
);

// The Ask-an-agent hero summon — grouped as an ACTION ("Ask an agent"), not
// navigation, so it reads as the hero verb it is.
const AGENT_ROW: SeqRow = {
  keys: formatSeqHint(ASK_AGENT_SEQ),
  label: "Ask an agent",
  effect: { kind: "openChat" },
};

export function HelpOverlay() {
  const { enabled, helpOpen, closeHelp, openPalette, runEffect, isAdmin } =
    useShortcuts();
  const tour = useTour();

  function runChord(action: HelpAction) {
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

  // Dismiss the overlay first so the destination mounts as the top layer.
  function runRow(effect: CommandEffect) {
    closeHelp();
    runEffect(effect);
  }

  const navRows = isAdmin ? [...NAV_ROWS, ...ADMIN_NAV_ROWS] : NAV_ROWS;

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
          {CHORDS.map((s) => (
            <Command.Item
              key={s.keys + s.label}
              value={`${s.label} ${s.keys}`}
              // Selecting a row RUNS its shortcut (open palette / toggle sidebar
              // / close), not just dismiss the overlay.
              onSelect={() => runChord(s.action)}
              data-testid={`help-row-${s.keys}`}
            >
              <span className="cmdk-help-label">{s.label}</span>
              <kbd className="cmdk-keys">{s.keys}</kbd>
            </Command.Item>
          ))}
        </Command.Group>
        <Command.Group heading="Ask an agent">
          <Command.Item
            value={`${AGENT_ROW.label} ${AGENT_ROW.keys}`}
            onSelect={() => runRow(AGENT_ROW.effect)}
            data-testid={`help-row-${AGENT_ROW.keys}`}
          >
            <span className="cmdk-help-label">{AGENT_ROW.label}</span>
            <kbd className="cmdk-keys">{AGENT_ROW.keys}</kbd>
          </Command.Item>
        </Command.Group>
        <Command.Group heading="Go to">
          {navRows.map((s) => (
            <Command.Item
              key={s.keys + s.label}
              value={`${s.label} ${s.keys}`}
              onSelect={() => runRow(s.effect)}
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
