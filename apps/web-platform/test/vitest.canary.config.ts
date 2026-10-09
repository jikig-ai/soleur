import { defineConfig } from "vitest/config";

// Deploy-time canary vitest config (#2640). ci-deploy.sh runs
//   docker exec -w /app soleur-web-platform-canary /usr/bin/env -i \
//     PATH=… HOME=/tmp CI=true SOLEUR_ISOLATION_TEST_HOST=1 \
//     SOLEUR_ISOLATION_TIERS=direct SOLEUR_ISOLATION_IN_IMAGE=1 \
//     /usr/local/bin/vitest run --config test/vitest.canary.config.ts
// inside the canary container (root = cwd = /app) before the prod swap —
// env -i scrubs the canary's Config.Env (the prod env-file) out of the suite.
// The exact argv is pinned by ci-deploy.test.sh CWI-1.
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
