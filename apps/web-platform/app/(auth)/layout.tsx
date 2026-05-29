import type { Metadata } from "next";

// Pin a strict referrer policy on auth pages so the user's email — which
// the no-account redirect places in the URL as ?email=... — does not leak
// in the Referer header on cross-origin navigations (notably OAuth handoffs
// to the Supabase auth domain).
export const metadata: Metadata = {
  referrer: "strict-origin-when-cross-origin",
  // Auth pages are logged-out funnel surfaces, not marketing content. Keep
  // them out of the index so app.soleur.ai/login (etc.) does not surface as
  // a "duplicate without user-selected canonical" in Search Console.
  robots: { index: false, follow: false },
};

export default function AuthLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return children;
}
