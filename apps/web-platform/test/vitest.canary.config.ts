import { defineConfig } from "vitest/config";

// Deploy-time canary vitest config (#2640). ci-deploy.sh runs
//   docker exec -w /app -e CI=true -e SOLEUR_ISOLATION_TEST_HOST=1 \
//     -e SOLEUR_ISOLATION_TIERS=direct soleur-web-platform-canary \
//     /usr/local/bin/vitest run --config test/vitest.canary.config.ts
// inside the canary container (root = cwd = /app) before the prod swap.
//
// Why a standalone config and not the repo vitest.config.ts: that config's
// `globalSetup` (test/global-setup-git-tripwire.ts) and project `setupFiles`
// (test/setup-node.ts) live under test/, which .dockerignore prunes from the
// image — only the three-file probe payload below is re-included. This config
// therefore carries no setup hooks and no project fan-out: just the isolation
// suite, in the node environment.
//
// `cacheDir`: the canary exec runs as USER soleur and /app/node_modules is
// root-owned, so vitest's default cache location is unwritable — /tmp is the
// canary's tmpfs mount.
export default defineConfig({
  cacheDir: "/tmp/vitest-cache",
  test: {
    environment: "node",
    include: ["test/sandbox-isolation.test.ts"],
    // The direct tier spawns real bwrap sandboxes on the canary host; give it
    // the headroom the query-tier timeouts encode (FR8/FR9 run up to 300s
    // locally) without letting a deadlocked sandbox hold the deploy's
    // host-side `timeout` cap open. The probe wrapper still bounds total
    // runtime; these bound per-test and per-hook hangs.
    testTimeout: 120_000,
    hookTimeout: 60_000,
  },
});
