"use client";

import { useEffect } from "react";
import { subscribeToPush } from "@/lib/push-subscription";
import {
  hasSwResetFlag,
  unregisterAllAndClearCaches,
  cleanResetUrl,
} from "@/lib/pwa/sw-reset";

export function SwRegister() {
  useEffect(() => {
    if ("serviceWorker" in navigator) {
      // Kill switch (ADR-137 brand-survival recovery): if a bad worker bricks the
      // installed app, `?sw-reset` on any URL wipes all workers + caches and
      // reloads clean. Runs BEFORE (re)registration so a broken worker is torn
      // down rather than re-registered.
      if (hasSwResetFlag()) {
        unregisterAllAndClearCaches().finally(() => {
          window.location.replace(cleanResetUrl());
        });
        return;
      }
      navigator.serviceWorker
        .register("/sw.js", { scope: "/", updateViaCache: "none" })
        .then((registration) => {
          // Chain push subscription if permission already granted
          if (Notification.permission === "granted") {
            registration.pushManager.getSubscription().then((existing) => {
              if (!existing) {
                subscribeToPush(registration).catch(() => {
                  // Non-fatal: push is a progressive enhancement
                });
              }
            });
          }
        })
        .catch((err) => {
          // Non-fatal: app works without SW, just no caching
          console.warn("SW registration failed:", err);
        });
    }
  }, []);

  return null;
}
