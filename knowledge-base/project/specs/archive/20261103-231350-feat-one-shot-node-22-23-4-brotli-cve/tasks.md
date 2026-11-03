# Tasks - feat-one-shot-node-22-23-4-brotli-cve

Plan: knowledge-base/project/plans/2026-11-03-fix-node-22-23-4-brotli-cve-plan.md

## Phase 1 - Re-verify and bump the digest
- 1.1 Re-run `docker buildx imagetools inspect node:22-slim`; confirm NODE_VERSION >= 22.23.4 (22 line only)
- 1.2 Replace the old digest in the five sites (Dockerfile x2, sandbox-canary-verify-in-image.sh, plugin-root-propagation-verify-in-image.sh, community-argv.test.sh); verify with `git grep -l <old> -- . ':!knowledge-base'` empty
- 1.3 Add the Node-version comment above the Dockerfile `deps` stage

## Phase 2 - Pin census fixes
- 2.1 scheduled-realtime-probe.yml: node-version '22', NODE_OPTIONS=--no-experimental-websocket (step env), typeof WebSocket guard before the loop, require `polyfill: applied` in every iteration, comment; keep the Sentry heartbeat step shape intact
- 2.2 apps/web-platform/.nvmrc to 22.23.4; fix README and engines-floor.ts wording; leave engines.node
- 2.3 Record deliberately-left pins for the PR body

## Phase 3 - Bun
- 3.1 .bun-version to 1.4.4
- 3.2 npm-publish.yml setup-bun reads .bun-version
- 3.3 Re-measure preflight-check10 fixtures under 1.4.4; update comment only if byte-identical

## Phase 4 - Guards
- 4.1 Offline: in-image-copy-src.test.sh, community-argv.test.sh (1596), vitest pin tests, dockerfile-copy-dockerignore-parity, npm-publish-oidc, sentry-monitor-iac-parity + function-registry-count (vitest, read the probe workflow), lint-workflow-install-sites(+test), test-all-enumerate-toolchain, preflight-check10, actionlint
- 4.2 Local smoke: node -v and Content-Encoding: br fetch inside the committed digest
- 4.3 CI: confirm sandbox-canary-capture-gate ran (not skipped) and shows no drift; regenerate fixture only on drift

- 4.4 Guard Contract rows: run the mutation matrix against the probe step (delete NODE_OPTIONS, remove the guard, second node call) and confirm RED
- 4.5 Post-merge: `gh workflow run scheduled-realtime-probe.yml`, expect 5/5 SUBSCRIBED

## Phase 5 - Learning and PR
- 5.1 Write the learning
- 5.2 PR body: pins left floating, rollback digest, Node version
