import {
  NO_TRANSITION_CSS_TEXT,
  NO_TRANSITION_STYLE_ID,
} from "@/components/theme/no-transition-contract";

/**
 * No-FOUC theme bootstrap. Runs synchronously in <head> BEFORE the React
 * tree mounts so the first paint matches the user's persisted theme. Reads
 * localStorage["soleur:theme"] and:
 *
 *   1. Sets <html data-theme=...> so CSS variables resolve correctly.
 *   2. Writes documentElement.style.colorScheme + style.backgroundColor as
 *      pre-paint hints. These bypass stylesheet load timing entirely —
 *      even if globals.css is still loading, the very first paint matches
 *      the resolved palette and the user does not see a dark-to-light
 *      flash on Light-mode reload. `style.colorScheme` is left set after
 *      cleanup; the runtime <ThemeProvider> re-asserts it on every theme
 *      change so UA-rendered widgets (scrollbars, form controls) follow
 *      the active palette.
 *   3. Injects a transient <style id="__soleur-no-transition"> with
 *      `transition: none` and `animation-duration: 0s`, removed on the
 *      next frame via double-rAF. Prevents first-paint transitions when
 *      React hydrates and consumer components compute their own initial
 *      colors against `transition-colors` utilities. Mirrors the runtime
 *      `disableTransitionsForOneFrame` helper in theme-provider.tsx; both
 *      sides import the id and CSS text from no-transition-contract.ts so
 *      the contract has a single source of truth.
 *
 * Server-rendered as an inline <script>; Next.js 15 will attach the
 * per-request CSP nonce automatically because we render this from a Server
 * Component in app/layout.tsx with `await headers()` already called above.
 *
 * The script is intentionally tiny and dependency-free — anything heavy
 * here delays Time-To-First-Contentful-Paint.
 *
 * Agent-DX: external introspection of the resolved theme should read
 * `documentElement.dataset.theme` (stable, persisted) or
 * `documentElement.style.colorScheme` (re-asserted on every theme change).
 * Do NOT read `documentElement.style.backgroundColor` — it is a transient
 * pre-paint hint cleared on the first cleanup frame.
 *
 * IMPORTANT: the hex literals below MUST match `--soleur-bg-base` for each
 * palette in app/globals.css. The drift-guard test in
 * test/components/theme-no-fouc-script.test.tsx asserts parity at CI time;
 * a brand-guide palette refresh that updates globals.css without updating
 * this file will fail the drift-guard before merge.
 */
const SCRIPT = `(function () {
  try {
    var v = localStorage.getItem("soleur:theme");
    if (v !== "dark" && v !== "light" && v !== "system") {
      v = "system";
    }
    var html = document.documentElement;
    html.dataset.theme = v;

    // Resolve the effective palette for the inline pre-paint hint. For
    // "system", read prefers-color-scheme; matchMedia is synchronous and
    // safe in a head script. Defaults to dark on any failure to mirror the
    // CSS cascade fallback.
    var effective = v;
    if (v === "system") {
      effective = (window.matchMedia &&
        window.matchMedia("(prefers-color-scheme: light)").matches)
        ? "light" : "dark";
    }

    // Pre-paint inline-style hint. colorScheme governs system colors for
    // form controls, scrollbars, and the default <body> background;
    // backgroundColor on <html> ensures the very first paint matches the
    // resolved palette even if the stylesheet is still loading.
    html.style.colorScheme = effective === "light" ? "light" : "dark";
    html.style.backgroundColor = effective === "light" ? "#fbf7ee" : "#0a0a0a";

    // Inject a transient transition-disable override so React's hydration
    // and any first-paint transition-colors consumer doesn't animate from
    // its initial computed value. Removed via double-rAF after first paint.
    // No existence guard — this script is the very first thing to run in
    // <head>; nothing earlier could have injected the same id.
    var s = document.createElement("style");
    s.id = ${JSON.stringify(NO_TRANSITION_STYLE_ID)};
    s.textContent = ${JSON.stringify(NO_TRANSITION_CSS_TEXT)};
    document.head.appendChild(s);

    var cleanup = function () {
      var existing = document.getElementById(${JSON.stringify(NO_TRANSITION_STYLE_ID)});
      if (existing) existing.remove();
      // Clear the inline backgroundColor so subsequent CSS-only theme
      // changes (data-theme writes that update --soleur-bg-base) take
      // effect normally. colorScheme stays — the runtime <ThemeProvider>
      // re-asserts it on every theme change, and the persistent inline
      // hint keeps UA-rendered widgets aligned with the active palette
      // even before React hydrates.
      html.style.backgroundColor = "";
    };
    var raf = window.requestAnimationFrame;
    if (typeof raf === "function") {
      raf(function () { raf(cleanup); });
    } else {
      setTimeout(cleanup, 0);
    }
  } catch (_e) {
    document.documentElement.dataset.theme = "system";
  }
})();`;

export function NoFoucScript({ nonce }: { nonce?: string }) {
  return (
    <script
      // CSP-nonce passthrough: the middleware sets a per-request nonce on
      // the Content-Security-Policy header. Without it, this inline script
      // would be blocked by the script-src 'nonce-...' directive and the
      // page would render with the default (dark) palette regardless of
      // the user's stored preference, defeating the no-FOUC guarantee.
      nonce={nonce}
      // Use dangerouslySetInnerHTML so React renders the script content
      // as-is without escaping. The content is a static string literal —
      // no user input flows into it.
      dangerouslySetInnerHTML={{ __html: SCRIPT }}
    />
  );
}
