"use client";

import { useState, useCallback } from "react";
import { subscribeToPush } from "@/lib/push-subscription";

const STORAGE_KEY = "notification-prompt-seen";
const MAX_SHOWS = 2;

function isIosSafariNotPwa(): boolean {
  if (typeof navigator === "undefined") return false;
  const ua = navigator.userAgent;
  const isIos = /iPhone|iPad|iPod/.test(ua);
  const isStandalone =
    ("standalone" in navigator && (navigator as { standalone?: boolean }).standalone) ||
    window.matchMedia("(display-mode: standalone)").matches;
  return isIos && !isStandalone;
}

function getShowCount(): number {
  try {
    return parseInt(localStorage.getItem(STORAGE_KEY) ?? "0", 10) || 0;
  } catch {
    return 0;
  }
}

function incrementShowCount(): void {
  try {
    localStorage.setItem(STORAGE_KEY, String(getShowCount() + 1));
  } catch {
    // localStorage unavailable
  }
}

function markPermanentlyDismissed(): void {
  try {
    localStorage.setItem(STORAGE_KEY, String(MAX_SHOWS));
  } catch {
    // localStorage unavailable
  }
}

type PromptState = "default" | "granted" | "denied";

interface NotificationPromptProps {
  visible: boolean;
}

export function NotificationPrompt({ visible }: NotificationPromptProps) {
  const [state, setState] = useState<PromptState>("default");
  const [dismissed, setDismissed] = useState(false);

  const handleEnable = useCallback(async () => {
    const permission = await Notification.requestPermission();
    if (permission === "granted") {
      setState("granted");
      markPermanentlyDismissed();
      // Subscribe via service worker
      const registration = await navigator.serviceWorker.ready;
      await subscribeToPush(registration);
      // Auto-dismiss after brief success message
      setTimeout(() => setDismissed(true), 2000);
    } else {
      setState("denied");
      markPermanentlyDismissed();
    }
  }, []);

  const handleDismiss = useCallback(() => {
    incrementShowCount();
    setDismissed(true);
  }, []);

  if (!visible || dismissed) return null;

  // Already at max shows or permission already decided
  if (typeof window !== "undefined") {
    if (getShowCount() >= MAX_SHOWS) return null;
    if (Notification.permission === "granted") return null;
  }

  // iOS Safari without PWA: can't do Web Push
  if (isIosSafariNotPwa()) {
    return (
      <div className="mt-3 flex w-full items-start gap-3 rounded-xl border border-blue-800/40 bg-blue-950/30 p-4">
        <BellIcon />
        <div className="flex-1">
          <p className="text-sm font-semibold text-white">
            Install Soleur for push notifications
          </p>
          <p className="mt-1 text-sm text-neutral-400">
            Add Soleur to your home screen to receive notifications when agents
            need your input.
          </p>
        </div>
        <DismissButton onClick={handleDismiss} />
      </div>
    );
  }

  if (state === "granted") {
    return (
      <div className="mt-3 flex w-full items-center gap-3 rounded-xl border border-green-800/40 bg-green-950/30 p-4">
        <CheckIcon />
        <p className="text-sm text-green-300">
          Notifications enabled — you&apos;ll be alerted when agents need you.
        </p>
      </div>
    );
  }

  if (state === "denied") {
    return (
      <div className="mt-3 flex w-full items-start gap-3 rounded-xl border border-blue-800/40 bg-blue-950/30 p-4">
        <BellIcon />
        <div className="flex-1">
          <p className="text-sm text-neutral-400">
            No problem — we&apos;ll email you instead when agents need your input.
          </p>
        </div>
        <DismissButton onClick={() => setDismissed(true)} />
      </div>
    );
  }

  // Default state: ask for permission
  return (
    <div className="mt-3 flex w-full items-start gap-3 rounded-xl border border-blue-800/40 bg-blue-950/30 p-4">
      <BellIcon />
      <div className="flex-1">
        <p className="text-sm font-semibold text-white">
          Agents need you even when you&apos;re away.
        </p>
        <p className="mt-1 text-sm text-neutral-400">
          Enable notifications so you never miss a decision that blocks progress.
        </p>
        <div className="mt-3 flex items-center gap-3">
          <button
            type="button"
            onClick={handleEnable}
            className="rounded-lg bg-blue-600 px-4 py-1.5 text-sm font-medium text-white transition-colors hover:bg-blue-500"
          >
            Enable notifications
          </button>
          <button
            type="button"
            onClick={handleDismiss}
            className="text-sm text-neutral-500 transition-colors hover:text-neutral-300"
          >
            Not now
          </button>
        </div>
      </div>
      <DismissButton onClick={handleDismiss} />
    </div>
  );
}

function DismissButton({ onClick }: { onClick: () => void }) {
  return (
    <button
      type="button"
      onClick={onClick}
      className="shrink-0 rounded p-1 text-neutral-500 transition-colors hover:text-neutral-300"
      aria-label="Dismiss notification prompt"
    >
      <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
        <line x1="18" y1="6" x2="6" y2="18" />
        <line x1="6" y1="6" x2="18" y2="18" />
      </svg>
    </button>
  );
}

function BellIcon() {
  return (
    <span className="mt-0.5 text-blue-400">
      <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
        <path d="M18 8A6 6 0 0 0 6 8c0 7-3 9-3 9h18s-3-2-3-9" />
        <path d="M13.73 21a2 2 0 0 1-3.46 0" />
      </svg>
    </span>
  );
}

function CheckIcon() {
  return (
    <span className="text-green-400">
      <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
        <polyline points="20 6 9 17 4 12" />
      </svg>
    </span>
  );
}
