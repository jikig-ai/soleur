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
  | "Settings"
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

/** A minimal KeyboardEvent shape `resolveShortcut` reads — DOM-free + testable. */
export type ShortcutKeyEvent = {
  key: string;
  metaKey: boolean;
  ctrlKey: boolean;
  shiftKey: boolean;
  target: unknown;
  /** Auto-repeat (held key). A repeat never arms/advances a sequence (MDN std). */
  repeat?: boolean;
};

/** The trigger a keystroke maps to (null = no shortcut / suppressed). */
export type ShortcutAction =
  | "openPalette"
  | "openHelp"
  | "toggleSidebar"
  | null;

/**
 * Pure keystroke → action mapping. The single matching authority shared by the
 * global listener; extracted as a pure function so the binding scheme is
 * unit-testable without a DOM (the listener layers `shortcutsEnabled` + Escape
 * handling on top). Suppressed entirely while focus is in an editable element
 * (FR1) — including the palette's own search input, so `?` types a literal `?`
 * there (G3). Bindings: `⌘K`/`Ctrl+K` palette, `⌘/` (canonical, WCAG-exempt) +
 * bare `?` (alias) help, `⌘B`/`Ctrl+B` sidebar (shift variant rejected — kept
 * single-purpose, matching the pre-migration layout handler).
 */
export function resolveShortcut(e: ShortcutKeyEvent): ShortcutAction {
  if (isEditable(e.target)) return null;
  const mod = e.metaKey || e.ctrlKey;
  const k = e.key.toLowerCase();
  if (mod && !e.shiftKey && k === "k") return "openPalette";
  if (mod && e.key === "/") return "openHelp";
  if (!mod && e.key === "?") return "openHelp";
  if (mod && !e.shiftKey && k === "b") return "toggleSidebar";
  return null;
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

import { NAV_ITEMS, ADMIN_NAV_ITEMS, SETTINGS_NAV_ITEMS } from "./nav-items";
import { isApplePlatform, modChord } from "./platform";

// ---------------------------------------------------------------------------
// Direct "go-to" keyboard sequences (`g` prefix + a letter) — #5636, the
// wireframe's design. The `seq` field on NAV_ITEMS/ADMIN_NAV_ITEMS is the SINGLE
// source for the SECOND key: the resolver map, the palette key hint, and the
// `?` overlay rows all derive from it, so the destination letter can never drift
// from the live binding. The shared `g` PREFIX is the fixed `SEQUENCE_PREFIX`
// constant below (every `seq` starts with it by construction).
// ---------------------------------------------------------------------------

/** The one shared "go-to" prefix. The arm matcher keys on this, and every `seq`
 * (incl. ASK_AGENT_SEQ) is authored `"<SEQUENCE_PREFIX> <letter>"`. */
export const SEQUENCE_PREFIX = "g";

/** The Ask-an-agent hero sequence ("go to chat"). Not a nav route, so it lives
 * here rather than on a nav array. Rebound from the requested `Ctrl+C` (a hard
 * copy/SIGINT conflict `isEditable` cannot protect) to the collision-free
 * `g`-family — `c` = chat, the closest surviving letter. */
export const ASK_AGENT_SEQ = "g c";

/** The Ask-an-agent Super/Meta accelerator (⌘C). Mirrors ASK_AGENT_SEQ; not a
 * nav route so it lives here, not on a nav array. */
export const ASK_AGENT_ACCEL = "c";

/** Window between the two keystrokes of a sequence (GitHub `hotkey`'s value). */
export const SEQUENCE_WINDOW_MS = 1500;

/** Format a `seq` for display: `"g d"` → `"G D"` (the palette/overlay hint). */
export function formatSeqHint(seq: string): string {
  return seq
    .split(" ")
    .map((k) => k.toUpperCase())
    .join(" ");
}

/** The letter that follows the `g` prefix (`"g d"` → `"d"`), lower-cased. */
function seqSecondKey(seq: string): string {
  return (seq.split(" ")[1] ?? "").toLowerCase();
}

// Second-key → effect, derived once from the single-source `seq` fields.
const NAV_SEQUENCE_EFFECTS: Readonly<Record<string, CommandEffect>> = {
  ...Object.fromEntries(
    NAV_ITEMS.filter((i) => i.seq).map((i) => [
      seqSecondKey(i.seq as string),
      { kind: "navigate", href: i.href } as CommandEffect,
    ]),
  ),
  [seqSecondKey(ASK_AGENT_SEQ)]: { kind: "openChat" },
};

// Admin-only second keys (`g a` → Analytics), resolved only when `ctx.isAdmin`.
const ADMIN_SEQUENCE_EFFECTS: Readonly<Record<string, CommandEffect>> =
  Object.fromEntries(
    ADMIN_NAV_ITEMS.filter((i) => i.seq).map((i) => [
      seqSecondKey(i.seq as string),
      { kind: "navigate", href: i.href } as CommandEffect,
    ]),
  );

/**
 * Pure keystroke → sequence outcome, the DOM-free companion to `resolveShortcut`.
 * `armed === false` → the arm phase: a bare `g` (no modifier, not editable)
 * returns `"arm"`; anything else `null`. `armed === true` → the resolve phase: a
 * mapped second key returns its `CommandEffect` (admin-gated for `g a`); an
 * unmapped key / second `g` / chord / editable focus returns `null` (the caller
 * clears the prefix and lets the key fall through to its own binding). Auto-repeat
 * never arms or resolves. Shares `isEditable` with `resolveShortcut` so both are
 * tested without a DOM. The 1500 ms expiry is the caller's concern (it tracks the
 * arm timestamp; a pure matcher cannot see wall-clock).
 */
export function resolveSequence(
  armed: boolean,
  e: ShortcutKeyEvent,
  ctx: ShortcutContext,
): CommandEffect | "arm" | null {
  if (isEditable(e.target)) return null;
  if (e.repeat) return null;
  const mod = e.metaKey || e.ctrlKey;
  const k = e.key.toLowerCase();
  if (!armed) {
    // Arm phase — only a bare `g` prefix starts a sequence.
    return !mod && k === SEQUENCE_PREFIX ? "arm" : null;
  }
  // Resolve phase — a modifier chord aborts (falls through to resolveShortcut).
  if (mod) return null;
  const navEffect = NAV_SEQUENCE_EFFECTS[k];
  if (navEffect) return navEffect;
  const adminEffect = ADMIN_SEQUENCE_EFFECTS[k];
  if (adminEffect) return ctx.isAdmin ? adminEffect : null;
  return null;
}

// ---------------------------------------------------------------------------
// Super/Meta accelerators (⌘D/⌘I/⌘R/⌘A/⌘C) — the metaKey-only companion layer to
// the `g`-leader, additive and never replacing it. The `accel` field on
// NAV_ITEMS/ADMIN_NAV_ITEMS is the SINGLE source for the accelerator letter: the
// resolver map, the palette accel hint, and the `?` overlay accel row all derive
// from it. Module-private (like NAV_SEQUENCE_EFFECTS) — asserted via behavior.
// ---------------------------------------------------------------------------

// letter → effect, derived once from the single-source `accel` fields.
const NAV_ACCEL_EFFECTS: Readonly<Record<string, CommandEffect>> = {
  ...Object.fromEntries(
    NAV_ITEMS.filter((i) => i.accel).map((i) => [
      (i.accel as string).toLowerCase(),
      { kind: "navigate", href: i.href } as CommandEffect,
    ]),
  ),
  [ASK_AGENT_ACCEL]: { kind: "openChat" },
};

// Admin-only accelerator letters (⌘A → Analytics), resolved only when isAdmin.
const ADMIN_ACCEL_EFFECTS: Readonly<Record<string, CommandEffect>> =
  Object.fromEntries(
    ADMIN_NAV_ITEMS.filter((i) => i.accel).map((i) => [
      (i.accel as string).toLowerCase(),
      { kind: "navigate", href: i.href } as CommandEffect,
    ]),
  );

/**
 * Pure Super/Meta accelerator resolver — the `metaKey`-only sibling of
 * `resolveSequence`. Reads `e.metaKey` EXCLUSIVELY (never `ctrlKey` — Ctrl+letter
 * on Win/Linux is a hostile hijack of native shortcuts and must NOT arm; this is
 * the whole point of the guarded design, distinct from `resolveShortcut`'s
 * `metaKey || ctrlKey` union). Rejects the shift variant (⌘⇧D is a distinct
 * chord), editable focus (native ⌘C/⌘A/⌘R survive in inputs), and auto-repeat.
 * `⌘A` (Analytics) is admin-gated, mirroring `resolveSequence`. Returns the
 * CommandEffect (the caller `preventDefault`s + runs it) or null (fall through to
 * the g-leader arm). Stays DOM-free — the ⌘C selection-yield lives in the LISTENER.
 *
 * NOTE on ⌥/Alt: on macOS Option transforms `e.key` (⌘⌥D → "∂") so an Alt chord
 * never matches a letter here; on Win/Linux Alt does NOT transform the key, so
 * `Meta+Alt+D` would technically match — but that combo is harmless (navigates, no
 * data-loss) and, since the accelerators are a macOS feature in practice
 * (Win+letter / Super+letter are OS/WM-reserved, which is WHY the HINT is gated to
 * Apple), it is accepted-unguarded, not silently wrong. No `altKey` widening.
 * NOTE on ⌘R: `preventDefault` stops the SOFT reload; ⌘⇧R (hard reload) still
 * fires — an acceptable escape hatch, not a gap.
 */
export function resolveNavChord(
  e: ShortcutKeyEvent,
  ctx: ShortcutContext,
): CommandEffect | null {
  if (isEditable(e.target)) return null; // native ⌘C/⌘A/⌘R survive in inputs
  if (e.repeat) return null;
  if (!e.metaKey) return null; // metaKey ONLY, never ctrlKey
  if (e.shiftKey) return null; // ⌘⇧<letter> is a distinct chord
  const k = e.key.toLowerCase();
  const navEffect = NAV_ACCEL_EFFECTS[k];
  if (navEffect) return navEffect;
  const adminEffect = ADMIN_ACCEL_EFFECTS[k];
  if (adminEffect) return ctx.isAdmin ? adminEffect : null;
  return null;
}

/**
 * The static command registry (navigation + hero actions). Routine and KB-doc
 * commands are async (fetched when the palette opens) and built in the palette
 * component — they are not part of this synchronous static set.
 */
export function buildCommands(
  ctx: ShortcutContext,
  // Display-only: picks the modifier glyph for chord hints (⌘ vs Ctrl). Defaults
  // to non-Apple so SSR / no-navigator renders the stable `Ctrl` form the
  // provider then syncs post-hydration. NOT part of ShortcutContext — the pure
  // resolvers must never see platform.
  opts?: { isApplePlatform?: boolean },
): Command[] {
  const isApple = opts?.isApplePlatform ?? false;
  // Primary nav + admin stay in the root "Navigation" group. Settings
  // destinations get their OWN "Settings" group, surfaced behind the palette's
  // Settings drill-in sub-page (not flat in the root) — see command-palette.tsx.
  const nav: Command[] = [...NAV_ITEMS, ...(ctx.isAdmin ? ADMIN_NAV_ITEMS : [])].map(
    (item) => ({
      id: `nav:${item.href}`,
      label: item.label,
      group: "Navigation" as const,
      // Key hint derived from the single-source `seq` field (`"g d"` → `G D`).
      ...(item.seq ? { keys: formatSeqHint(item.seq) } : {}),
      run: () => ({ kind: "navigate" as const, href: item.href }),
    }),
  );

  const settings: Command[] = SETTINGS_NAV_ITEMS.map((item) => ({
    id: `settings:${item.href}`,
    label: item.label,
    group: "Settings" as const,
    run: () => ({ kind: "navigate" as const, href: item.href }),
  }));

  const actions: Command[] = [
    {
      id: "ask-agent",
      label: "Ask an agent",
      group: "Ask an agent",
      // Show the GLOBAL summon binding (`G C`), not the palette-only `⌘↵` — the
      // latter only fires with the palette already open.
      keys: formatSeqHint(ASK_AGENT_SEQ),
      run: () => ({ kind: "openChat" as const }),
    },
    {
      id: "toggle-sidebar",
      label: "Toggle sidebar",
      group: "General",
      keys: modChord("B", isApple),
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

  return [...nav, ...settings, ...actions];
}

// ---------------------------------------------------------------------------
// Provider — the single source of truth for palette/help open state, the ONE
// global keydown listener, and `shortcutsEnabled`. Mounted in the dashboard
// layout wrapping {children}; the palette + overlay components are siblings the
// layout composes (they read this context). Palette `open` state lives HERE,
// never lifted into the layout's useState cluster, so unrelated layout state
// changes (drawerOpen/railWidth/…) do not re-render every context consumer.
// ---------------------------------------------------------------------------

import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useRef,
  useState,
} from "react";
import { useRouter } from "next/navigation";

// A device-local sync channel: the Settings toggle writes localStorage and
// dispatches this so a live provider re-reads without a page reload (storage
// events do not fire in the same document that wrote the value).
export const SHORTCUTS_CHANGED_EVENT = "soleur:shortcuts-changed";

export type ShortcutsContextValue = {
  /** Whether the command layer is active (feature flag + not torn down). */
  enabled: boolean;
  paletteOpen: boolean;
  helpOpen: boolean;
  openPalette: () => void;
  closePalette: () => void;
  openHelp: () => void;
  closeHelp: () => void;
  isAdmin: boolean;
  shortcutsEnabled: boolean;
  /**
   * Whether the device is an Apple platform — DISPLAY ONLY (picks ⌘ vs Ctrl for
   * key hints). SSR-safe: false on the server, synced post-hydration so the
   * glyph never mismatches. Consumers pass it to `modChord` / `buildCommands`.
   */
  isApplePlatform: boolean;
  /** Interpret a serializable CommandEffect (navigate / chat / help / sidebar). */
  runEffect: (effect: CommandEffect) => void;
};

const ShortcutsContext = createContext<ShortcutsContextValue | null>(null);

export function useShortcuts(): ShortcutsContextValue {
  const ctx = useContext(ShortcutsContext);
  if (!ctx) {
    throw new Error(
      "useShortcuts must be used inside <ShortcutsProvider> (wired in app/(dashboard)/layout.tsx)",
    );
  }
  return ctx;
}

export function ShortcutsProvider({
  enabled,
  isAdmin,
  onToggleSidebar,
  onEscape,
  children,
}: {
  /** Feature-flag gate. When false, no listener binds and no overlay opens. */
  enabled: boolean;
  isAdmin: boolean;
  /** ⌘B — toggles the layout-owned sidebar collapse. */
  onToggleSidebar: () => void;
  /** Esc with no overlay open — closes the layout-owned mobile drawer (FR5). */
  onEscape?: () => void;
  children: React.ReactNode;
}) {
  const router = useRouter();
  const [paletteOpen, setPaletteOpen] = useState(false);
  const [helpOpen, setHelpOpen] = useState(false);
  // SSR-safe: init ON (matches server render), then sync the device-local pref
  // post-hydration so the ⌘ glyph / listener decision never mismatches.
  const [shortcutsEnabled, setShortcutsEnabled] = useState(true);
  // SSR-safe: init non-Apple (→ `Ctrl` glyph, matches the server render), then
  // read the real platform post-hydration. A one-frame `Ctrl`→`⌘` correction on
  // Apple is acceptable and never the reverse, so no hydration mismatch warning.
  const [applePlatform, setApplePlatform] = useState(false);

  useEffect(() => {
    const sync = () => setShortcutsEnabled(readShortcutsEnabled());
    sync();
    window.addEventListener(SHORTCUTS_CHANGED_EVENT, sync);
    return () => window.removeEventListener(SHORTCUTS_CHANGED_EVENT, sync);
  }, []);

  // Platform is stable for the session; read it once post-hydration.
  useEffect(() => {
    setApplePlatform(isApplePlatform());
  }, []);

  const openPalette = useCallback(() => setPaletteOpen(true), []);
  const closePalette = useCallback(() => setPaletteOpen(false), []);
  const openHelp = useCallback(() => setHelpOpen(true), []);
  const closeHelp = useCallback(() => setHelpOpen(false), []);

  const runEffect = useCallback(
    (effect: CommandEffect) => {
      switch (effect.kind) {
        case "navigate":
          setPaletteOpen(false);
          router.push(effect.href);
          break;
        case "openChat":
          setPaletteOpen(false);
          router.push(
            effect.query
              ? `/dashboard/chat/new?q=${encodeURIComponent(effect.query)}`
              : "/dashboard/chat/new",
          );
          break;
        case "openHelp":
          setPaletteOpen(false);
          setHelpOpen(true);
          break;
        case "toggleSidebar":
          setPaletteOpen(false);
          onToggleSidebar();
          break;
        case "runRoutine":
          // Routine dispatch is async (confirm flow) and owned by the palette
          // component, which intercepts this effect before reaching runEffect.
          break;
      }
    },
    [router, onToggleSidebar],
  );

  // ONE global listener, registered once. Live state is read through a ref so
  // the listener never re-subscribes (TR2: a single global keydown listener).
  const stateRef = useRef({
    enabled,
    shortcutsEnabled,
    paletteOpen,
    helpOpen,
    isAdmin,
    onToggleSidebar,
    onEscape,
    runEffect,
  });
  stateRef.current = {
    enabled,
    shortcutsEnabled,
    paletteOpen,
    helpOpen,
    isAdmin,
    onToggleSidebar,
    onEscape,
    runEffect,
  };

  // The pending "go-to" prefix as its arm timestamp (null = none), held in a ref
  // so the ONE listener never re-subscribes (TR2). Armed by `g`; resolved/cleared
  // on the next key. Expiry is `Date.now() - armedAt > SEQUENCE_WINDOW_MS`.
  const pendingPrefixRef = useRef<number | null>(null);

  useEffect(() => {
    function handleKeyDown(e: KeyboardEvent) {
      const s = stateRef.current;
      // `shortcutsEnabled` is the WCAG SC 2.1.4 turn-off — when off it disables
      // the WHOLE listener (⌘K/⌘//?/⌘B AND the go-to sequences), per FR9/AC10.
      if (!s.shortcutsEnabled) return;
      // Auto-repeat (held key) never arms, advances, or clears a sequence.
      if (e.repeat) return;
      // A lone modifier keydown (Shift/Ctrl/Alt/Meta) is never a shortcut and must
      // not clear a pending prefix — so `g` then Shift-hold then `d` still works.
      if (
        e.key === "Shift" ||
        e.key === "Control" ||
        e.key === "Alt" ||
        e.key === "Meta"
      )
        return;

      // --- Pending go-to prefix: resolve or clear. Runs BEFORE the Escape
      // drawer branch and the chord matcher so `g` then <key> is handled as one
      // sequence (FR1). ---
      const armedAt = pendingPrefixRef.current;
      if (armedAt !== null) {
        // The second key always ends the sequence, mapped or not.
        pendingPrefixRef.current = null;
        if (Date.now() - armedAt <= SEQUENCE_WINDOW_MS) {
          const effect = resolveSequence(true, e, { isAdmin: s.isAdmin });
          // `armed === true` cannot return "arm" at runtime, but the union type
          // includes it — the `!== "arm"` check narrows it out for `runEffect`.
          if (effect && effect !== "arm") {
            e.preventDefault();
            s.runEffect(effect);
            return;
          }
          // Escape aborts the prefix and is SWALLOWED so it does not also close
          // the mobile drawer (AC9). Any other unmapped key falls through below
          // so it still runs its own binding (`g` then `⌘K` opens the palette).
          if (e.key === "Escape") {
            e.preventDefault();
            return;
          }
        }
        // Expired, or unmapped non-Escape key: prefix cleared; fall through and
        // handle THIS key normally.
      }

      // Esc closes the mobile drawer ONLY when no overlay is layered above it
      // (the palette/help own their own Esc via Radix). Not gated by isEditable
      // — Esc must escape an input too. A pre-existing capability, not flag-gated.
      if (e.key === "Escape") {
        if (!s.paletteOpen && !s.helpOpen) s.onEscape?.();
        return;
      }
      const action = resolveShortcut(e);
      if (action) {
        // The palette + help overlay are the NEW flag-gated surfaces. ⌘B (sidebar
        // toggle) is a pre-existing capability (since #2415) migrated into this one
        // listener — it must keep working even when the command-palette flag is OFF,
        // so it is NOT gated on `enabled` (only on `shortcutsEnabled`, above).
        if (action === "openPalette") {
          if (!s.enabled) return;
          e.preventDefault();
          setPaletteOpen(true);
        } else if (action === "openHelp") {
          if (!s.enabled) return;
          e.preventDefault();
          setHelpOpen(true);
        } else if (action === "toggleSidebar") {
          e.preventDefault();
          s.onToggleSidebar();
        }
        return;
      }

      // --- Super/Meta accelerators (metaKey-only). AFTER resolveShortcut so
      // ⌘K=palette / ⌘B=sidebar stay authoritative; BEFORE the g-leader arm.
      // NEW flag-gated bindings → gated on `enabled`; suppressed while the
      // palette/help overlay is open. ---
      if (s.enabled && !s.paletteOpen && !s.helpOpen) {
        // Resolve FIRST (pure, exits instantly on !metaKey for ordinary typing);
        // the DOM query then runs ONLY on an actual accelerator match — matching
        // the g-arm's "cheap, only on match" discipline (DHH #1 + code-simplicity).
        const navEffect = resolveNavChord(e, { isAdmin: s.isAdmin });
        if (navEffect) {
          // ⌘C YIELDS to native copy when the user has an ACTIVE selection —
          // copying agent/KB/code output is a core reading gesture and isEditable
          // does NOT cover a selection in a plain <p>/<div> (focus on body). No
          // selection → ⌘C opens chat as bound. The resolver stays DOM-free; this
          // selection read lives in the listener (CPO #1 / Kieran P1 / spec-flow /
          // user-impact). Scoped to openChat (⌘C) only. `!isCollapsed` (not
          // `toString() !== ""`) so a NON-text selection (image / rich node) also
          // yields to native copy (user-impact Finding 2).
          const sel =
            typeof window !== "undefined" ? window.getSelection() : null;
          const yieldToCopy =
            navEffect.kind === "openChat" && !!sel && !sel.isCollapsed;
          // Suppress under any app modal (a nav-away would discard unsaved input)
          // — parity with the g-arm guard. preventDefault stops the native
          // ⌘D/⌘R/⌘A/⌘C data-loss action.
          if (
            !yieldToCopy &&
            !document.querySelector('[role="dialog"][aria-modal="true"]')
          ) {
            e.preventDefault();
            s.runEffect(navEffect);
            return;
          }
        }
      }

      // --- Arm a new go-to prefix on `g`. Gated on the command-palette flag
      // (`enabled`) — these are new flag-gated bindings — AND suppressed while the
      // palette/help overlay is open. ---
      if (s.enabled && !s.paletteOpen && !s.helpOpen) {
        if (resolveSequence(false, e, { isAdmin: s.isAdmin }) === "arm") {
          // Also suppress while ANY app modal is open (generalizes FR7 beyond
          // palette/help): a go-sequence fired from a button inside a modal —
          // where focus is non-editable — would navigate away and silently
          // discard the modal's unsaved input. Cheap: only runs on a `g` press.
          if (document.querySelector('[role="dialog"][aria-modal="true"]'))
            return;
          e.preventDefault();
          pendingPrefixRef.current = Date.now();
        }
      }
    }
    document.addEventListener("keydown", handleKeyDown);
    return () => document.removeEventListener("keydown", handleKeyDown);
  }, []);

  const value = useMemo<ShortcutsContextValue>(
    () => ({
      enabled,
      paletteOpen,
      helpOpen,
      openPalette,
      closePalette,
      openHelp,
      closeHelp,
      isAdmin,
      shortcutsEnabled,
      isApplePlatform: applePlatform,
      runEffect,
    }),
    [
      enabled,
      paletteOpen,
      helpOpen,
      openPalette,
      closePalette,
      openHelp,
      closeHelp,
      isAdmin,
      shortcutsEnabled,
      applePlatform,
      runEffect,
    ],
  );

  return (
    <ShortcutsContext.Provider value={value}>
      {children}
    </ShortcutsContext.Provider>
  );
}
