import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Soleur — One Command Center, 8 Departments",
  description:
    "One command center for your entire business. AI agents across 8 departments plan, execute, and compound knowledge — so you can focus on the decisions only you can make.",
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en">
      <body className="bg-neutral-950 text-neutral-100 antialiased">
        {children}
      </body>
    </html>
  );
}
