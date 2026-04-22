import { defineConfig } from "vitest/config";
import path from "path";
import { fileURLToPath } from "url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

export default defineConfig({
  esbuild: {
    jsx: "automatic",
  },
  test: {
    exclude: ["e2e/**", "node_modules/**"],
    projects: [
      {
        extends: true,
        test: {
          name: "unit",
          environment: "node",
          include: ["test/**/*.test.ts", "lib/**/*.test.ts"],
        },
      },
      {
        extends: true,
        test: {
          name: "component",
          environment: "happy-dom",
          include: ["test/**/*.test.tsx"],
          setupFiles: ["test/setup-dom.ts"],
          // Per-file module-graph isolation. Without this, vitest's
          // pool: 'threads' default reuses workers across files and module
          // graphs can leak state (storage writes, raw `globalThis.fetch =`
          // assignments, accumulated spy call-history). The setup-dom.ts
          // afterAll hook scrubs most worker-level state, but some hoisted
          // `vi.mock(...)` module graphs survive the scrub and still cause
          // cross-file flakes in the kb-chat-sidebar family (#2594, #2505).
          // isolate: true gives each file its own module graph and closes
          // the remaining gap.
          //
          // Tradeoff: ~15-25% slower component-project runtime. Acceptable
          // for a reliable suite.
          isolate: true,
        },
      },
    ],
  },
  resolve: {
    alias: {
      "@": path.resolve(__dirname),
    },
  },
});
