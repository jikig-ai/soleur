import type { Metadata, Viewport } from "next";
import { headers } from "next/headers";
import { SwRegister } from "./sw-register";
import "./globals.css";

export const metadata: Metadata = {
  // Scoped to the dashboard surface so the Next.js app (served under
  // /dashboard/*) and the Eleventy marketing site (served at /) never present
  // conflicting brand claims to crawlers or preview tools. The marketing brand
  // line lives in plugins/soleur/docs/index.njk seoTitle. See #2708.
  title: {
    template: "%s — Soleur Dashboard",
    default: "Soleur Dashboard",
  },
  description:
    "Your Soleur dashboard — manage subscriptions, review agent output, and configure your AI organization.",
  icons: {
    apple: "/icons/apple-touch-icon.png",
  },
};

export const viewport: Viewport = {
  themeColor: "#0a0a0a",
};

export default async function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  // Force dynamic rendering so Next.js extracts the CSP nonce from
  // the Content-Security-Policy header and applies it to all framework
  // scripts, inline scripts, and styles automatically.
  await headers();

  return (
    <html lang="en">
      <body className="bg-neutral-950 text-neutral-100 antialiased">
        <SwRegister />
        {children}
      </body>
    </html>
  );
}
