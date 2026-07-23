// PWA install-affordance helpers: standalone detection, iOS detection, and
// beforeinstallprompt capture. All are browser-only (guard `typeof window`).

/** The (non-standard, Chromium-only) beforeinstallprompt event shape. */
export interface BeforeInstallPromptEvent extends Event {
  readonly platforms: string[];
  prompt: () => Promise<void>;
  readonly userChoice: Promise<{ outcome: "accepted" | "dismissed"; platform: string }>;
}

/** True when the app is running as an installed standalone PWA (any platform). */
export function isStandalone(): boolean {
  if (typeof window === "undefined") return false;
  const displayModeStandalone =
    typeof window.matchMedia === "function" &&
    window.matchMedia("(display-mode: standalone)").matches;
  // iOS Safari exposes navigator.standalone instead of the display-mode query.
  const iosStandalone =
    (window.navigator as Navigator & { standalone?: boolean }).standalone === true;
  return displayModeStandalone || iosStandalone;
}

/** True on iOS/iPadOS (including iPadOS 13+ which masquerades as macOS). */
export function isIos(): boolean {
  if (typeof window === "undefined") return false;
  const ua = window.navigator.userAgent;
  const iosDevice = /iPad|iPhone|iPod/.test(ua);
  const iPadOs = ua.includes("Macintosh") && "ontouchend" in window;
  return iosDevice || iPadOs;
}

/**
 * True on iOS Safari specifically — the only iOS browser that can install a
 * PWA via the Share → Add to Home Screen flow. In-app browsers and iOS
 * Chrome/Firefox/Edge (CriOS/FxiOS/EdgiOS) cannot, so we do NOT show them the
 * guidance card.
 */
export function isIosSafari(): boolean {
  if (!isIos()) return false;
  const ua = window.navigator.userAgent;
  // Real iOS Safari UAs carry a `Version/<n>` token. iOS in-app WKWebViews
  // (Facebook FBAN/FBAV, Instagram, LinkedInApp, Line, TikTok, Snapchat, …) put
  // "Safari" in the UA but OMIT `Version/` and have no Share→Add-to-Home-Screen
  // affordance — showing them the guidance card would be a dead end. Require the
  // positive `Version/` marker AND exclude the dedicated third-party iOS browsers.
  return (
    /Version\/\d/.test(ua) &&
    /Safari/.test(ua) &&
    !/CriOS|FxiOS|EdgiOS|GSA/.test(ua)
  );
}

/**
 * Capture the deferred `beforeinstallprompt` event (Chromium) and observe
 * `appinstalled`. `onCapture` receives the prompt event (already
 * `preventDefault()`-ed so the browser's mini-infobar is suppressed and we own
 * the affordance); `onInstalled` fires once the app is installed.
 * Returns an unsubscribe function.
 */
export function watchInstallPrompt(
  onCapture: (event: BeforeInstallPromptEvent) => void,
  onInstalled: () => void,
): () => void {
  if (typeof window === "undefined") return () => {};

  const onBeforeInstallPrompt = (event: Event) => {
    event.preventDefault();
    onCapture(event as BeforeInstallPromptEvent);
  };
  const onAppInstalled = () => onInstalled();

  window.addEventListener("beforeinstallprompt", onBeforeInstallPrompt);
  window.addEventListener("appinstalled", onAppInstalled);

  return () => {
    window.removeEventListener("beforeinstallprompt", onBeforeInstallPrompt);
    window.removeEventListener("appinstalled", onAppInstalled);
  };
}
