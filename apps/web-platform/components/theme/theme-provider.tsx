"use client";

import {
  createContext,
  useContext,
  useEffect,
  useState,
  useCallback,
  useMemo,
} from "react";

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

type ThemeContextValue = {
  theme: Theme;
  resolvedTheme: ResolvedTheme;
  setTheme(next: Theme): void;
};

const ThemeContext = createContext<ThemeContextValue | null>(null);

export function ThemeProvider({ children }: { children: React.ReactNode }) {
  // Initial state is "system" on every render (server + first client paint)
  // to keep SSR markup identical and avoid hydration drift. The post-mount
  // effect below replaces it with the persisted choice. The no-FOUC inline
  // script in app/layout.tsx has already set <html data-theme=...> before
  // React mounted, so the visual surface stays correct during this swap.
  const [theme, setThemeState] = useState<Theme>("system");
  const [resolvedTheme, setResolvedTheme] = useState<ResolvedTheme>("dark");

  // Hydrate from localStorage + sync data-theme on mount.
  useEffect(() => {
    const stored = readStoredTheme();
    setThemeState(stored);
    setResolvedTheme(stored === "system" ? getSystemPreference() : stored);
  }, []);

  // Apply data-theme on the html element + dynamic theme-color whenever theme
  // changes. Done in a separate effect so it also runs after hydration when
  // the stored value differs from the default "system".
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
    } catch {
      // Persistence failed (quota, private mode) — in-memory state still
      // applies for the current session, which is acceptable degradation.
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
