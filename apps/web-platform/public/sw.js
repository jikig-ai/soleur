const CACHE_NAME = "soleur-app-shell-v1";

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
