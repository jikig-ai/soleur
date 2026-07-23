// PWA kill switch — the brand-survival recovery mitigation for the
// single-user-incident threshold (ADR-137).
//
// If a bad service worker ever bricks the installed app, navigating to ANY URL
// with the `?sw-reset` query flag unregisters every service worker and clears
// all Cache Storage, then reloads to the clean URL. Because HTML is served
// network-only (fresh per-request), the document + this recovery code still
// load even when the worker's fetch/cache logic is broken — so the escape hatch
// is reachable. Wired into <SwRegister/> (app/layout.tsx) so it works on every
// route, including /login.

export const SW_RESET_PARAM = "sw-reset";

/** True when the current URL carries the `?sw-reset` recovery flag. */
export function hasSwResetFlag(search: string = window.location.search): boolean {
  return new URLSearchParams(search).has(SW_RESET_PARAM);
}

/** Unregister every service worker and delete every Cache Storage bucket. */
export async function unregisterAllAndClearCaches(): Promise<void> {
  if ("serviceWorker" in navigator) {
    const registrations = await navigator.serviceWorker.getRegistrations();
    await Promise.all(registrations.map((registration) => registration.unregister()));
  }
  if (typeof caches !== "undefined") {
    const keys = await caches.keys();
    await Promise.all(keys.map((key) => caches.delete(key)));
  }
}

/** The current URL with the `?sw-reset` flag stripped (path + remaining query + hash). */
export function cleanResetUrl(href: string = window.location.href): string {
  const url = new URL(href);
  url.searchParams.delete(SW_RESET_PARAM);
  return url.pathname + url.search + url.hash;
}
