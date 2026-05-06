import type { Metadata, Viewport } from "next";
import { headers } from "next/headers";
import { SwRegister } from "./sw-register";
import { NoFoucScript } from "@/components/theme/no-fouc-script";
import { ThemeProvider } from "@/components/theme/theme-provider";
import { DynamicThemeColor } from "@/components/theme/dynamic-theme-color";
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

// Static fallback covers the pre-hydration window. Once <ThemeProvider> +
// <DynamicThemeColor> mount, the meta tag is updated to match the resolved
// theme. Forge dark is the default to avoid a light flash for dark-mode users.
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
  const headerList = await headers();
  const nonce = headerList.get("x-nonce") ?? undefined;

  return (
    // suppressHydrationWarning: the <NoFoucScript> below writes
    // document.documentElement.dataset.theme synchronously during head
    // parsing. Server-rendered HTML has no data-theme attribute, so React's
    // hydration check would otherwise warn about the mismatch on every page
    // load. Suppression is scoped to <html> only — child trees still get
    // normal hydration validation.
    <html lang="en" suppressHydrationWarning>
      <head>
        {/* Sync theme bootstrap — runs before paint to prevent FOUC.
            INVARIANT: this <script> MUST stay in <head> and MUST render
            BEFORE <ThemeProvider> below; the provider's lazy initializer
            (components/theme/theme-provider.tsx) reads the same
            localStorage["soleur:theme"] key and assumes the inline script
            already wrote data-theme to <html>. Reordering breaks no-FOUC. */}
        <NoFoucScript nonce={nonce} />
      </head>
      <body className="bg-soleur-bg-base text-soleur-text-primary antialiased">
        <ThemeProvider>
          <DynamicThemeColor />
          <SwRegister />
          {children}
        </ThemeProvider>
      </body>
    </html>
  );
}
