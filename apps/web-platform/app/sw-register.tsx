"use client";

import { useEffect } from "react";

export function SwRegister() {
  useEffect(() => {
    if ("serviceWorker" in navigator) {
      navigator.serviceWorker
        .register("/sw.js", { scope: "/", updateViaCache: "none" })
        .catch((err) => {
          // Non-fatal: app works without SW, just no caching
          console.warn("SW registration failed:", err);
        });
    }
  }, []);

  return null;
}
