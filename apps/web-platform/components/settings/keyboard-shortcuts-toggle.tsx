"use client";

// feat-web-app-shortcuts (FR9 / WCAG SC 2.1.4) — the "turn off" mechanism for
// the keyboard command layer. Device-local (localStorage), NOT account state:
// the shortcut layer is a per-device a11y concern, so this deliberately diverges
// from the server-persisted settings toggles. When OFF, the ENTIRE global
// listener is disabled (⌘K / ⌘/ / ? / ⌘B) — the provider re-reads the pref via
// the SHORTCUTS_CHANGED_EVENT this dispatches. Gated behind the command-palette
// flag so it only appears where the layer is live.

import { useEffect, useState } from "react";
import {
  readShortcutsEnabled,
  writeShortcutsEnabled,
  SHORTCUTS_CHANGED_EVENT,
} from "@/components/command-palette/use-shortcuts";
import { useOptionalFeatureFlag } from "@/components/feature-flags/provider";

export function KeyboardShortcutsToggle() {
  const flagOn = useOptionalFeatureFlag("command-palette");
  // SSR-safe: init ON (matches the server render + the pref default), then sync
  // the device-local value post-hydration.
  const [enabled, setEnabled] = useState(true);

  useEffect(() => {
    setEnabled(readShortcutsEnabled());
  }, []);

  if (!flagOn) return null;

  function toggle() {
    const next = !enabled;
    setEnabled(next);
    writeShortcutsEnabled(next);
    // Notify any live ShortcutsProvider in this document (storage events do not
    // fire in the same document that wrote the value).
    window.dispatchEvent(new Event(SHORTCUTS_CHANGED_EVENT));
  }

  return (
    <section>
      <h2 className="mb-4 text-lg font-semibold text-soleur-text-primary">
        Preferences
      </h2>
      <div className="rounded-xl border border-soleur-border-default bg-soleur-bg-surface-1/50 p-6">
        <div className="flex items-center justify-between gap-4">
          <div className="flex flex-col gap-1">
        <span className="text-sm font-semibold text-soleur-text-primary">
          Enable keyboard shortcuts
        </span>
        <span className="text-xs text-soleur-text-muted">
          Use <kbd>⌘K</kbd> to open the command palette, <kbd>⌘/</kbd> for the
          shortcut list, and <kbd>⌘B</kbd> to toggle the sidebar. Turn off to
          disable all keyboard shortcuts on this device.
        </span>
      </div>
      <button
        type="button"
        role="switch"
        aria-checked={enabled}
        aria-label="Enable keyboard shortcuts"
        onClick={toggle}
        className={`relative inline-flex h-5 w-9 shrink-0 cursor-pointer rounded-full border-2 border-transparent transition-colors ${
          enabled ? "bg-soleur-accent-gold-fg" : "bg-soleur-bg-surface-2"
        }`}
      >
        <span
          className={`pointer-events-none inline-block h-4 w-4 transform rounded-full bg-white shadow-sm transition-transform ${
            enabled ? "translate-x-4" : "translate-x-0"
          }`}
        />
          </button>
        </div>
      </div>
    </section>
  );
}
