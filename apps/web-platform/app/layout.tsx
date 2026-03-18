import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Soleur — AI Domain Leaders",
  description:
    "Chat with AI domain leaders. They plan, execute, and compound knowledge for your business.",
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
