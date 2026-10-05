import localFont from "next/font/local";

// Vendored Inter (see assets/fonts/README.md). A build-time network fetch of
// the font made the first compile of app/layout.tsx fail on a network blip and
// cascaded into 64 e2e reds; test/no-network-fonts.test.ts keeps the network
// loader out. `weight` mirrors the old 400/500/600 set.
export const sans = localFont({
  src: "../assets/fonts/inter-latin-wght.woff2",
  weight: "400 600",
  style: "normal",
  variable: "--font-inter",
  display: "swap",
});
