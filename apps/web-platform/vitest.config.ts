import { defineConfig } from "vitest/config";
import path from "path";
import { fileURLToPath } from "url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

// Component-project worker pool. Default on `forks` (per-file process
// isolation) since #3817 confirmed the kb-chat-sidebar/chat-page/ws-* flake
// class is worker-pool resource contention under `pool: 'threads'`, not
// module-graph aliasing. `isolate: true` closes the aliasing vector but does
// NOT close the contention vector — forks does. Opt out via
// `WEBPLAT_TEST_USE_THREADS=1 npm run test:ci` for diagnosis (the threads
// pool is faster but reintroduces the contention class). Default on.
const componentPool =
  process.env.WEBPLAT_TEST_USE_THREADS === "1" ? undefined : "forks";

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
          // Vitest 3.x defaults `isolate` to true, but the default has
          // changed before. Pin it explicitly here so module-init env-var
          // reads (e.g., `const SENTRY_USERID_PEPPER = process.env.…` in
          // `server/observability.ts`) cannot leak between unit test files
          // sharing a worker — `observability-pepper-unset.test.ts` deletes
          // the env var at vi.hoisted time and relies on a fresh module
          // graph to see the deletion. See #3638.
          isolate: true,
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
          ...(componentPool ? { pool: componentPool } : {}),
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
