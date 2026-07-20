// feat-super-key-nav-shortcuts (Option A′) — platform detection for the DISPLAY
// glyph only. The command layer BINDS `mod = metaKey || ctrlKey` cross-platform
// (use-shortcuts.tsx:88) and navigates via the `g`-leader; this helper decides
// solely whether the hint reads `⌘K` (Apple) or `Ctrl+K` (everywhere else), so a
// Windows/Linux user is no longer shown a `⌘` key they do not have. It is NEVER
// read inside a resolver (the resolvers stay pure/DOM-free per ADR discipline).

/** The subset of `navigator` this helper reads — injectable for DOM-free tests. */
export type NavigatorLike = {
  readonly platform?: string;
  readonly userAgent?: string;
};

/**
 * Pure, SSR-safe Apple-platform check. Pass a navigator shape to test without a
 * DOM; omit it to read the ambient `globalThis.navigator`. Returns the stable
 * `false` (→ `Ctrl`) default whenever no navigator is available (SSR, node), so
 * the first server paint and a no-navigator environment never render a `⌘` the
 * provider would then have to correct — it only ever corrects `Ctrl`→`⌘`, never
 * the reverse (matches the init-default-then-sync hydration pattern).
 */
export function isApplePlatform(nav?: NavigatorLike | null): boolean {
  const n =
    nav === undefined
      ? (globalThis.navigator as NavigatorLike | undefined)
      : nav;
  if (!n) return false;
  const haystack = `${n.platform ?? ""} ${n.userAgent ?? ""}`;
  return /Mac|iPhone|iPad|iPod/i.test(haystack);
}

/**
 * Format a single-letter modifier chord for DISPLAY: `⌘K` on Apple (glyph, no
 * separator — the native convention), `Ctrl+K` elsewhere. `letter` is rendered
 * verbatim (`"K"`, `"/"`, `"B"`).
 */
export function modChord(letter: string, isApple: boolean): string {
  return isApple ? `⌘${letter}` : `Ctrl+${letter}`;
}

/**
 * Format a modifier+Shift chord for DISPLAY: `⌘⇧L` on Apple, `Ctrl+Shift+L`
 * elsewhere. Used for the KB "Quote in chat" shortcut, which binds on
 * `(meta || ctrl) + shift + <letter>` cross-platform.
 */
export function modShiftChord(letter: string, isApple: boolean): string {
  return isApple ? `⌘⇧${letter}` : `Ctrl+Shift+${letter}`;
}
