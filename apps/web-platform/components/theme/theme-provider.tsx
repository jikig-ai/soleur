"use client";

import {
  createContext,
  useContext,
  useEffect,
  useState,
  useCallback,
  useMemo,
} from "react";
import { reportSilentFallback } from "@/lib/client-observability";

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

  // Apply data-theme on the html element whenever theme changes. Runs once
  // post-mount to harmonise with the lazy initializer above (covers the
  // narrow window where the inline script wrote a stale value before the
  // user changed their preference in another tab).
  useEffect(() => {
    document.documentElement.dataset.theme = theme;
  }, [theme]);

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
      setThemeState(next);
    }
    window.addEventListener("storage", onStorage);
    return () => window.removeEventListener("storage", onStorage);
  }, []);

  const setTheme = useCallback((next: Theme) => {
    setThemeState(next);
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
