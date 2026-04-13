"use client";

import { useEffect } from "react";
import { subscribeToPush } from "@/lib/push-subscription";

export function SwRegister() {
  useEffect(() => {
    if ("serviceWorker" in navigator) {
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
