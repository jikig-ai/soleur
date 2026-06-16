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
    // #4128 — bump vitest defaults (5000ms test / 10000ms hook). Observed
    // slow-first-test runtimes under full-suite contention (473 files, 5003
    // tests, single ubuntu-latest runner — local `npm test` is unsharded):
    //   chat-page#sessionConfirmed=false           2837ms isolated → 6-14s contended
    //   chat-surface-resume-classifying#T5a        4031ms isolated → 5-12s contended
    //   chat-surface-sidebar#dashboard-header      4256ms isolated → 5-11s contended
    //   kb-chat-sidebar#close-button-aria-label    3901ms isolated → 5-13s contended
    //   pdfjs-dist `beforeAll` pre-warm (PR #4097 Fix 3) → 8-15s contended
    // 16_000ms is one tick above vitest's browser-env default (15_000) —
    // happy-dom component tests do browser-shaped work without browser-env
    // defaults applying. 20_000ms hookTimeout = 2× default, gives pdfjs
    // pre-warm + Supabase-fixture setup headroom.
    // Inherits to both `unit` and `component` projects via `extends: true`.
    testTimeout: 16_000,
    hookTimeout: 20_000,
    projects: [
      {
        extends: true,
        test: {
          name: "unit",
          environment: "node",
          include: ["test/**/*.test.ts", "lib/**/*.test.ts"],
          // Default WORKSPACES_ROOT to a writable temp dir (server startup paths
          // now unconditionally mkdir the resolved workspace dir before sandbox
          // construction; the prod default "/workspaces" is not writable in CI).
          setupFiles: ["test/setup-node.ts"],
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
