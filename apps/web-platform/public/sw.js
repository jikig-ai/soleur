// Bumping the suffix triggers the activate handler's cache cleanup, which
// purges _next/static/** chunks cached against an old project ref. Keep
// push-notification subscriptions intact (registration is unchanged).
const CACHE_NAME = "soleur-app-shell-v10";

// Static shell assets cached on install (non-hashed assets only).
// _next/static/** are cached on fetch via cache-first strategy.
// /offline.html is the static, script-free navigate-fallback (see fetch below);
// it MUST be in PUBLIC_PATHS (lib/routes.ts) so this precache captures the real
// page, not a 307→/login redirect body.
const SHELL_ASSETS = [
  "/offline.html",
  "/icons/icon-192x192.png",
  "/icons/icon-512x512.png",
  "/icons/apple-touch-icon.png",
  "/favicon.ico",
];

// Install: pre-cache shell assets. Do NOT skipWaiting() — a new worker waits
// until the user accepts the update (the "Update available" affordance posts
// SKIP_WAITING; see the message listener below). Silent skipWaiting can swap
// assets mid-session under a controlled page.
self.addEventListener("install", (event) => {
  event.waitUntil(caches.open(CACHE_NAME).then((cache) => cache.addAll(SHELL_ASSETS)));
});

// The client posts this when the user accepts an "Update available" prompt.
self.addEventListener("message", (event) => {
  if (event.data && event.data.type === "SKIP_WAITING") {
    self.skipWaiting();
  }
});

// Activate: clean old caches, claim clients immediately
self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches.keys().then((names) =>
      Promise.all(
        names
          .filter((name) => name !== CACHE_NAME)
          .map((name) => caches.delete(name))
      )
    )
  );
  self.clients.claim();
});

// Fetch: route by URL pattern
self.addEventListener("fetch", (event) => {
  const url = new URL(event.request.url);

  // Skip non-GET requests (POST, WebSocket upgrade, etc.)
  if (event.request.method !== "GET") return;

  // Skip API routes, WebSocket, and health check
  if (
    url.pathname.startsWith("/api/") ||
    url.pathname === "/ws" ||
    url.pathname === "/health"
  ) {
    return;
  }

  // Cache-first for static assets: content-hashed bundles (_next/static),
  // pre-cached icons, and favicon. Cache hit returns immediately;
  // cache miss fetches from network and populates cache for next visit.
  if (
    url.pathname.startsWith("/_next/static/") ||
    url.pathname.startsWith("/icons/") ||
    url.pathname === "/favicon.ico"
  ) {
    event.respondWith(
      caches.match(event.request).then(
        (cached) =>
          cached ||
          fetch(event.request).then((response) => {
            if (response.ok) {
              const clone = response.clone();
              // #3002: a failed cache.put (QuotaExceededError on a full
              // storage bucket) must not reject the fetch handler — the
              // response is already in hand. Swallow the write error; the
              // asset just isn't cached for next time.
              caches
                .open(CACHE_NAME)
                .then((cache) => cache.put(event.request, clone))
                .catch(() => {});
            }
            return response;
          })
      )
    );
    return;
  }

  // Navigations (HTML documents): network-only for a fresh CSP nonce, but fall
  // back to the static offline shell when the network is unavailable. `mode ===
  // "navigate"` is true only for top-level document requests, so this never
  // touches API/asset fetches. We NEVER branch on `response.ok` — a served 4xx/
  // 5xx from the origin is the app's own error page (with a fresh nonce), not an
  // offline condition; only a rejected fetch() (no network) yields the fallback.
  // This catch-only shape is the brand-survival mitigation: a bad worker can
  // never mask a live origin response with the cached shell.
  if (event.request.mode === "navigate") {
    event.respondWith(
      fetch(event.request).catch(() => caches.match("/offline.html"))
    );
    return;
  }

  // Network-only for everything else (manifest, etc.)
  // HTML navigations are handled above; assets are cached-first above.
});

// ---------------------------------------------------------------------------
// #3002: global error + unhandledrejection handlers. Without these, an
// exception in an event handler is swallowed silently by the SW runtime;
// surfacing it to the console gives a debugging breadcrumb for cache/quota
// failures in the field. Intentionally console-only — the SW has no Sentry.
// ---------------------------------------------------------------------------
self.addEventListener("error", (event) => {
  console.error("[sw] uncaught error:", event.message || event.error);
});
self.addEventListener("unhandledrejection", (event) => {
  console.error("[sw] unhandled rejection:", event.reason);
});

// ---------------------------------------------------------------------------
// Push notifications (review gate alerts for offline users)
// ---------------------------------------------------------------------------

self.addEventListener("push", (event) => {
  if (!event.data) return;

  let payload;
  try {
    payload = event.data.json();
  } catch {
    return;
  }

  const title = payload.title || "Soleur";
  const options = {
    body: payload.body || "",
    icon: payload.icon || "/icons/icon-192x192.png",
    badge: "/icons/icon-192x192.png",
    data: payload.data || {},
    // Per-variant tag namespace: browsers REPLACE same-tag notifications, so
    // each variant must carry its own per-item tag or pings collapse into one
    // another. inbox_item payloads carry data.inboxItemId; email_triage carry
    // data.emailId; review-gate carry data.conversationId.
    tag: payload.data?.inboxItemId
      ? `inbox-item-${payload.data.inboxItemId}`
      : payload.data?.emailId
        ? `email-triage-${payload.data.emailId}`
        : payload.data?.conversationId
          ? `review-gate-${payload.data.conversationId}`
          : "review-gate",
  };

  event.waitUntil(self.registration.showNotification(title, options));
});

self.addEventListener("notificationclick", (event) => {
  event.notification.close();

  // Validate URL origin to prevent open redirect via crafted push payload
  const rawUrl = event.notification.data?.url || "/dashboard";
  const parsed = new URL(rawUrl, self.location.origin);
  const url = parsed.origin === self.location.origin ? parsed.href : "/dashboard";

  event.waitUntil(
    self.clients
      .matchAll({ type: "window", includeUncontrolled: true })
      .then((clients) => {
        // Focus an existing tab if one is open on the app
        for (const client of clients) {
          if (new URL(client.url).origin === self.location.origin) {
            client.navigate(url);
            return client.focus();
          }
        }
        // Otherwise open a new tab
        return self.clients.openWindow(url);
      })
  );
});
