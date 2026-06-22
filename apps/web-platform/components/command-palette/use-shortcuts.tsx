"use client";

// feat-web-app-shortcuts — the single source of truth for the ⌘K command layer.
// Owns the flat command registry, the ONE global keydown listener, the
// `isEditable` suppression predicate, and the `shortcutsEnabled` (WCAG SC 2.1.4
// "turn off") preference. Commands return a *serializable* CommandEffect rather
// than an opaque closure, so a future agent surface (#5638) can expose effects
// without rewriting run(). cmdk's Command.Dialog (Radix) handles focus
// trap/restore/inert for the palette + overlay; this module never hand-rolls it.

export type CommandEffect =
  | { kind: "navigate"; href: string }
  | { kind: "runRoutine"; fnId: string; label: string }
  | { kind: "openChat"; query?: string }
  | { kind: "openHelp" }
  | { kind: "toggleSidebar" };

export type CommandGroup =
  | "Navigation"
  | "Ask an agent"
  | "Knowledge Base"
  | "Workflows"
  | "General";

export type ShortcutContext = {
  isAdmin: boolean;
};

export type Command = {
  readonly id: string;
  readonly label: string;
  readonly group: CommandGroup;
  /** Optional keyboard hint shown in the palette/overlay (display only). */
  readonly keys?: string;
  /** Returns a serializable effect the UI interprets — never a side-effecting closure. */
  run(): CommandEffect;
};

/**
 * Suppression predicate — shortcuts must not fire while the user is typing.
 * Duck-typed (tagName / isContentEditable) rather than `instanceof HTMLElement`
 * so it is environment-agnostic and unit-testable without a DOM. Covers the
 * palette's own search input (a text input) so `?` types a literal there (G3).
 */
export function isEditable(target: unknown): boolean {
  if (!target || typeof target !== "object") return false;
  const el = target as { tagName?: string; isContentEditable?: boolean };
  const tag = el.tagName?.toUpperCase();
  return (
    tag === "INPUT" ||
    tag === "TEXTAREA" ||
    tag === "SELECT" ||
    el.isContentEditable === true
  );
}

// WCAG SC 2.1.4 "turn off" mechanism. Device-local a11y preference (NOT account
// state) — a deliberate divergence from the server-persisted settings toggles,
// since it gates the keyboard layer per-device. Default ON.
export const SHORTCUTS_STORAGE_KEY = "soleur:shortcuts.enabled";

export function readShortcutsEnabled(): boolean {
  try {
    return globalThis.localStorage?.getItem(SHORTCUTS_STORAGE_KEY) !== "0";
  } catch {
    return true; // storage unavailable (private mode / SSR) → default on
  }
}

export function writeShortcutsEnabled(enabled: boolean): void {
  try {
    globalThis.localStorage?.setItem(SHORTCUTS_STORAGE_KEY, enabled ? "1" : "0");
  } catch {
    /* persistence failed (quota / private mode) — in-memory state still applies */
  }
}

import { NAV_ITEMS, ADMIN_NAV_ITEMS, SECONDARY_NAV_ITEMS } from "./nav-items";

/**
 * The static command registry (navigation + hero actions). Routine and KB-doc
 * commands are async (fetched when the palette opens) and built in the palette
 * component — they are not part of this synchronous static set.
 */
export function buildCommands(ctx: ShortcutContext): Command[] {
  const nav: Command[] = [...NAV_ITEMS, ...SECONDARY_NAV_ITEMS, ...(ctx.isAdmin ? ADMIN_NAV_ITEMS : [])].map(
    (item) => ({
      id: `nav:${item.href}`,
      label: item.label,
      group: "Navigation" as const,
      run: () => ({ kind: "navigate" as const, href: item.href }),
    }),
  );

  const actions: Command[] = [
    {
      id: "ask-agent",
      label: "Ask an agent",
      group: "Ask an agent",
      keys: "⌘↵",
      run: () => ({ kind: "openChat" as const }),
    },
    {
      id: "toggle-sidebar",
      label: "Toggle sidebar",
      group: "General",
      keys: "⌘B",
      run: () => ({ kind: "toggleSidebar" as const }),
    },
    {
      id: "help",
      label: "Keyboard shortcuts",
      group: "General",
      keys: "?",
      run: () => ({ kind: "openHelp" as const }),
    },
  ];

  return [...nav, ...actions];
}
