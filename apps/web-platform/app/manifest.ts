import type { MetadataRoute } from "next";

export default function manifest(): MetadataRoute.Manifest {
  return {
    name: "Soleur Dashboard",
    short_name: "Soleur",
    description:
      "Your Soleur dashboard — manage subscriptions, review agent output, and configure your AI organization.",
    // Launch straight into the dashboard, but keep the navigation scope at the
    // origin root: session-expiry bounces to /login (outside /dashboard) must
    // stay INSIDE the installed app window rather than ejecting to the system
    // browser. Operator decision 2026-07-23 (decision-challenges.md Challenge 3).
    start_url: "/dashboard",
    scope: "/",
    id: "soleur-dashboard",
    lang: "en",
    dir: "ltr",
    categories: ["productivity", "business"],
    display: "standalone",
    background_color: "#0a0a0a",
    theme_color: "#0a0a0a",
    shortcuts: [
      {
        name: "Chat",
        short_name: "Chat",
        url: "/dashboard",
        icons: [
          { src: "/icons/icon-192x192.png", sizes: "192x192", type: "image/png" },
        ],
      },
      {
        name: "Inbox",
        short_name: "Inbox",
        url: "/dashboard/inbox",
        icons: [
          { src: "/icons/icon-192x192.png", sizes: "192x192", type: "image/png" },
        ],
      },
      {
        name: "Workstream",
        short_name: "Workstream",
        url: "/dashboard/workstream",
        icons: [
          { src: "/icons/icon-192x192.png", sizes: "192x192", type: "image/png" },
        ],
      },
    ],
    icons: [
      {
        src: "/icons/icon-192x192.png",
        sizes: "192x192",
        type: "image/png",
      },
      {
        src: "/icons/icon-512x512.png",
        sizes: "512x512",
        type: "image/png",
      },
      {
        src: "/icons/icon-512x512.png",
        sizes: "512x512",
        type: "image/png",
        purpose: "maskable",
      },
    ],
  };
}
