"use client";

import {
  createContext,
  useContext,
  useEffect,
  useRef,
  useState,
  useCallback,
  useMemo,
} from "react";
import { reportSilentFallback } from "@/lib/client-observability";
import {
  NO_TRANSITION_CSS_TEXT,
  NO_TRANSITION_STYLE_ID,
} from "@/components/theme/no-transition-contract";

export type Theme = "dark" | "light" | "system";
export type ResolvedTheme = "dark" | "light";

const THEMES: readonly Theme[] = ["dark", "light", "system"] as const;

const STORAGE_KEY = "soleur:theme";

function isTheme(value: unknown): value is Theme {
  return typeof value === "string" && (THEMES as readonly string[]).includes(value);
}

function readStoredTheme(): Theme {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (isTheme(raw)) return raw;
  } catch {
    // localStorage unavailable (private mode, SSR, disabled cookies).
  }
  return "system";
}

/**
 * Suppress CSS transitions and keyframe animations for one paint frame.
 *
 * Theme switches re-resolve every `var(--soleur-*)` token that surfaces
 * consume; surfaces with `transition-colors` (theme-toggle squares, active
 * nav indicator, conversations-rail rows, chat bubbles) animate the change
 * over Tailwind's default 150ms while the body and non-transitioning
 * surfaces snap instantly. The user perceives this as different parts of
 * the page changing theme at different speeds.
 *
 * Mirrors `next-themes`' `disableTransitionOnChange` pattern: inject a
 * transient `<style>` with `transition: none !important;` BEFORE the
 * `data-theme` attribute flips, force a synchronous style recalc so the
 * override is committed, then remove the style on the next paint via
 * double-rAF. Browsers commit the theme change as a single paint with no
 * transition cascade.
 *
 * Also forces `animation-duration: 0s !important;` because `globals.css`
 * declares a `pulse-border` keyframe used by `.message-bubble-active` —
 * without this rule, an in-progress pulse would mid-animate during a
 * theme switch.
 *
 * No-op on the server.
 */
function disableTransitionsForOneFrame(): void {
  if (typeof document === "undefined") return;
  // Bail if a previous call (e.g., the inline boot script's transient
  // style, or a fast user toggle within the same frame) already injected
  // the override. The existing element is on its own rAF cleanup
  // schedule — we do not extend it here.
  if (document.getElementById(NO_TRANSITION_STYLE_ID)) return;

  const style = document.createElement("style");
  style.id = NO_TRANSITION_STYLE_ID;
  style.textContent = NO_TRANSITION_CSS_TEXT;
  document.head.appendChild(style);

  // Force a synchronous style recalc so the override is committed BEFORE
  // the data-theme attribute change. Reading getComputedStyle on a
  // non-pseudo element is the standard reflow-forcing trick; opacity is
  // cheap to read and defends against dead-code-elimination.
  if (typeof window !== "undefined" && document.body) {
    void window.getComputedStyle(document.body).opacity;
  }

  // Double-rAF cleanup: gives the browser one full frame to commit the
  // theme change without animation, then removes the override on the
  // following frame. Resolve via globalThis so test stubs (vi.stubGlobal)
  // override the lookup; a bare `requestAnimationFrame` reference may bind
  // to the host's native function past property writes on globalThis.
  function schedule(cb: FrameRequestCallback): void {
    const g = globalThis as unknown as {
      requestAnimationFrame?: (cb: FrameRequestCallback) => number;
    };
    if (typeof g.requestAnimationFrame === "function") {
      g.requestAnimationFrame(cb);
      return;
    }
    setTimeout(() => cb(0), 0);
  }
  schedule(() => {
    schedule(() => {
      const existing = document.getElementById(NO_TRANSITION_STYLE_ID);
      if (existing) existing.remove();
    });
  });
}

function getSystemPreference(): ResolvedTheme {
  if (typeof window === "undefined" || typeof window.matchMedia !== "function") {
    return "dark";
  }
  return window.matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light";
}

function resolveInitial(theme: Theme): ResolvedTheme {
  if (theme === "system") return getSystemPreference();
  return theme;
}

type ThemeContextValue = {
  theme: Theme;
  resolvedTheme: ResolvedTheme;
  setTheme(next: Theme): void;
};

const ThemeContext = createContext<ThemeContextValue | null>(null);

export function ThemeProvider({ children }: { children: React.ReactNode }) {
  // Lazy initializers read localStorage / matchMedia on first client render
  // so the post-hydration paint already matches the persisted choice — no
  // extra effect-driven swap, no flicker. SSR (where window is undefined)
  // falls back to "system" + dark; the hydration mismatch on <html
  // data-theme> set by the no-FOUC inline script is silenced via
  // suppressHydrationWarning in app/layout.tsx.
  // INVARIANT: the inline <NoFoucScript> in app/layout.tsx <head> has already
  // written document.documentElement.dataset.theme before React mounts. This
  // provider's first paint and that script must agree on the value or the
  // user sees a one-frame flash.
  const [theme, setThemeState] = useState<Theme>(() =>
    typeof window === "undefined" ? "system" : readStoredTheme(),
  );
  const [resolvedTheme, setResolvedTheme] = useState<ResolvedTheme>(() =>
    typeof window === "undefined" ? "dark" : resolveInitial(readStoredTheme()),
  );

  // Apply data-theme on the html element whenever theme changes. The first
  // run on mount writes the attribute (covers the narrow window where the
  // inline script wrote a stale value vs. another tab) but intentionally
  // skips disableTransitionsForOneFrame: the inline <NoFoucScript> already
  // owns the boot-frame transition-disable cleanup, and the helper would
  // no-op anyway via its bail guard while the boot-script's <style> is
  // still alive. Skipping the call avoids an unnecessary createElement +
  // reflow round on first mount.
  const prevThemeRef = useRef<Theme | null>(null);
  useEffect(() => {
    if (prevThemeRef.current === theme) return;
    if (prevThemeRef.current !== null) {
      disableTransitionsForOneFrame();
    }
    document.documentElement.dataset.theme = theme;
    prevThemeRef.current = theme;
  }, [theme]);

  // Re-assert html.style.colorScheme whenever the resolved palette flips.
  // The inline boot script seeds colorScheme once at first paint; without
  // re-assertion here, a user who boots Dark and toggles Light keeps
  // `style.colorScheme = "dark"` permanently because nothing in the CSS
  // cascade declares `color-scheme` for our data-theme blocks. Inline
  // style beats stylesheet, so this assignment is the only path that
  // updates UA-rendered widgets (scrollbars, form controls, default <body>
  // background) after the boot frame.
  useEffect(() => {
    document.documentElement.style.colorScheme = resolvedTheme;
  }, [resolvedTheme]);

  // Live OS-change listener: only matters when theme === "system". The CSS
  // @media (prefers-color-scheme) block in globals.css already handles the
  // visual swap; this effect updates `resolvedTheme` so consumers (e.g. the
  // dynamic <meta name="theme-color"> updater) stay in sync.
  useEffect(() => {
    if (theme !== "system") {
      setResolvedTheme(theme);
      return;
    }
    if (typeof window === "undefined" || typeof window.matchMedia !== "function") {
      return;
    }
    const mq = window.matchMedia("(prefers-color-scheme: dark)");
    setResolvedTheme(mq.matches ? "dark" : "light");
    const handler = (e: { matches: boolean }) => {
      // OS flipped under "system" — same instant-switch invariant.
      disableTransitionsForOneFrame();
      setResolvedTheme(e.matches ? "dark" : "light");
    };
    mq.addEventListener("change", handler);
    return () => mq.removeEventListener("change", handler);
  }, [theme]);

  // Cross-tab sync: another tab's setTheme should be reflected here without
  // requiring a reload. localStorage 'storage' events fire only in OTHER tabs.
  useEffect(() => {
    function onStorage(event: StorageEvent) {
      if (event.key !== STORAGE_KEY) return;
      // newValue=null means the key was removed — reset to default. A
      // non-null value that doesn't match the Theme union means another
      // tab (or extension, or attacker) wrote garbage; fall back to
      // "system" but mirror to Sentry so we notice if it's not isolated.
      if (event.newValue !== null && !isTheme(event.newValue)) {
        reportSilentFallback(null, {
          feature: "theme-provider",
          op: "storage-event",
          extra: { newValue: event.newValue },
          message: "theme-provider received non-Theme storage event value",
        });
      }
      const next = isTheme(event.newValue) ? event.newValue : "system";
      disableTransitionsForOneFrame();
      // No localStorage.setItem here by design — the originating tab
      // already persisted; mirroring the write would cause an event loop.
      setThemeState(next);
    }
    window.addEventListener("storage", onStorage);
    return () => window.removeEventListener("storage", onStorage);
  }, []);

  const setTheme = useCallback((next: Theme) => {
    let changed = false;
    setThemeState((cur) => {
      if (cur === next) return cur;
      changed = true;
      return next;
    });
    if (!changed) return;
    disableTransitionsForOneFrame();
    try {
      localStorage.setItem(STORAGE_KEY, next);
    } catch (err) {
      // Persistence failed (quota, private mode, disabled cookies) —
      // in-memory state still applies for the current session, which is
      // acceptable degradation. Mirror to Sentry so we can detect if the
      // failure mode becomes systemic (browser update, quota explosion).
      reportSilentFallback(err, {
        feature: "theme-provider",
        op: "setItem",
        extra: { theme: next },
      });
    }
  }, []);

  const value = useMemo<ThemeContextValue>(
    () => ({ theme, resolvedTheme, setTheme }),
    [theme, resolvedTheme, setTheme],
  );

  return <ThemeContext.Provider value={value}>{children}</ThemeContext.Provider>;
}

export function useTheme(): ThemeContextValue {
  const ctx = useContext(ThemeContext);
  if (!ctx) {
    throw new Error("useTheme must be used inside <ThemeProvider>");
  }
  return ctx;
}
