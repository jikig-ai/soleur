// Bumping the suffix triggers the activate handler's cache cleanup, which
// purges _next/static/** chunks cached against an old project ref. Keep
// push-notification subscriptions intact (registration is unchanged).
const CACHE_NAME = "soleur-app-shell-v3";

// Static shell assets cached on install (non-hashed assets only).
// _next/static/** are cached on fetch via cache-first strategy.
const SHELL_ASSETS = [
  "/icons/icon-192x192.png",
  "/icons/icon-512x512.png",
  "/icons/apple-touch-icon.png",
  "/favicon.ico",
];

// Install: pre-cache shell assets, then activate immediately
self.addEventListener("install", (event) => {
  event.waitUntil(
    caches
      .open(CACHE_NAME)
      .then((cache) => cache.addAll(SHELL_ASSETS))
      .then(() => self.skipWaiting())
  );
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
              caches.open(CACHE_NAME).then((cache) =>
                cache.put(event.request, clone)
              );
            }
            return response;
          })
      )
    );
    return;
  }

  // Network-only for everything else (HTML, manifest, etc.)
  // HTML must come from network to get fresh CSP nonce
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
    tag: payload.data?.conversationId ? `review-gate-${payload.data.conversationId}` : "review-gate",
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
