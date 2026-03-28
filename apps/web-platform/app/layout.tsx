import type { Metadata, Viewport } from "next";
import { headers } from "next/headers";
import { SwRegister } from "./sw-register";
import "./globals.css";

export const metadata: Metadata = {
  title: "Soleur — One Command Center, 8 Departments",
  description:
    "One command center for your entire business. AI agents across 8 departments plan, execute, and compound knowledge — so you can focus on the decisions only you can make.",
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
