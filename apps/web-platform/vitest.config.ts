import { defineConfig } from "vitest/config";
import path from "path";

export default defineConfig({
  esbuild: {
    jsx: "automatic",
  },
  test: {
    environment: "node",
    exclude: ["e2e/**", "node_modules/**"],
    environmentMatchGlobs: [
      ["test/**/*.tsx", "happy-dom"],
    ],
    setupFiles: ["test/setup-dom.ts"],
  },
  resolve: {
    alias: {
      "@": path.resolve(__dirname),
    },
  },
});
