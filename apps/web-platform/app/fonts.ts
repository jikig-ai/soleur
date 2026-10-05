import localFont from "next/font/local";

// Vendored Inter, latin subset only (see assets/fonts/README.md). Resolving
// the network font loader during the first compile of app/layout.tsx failed
// (suspected transient fetch, #8785) and cascaded into 64 e2e reds;
// test/no-network-fonts.test.ts keeps the network loader out. `weight` mirrors
// the old 400/500/600 set; the old config was latin-only too.
export const sans = localFont({
  src: "../assets/fonts/inter-latin-wght.woff2",
  weight: "400 600",
  style: "normal",
  variable: "--font-inter",
  display: "swap",
});
