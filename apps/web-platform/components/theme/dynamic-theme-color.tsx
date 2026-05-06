"use client";

import { useEffect } from "react";
import { useTheme } from "./theme-provider";

const FORGE = "#0a0a0a";
const RADIANCE = "#fbf7ee";

/**
 * Keeps the <meta name="theme-color"> tag in sync with the resolved theme so
 * mobile browser chrome (Safari iOS address bar, Android status bar, PWA
 * shell) matches the rendered surface.
 *
 * Mounted under <ThemeProvider> in the root layout. The static viewport.themeColor
 * fallback in app/layout.tsx covers the pre-hydration window.
 */
export function DynamicThemeColor() {
  const { resolvedTheme } = useTheme();

  useEffect(() => {
    let meta = document.querySelector<HTMLMetaElement>('meta[name="theme-color"]');
    if (!meta) {
      meta = document.createElement("meta");
      meta.name = "theme-color";
      document.head.appendChild(meta);
    }
    meta.content = resolvedTheme === "light" ? RADIANCE : FORGE;
  }, [resolvedTheme]);

  return null;
}
