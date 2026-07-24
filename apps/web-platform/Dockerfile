# Stage 1: Install all dependencies (cached when package files unchanged)
FROM node:22-slim@sha256:4f77a690f2f8946ab16fe1e791a3ac0667ae1c3575c3e4d0d4589e9ed5bfaf3d AS deps
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci

# Stage 2: Build Next.js app + compile custom server
FROM deps AS builder
WORKDIR /app
COPY . .

# NEXT_PUBLIC_ vars must be present at build time for client-side inlining
ARG NEXT_PUBLIC_SUPABASE_URL
ARG NEXT_PUBLIC_SUPABASE_ANON_KEY
ARG NEXT_PUBLIC_SENTRY_DSN
ARG NEXT_PUBLIC_GITHUB_APP_SLUG
# Plugin stats (computed by CI from plugins/soleur/agents/)
ARG NEXT_PUBLIC_AGENT_COUNT
# Web Push VAPID public key (client-side push subscription)
ARG NEXT_PUBLIC_VAPID_PUBLIC_KEY
# Sentry source map upload (builder stage only — not present in runner image)
ARG SENTRY_AUTH_TOKEN
ARG SENTRY_ORG
ARG SENTRY_PROJECT
# SENTRY_URL targets the org-subdomain so sentry-cli source-map upload
# hits the new DE org (Branch C). `eu.sentry.io` is NOT correct here —
# its slug-parser rewrites org slugs ending in `-eu` per learning
# `2026-05-17-sentry-eu-region-host-rewrites-slugs-with-eu-suffix.md`.
ENV SENTRY_URL=https://jikigai-eu.sentry.io/

RUN npm run build
# R3 (feat-dev-signin-bypass): post-build tripwire that fails the prd
# image if dev-only sign-in symbols leak into client chunks or the RSC
# manifest. Scope is documented inside the script — server-bundle
# inclusion of the route handler is by-design and not flagged here.
RUN bash scripts/assert-dev-signin-eliminated.sh
RUN npm run build:server
# Compile next.config.ts to .mjs so the runner stage doesn't need TypeScript
RUN ./node_modules/.bin/esbuild next.config.ts --bundle --format=esm --platform=node --external:@sentry/nextjs --outfile=next.config.mjs

# Stage 3: Production image with only runtime artifacts
FROM node:22-slim@sha256:4f77a690f2f8946ab16fe1e791a3ac0667ae1c3575c3e4d0d4589e9ed5bfaf3d AS runner

# CACHE-ORDERING INVARIANT (gha layer cache, reusable-release.yml cache-to=type=gha):
# the heavy runner-stage installs below (claude-code, likec4, apt, gh, playwright)
# MUST stay ABOVE the `ENV BUILD_VERSION`/`ENV BUILD_SHA` block — BUILD_SHA changes
# every commit and busts every layer beneath it. Keeping these installs above it
# is what makes them cache hits across releases. Do NOT move an `ENV BUILD_*` (or
# any per-commit-volatile line) above this point. (Recovering `npm ci --omit=dev`,
# which sits below BUILD_SHA, is tracked as #5055.)
# Install Claude Code CLI (needed by Agent SDK)
RUN npm install -g @anthropic-ai/claude-code@2.1.79

# LikeC4 CLI for runtime diagram re-render after a Code-tab Save (#4964).
# Global install (NOT a package.json dep) — same pattern as the line above —
# so it preserves the npm10/npm11 lockfile-sync parity that prod `npm ci`
# requires (the constraint documented in lib/c4-constants.ts). The server
# spawns it out-of-process from server/c4-render.ts; it is never imported, so
# vite/esbuild/bundle-require never enter prod deps.
# Pinned to 1.50.0 to MATCH the client renderer @likec4/core/@likec4/diagram@1.50.0
# (package.json) so `export json` emits the exact schema LikeC4Model.create reads.
# Lays out via bundled graphviz-wasm — no native `dot` binary needed (verified
# 2026-06-05: `likec4@1.50.0 export json` exits 0 with no dot on PATH, ~0.8s).
RUN npm install -g likec4@1.50.0

# Install git (workspace provisioning) + bubblewrap/socat (Agent SDK sandbox)
# ca-certificates: required for git HTTPS clone — node:22-slim omits it (#1645)
#
# IMPORTANT: `socat` is load-bearing for the Agent SDK sandbox — not just for
# networking. The SDK's bwrap argv unconditionally includes socat-backed
# HTTP/SOCKS bridge listeners in the sandbox shell script (captured 2026-04-19
# via strace), so without socat ANY sandboxed run fails. With
# `sandbox.failIfUnavailable: true` set in agent-runner.ts (see #2634), the
# agent process refuses to start instead of silently falling back to
# unsandboxed Bash execution. Do NOT remove socat in future cleanups.
#
# `jq` is load-bearing for the content publisher: cron-content-publisher.ts
# spawns scripts/content-publisher.sh (jq x5) which spawns the LinkedIn scripts
# (linkedin-community.sh jq x8). The TR9 migration moved the publisher off the
# GHA runner (jq preinstalled) into this image without porting the dependency,
# so every scheduled post failed with "jq is required but not installed" and
# routed to a per-post fallback issue (e.g. #4858). Do NOT remove jq.
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates git bubblewrap socat qpdf jq \
    && rm -rf /var/lib/apt/lists/*

# GitHub CLI (needed by cron-follow-through-monitor gh label/issue commands
# and event-ship-merge gh pr checkout). Not in default Debian repos.
RUN apt-get update && apt-get install -y --no-install-recommends curl \
    && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
       -o /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
       > /etc/apt/sources.list.d/github-cli.list \
    && apt-get update && apt-get install -y --no-install-recommends gh=2.93.0 \
    && rm -rf /var/lib/apt/lists/*

# Playwright Chromium system deps + browser binary (TR9 PR-11).
# Baked at image-build time — bwrap sandbox blocks apt at handler runtime.
# Version pinned to @playwright/mcp@0.0.75's playwright-core (#5199: the prod
# image runs ONLY cron-ux-audit's Playwright MCP, whose playwright-core is
# 1.61.0-alpha-1778188671000 — this bakes the matching Chromium revision so the
# firewalled cron never needs a runtime browser download, registry.npmjs.org and
# the CDN both being off the egress allowlist). The e2e suite's @playwright/test
# (^1.58.2, satisfies next's peerOptional) runs in CI, NOT this image, so its
# Chromium revision is irrelevant here. @playwright/mcp is a runtime dep (baked
# via npm ci --omit=dev); only the browser binary + system libs persist here.
# Kept in lockstep with package.json + package-lock.json by
# test/playwright-mcp-version-pin.test.ts.
RUN npx playwright@1.61.0-alpha-1778188671000 install --with-deps chromium

WORKDIR /app
ENV NODE_ENV=production
ENV PORT=3000

# Version injected at build time for /health endpoint verification
ARG BUILD_VERSION=dev
ENV BUILD_VERSION=$BUILD_VERSION

# Git commit SHA injected at build time for /health endpoint verification.
# Asserted post-deploy by web-platform-release.yml against ${{ github.sha }}
# to catch bad-tag → bad-image associations (#3409).
ARG BUILD_SHA=dev
ENV BUILD_SHA=$BUILD_SHA

# Production dependencies only
COPY package.json package-lock.json ./
RUN npm ci --omit=dev

# Build-time assertion that lazy-imported runtime deps resolve in the runner image's
# node_modules. Catches future regressions where a Dockerfile edit (npm prune, prod
# re-copy, devDependencies migration) strips pdfjs-dist or sharp from the runner stage,
# which would otherwise be swallowed by try/catch in pdf-text-extract.ts /
# kb-preview-metadata.ts and surface only as a WARN Sentry breadcrumb in production.
# pdfjs-dist is a direct dep (apps/web-platform/package.json); sharp is transitive via
# Next.js — if Next ever drops it, this assertion fires loudly instead of breaking
# kb-share image previews silently.
# See #3422 / Ref #3410.
RUN node -e "require.resolve('pdfjs-dist/legacy/build/pdf.mjs'); require.resolve('sharp')"

# Next.js build output + public assets (icons, service worker)
COPY --from=builder /app/public ./public
COPY --from=builder /app/.next ./.next

# Compiled custom server
COPY --from=builder /app/dist/server ./dist/server

# Faithful sandbox canary payload + captured-argv fixture (#5875 / ADR-079).
# Baked into the image so ci-deploy.sh can `docker exec <canary> node
# /app/scripts/sandbox-canary.mjs --replay` against the LOADED profile — the
# host has no node, and the replay path is pure JS (reads the fixture, spawns
# bwrap) with no runtime TypeScript/SDK dependency. The fixture is version-
# consistent with this image's SDK because both are baked at build time.
COPY --from=builder /app/scripts/sandbox-canary.mjs ./scripts/sandbox-canary.mjs
COPY --from=builder /app/infra/sandbox-canary-argv.json ./infra/sandbox-canary-argv.json

# Config file (compiled from .ts to .mjs to avoid TypeScript dep at runtime)
COPY --from=builder /app/next.config.mjs ./next.config.mjs

# Plugin baked at build time from the vendored copy in the build context (#3045).
# Source tree is plugins/soleur, vendored to apps/web-platform/_plugin-vendored
# by reusable-release.yml's "Vendor plugin into build context" step before docker build.
# The bind-mount /mnt/data/plugins/soleur is seeded from this path by ci-deploy.sh
# via `docker cp <ephemeral>:/opt/soleur/plugin/. /mnt/data/plugins/soleur/`.
COPY _plugin-vendored /opt/soleur/plugin

# Fresh-host bootstrap scripts + hooks template baked for cloud-init extraction (#5921).
# These 22 scripts + hooks.json.tmpl were REMOVED from cloud-init.yml write_files: as
# base64 blobs they pushed the rendered Hetzner user_data to ~282 KB, ~8.6x over the
# 32,768-byte cap. cloud-init.yml now `docker cp`s them out of this dir at first boot
# (the same idiom as the plugin-seed above), verifies a combined content-hash, and
# installs each with an authoritative mode. Boot integrity: server.tf computes
# host_scripts_content_hash over local.host_script_files (this exact set) at plan time
# and the extraction stub re-verifies it before install — a stale/mis-built image aborts
# the boot loudly. KEEP THIS LIST IN LOCKSTEP with local.host_script_files in server.tf
# (cloud-init-user-data-size.test.ts asserts the two sets are identical).
COPY --from=builder \
  /app/infra/ci-deploy.sh \
  /app/infra/ci-deploy-wrapper.sh \
  /app/infra/cat-deploy-state.sh \
  /app/infra/canary-bundle-claim-check.sh \
  /app/infra/disk-monitor.sh \
  /app/infra/resource-monitor.sh \
  /app/infra/container-restart-monitor.sh \
  /app/infra/container-restart-monitor.service \
  /app/infra/container-restart-monitor.timer \
  /app/infra/infra-config-apply.sh \
  /app/infra/infra-config-install.sh \
  /app/infra/cat-infra-config-state.sh \
  /app/infra/cron-egress-nftables.sh \
  /app/infra/cron-egress-resolve.sh \
  /app/infra/cron-egress-alarm.sh \
  /app/infra/cron-egress-allowlist.txt \
  /app/infra/cron-egress-allowlist-cidr.txt \
  /app/infra/cron-egress-firewall.service \
  /app/infra/cron-egress-resolve.service \
  /app/infra/cron-egress-resolve.timer \
  /app/infra/cron-egress-alarm@.service \
  /app/infra/cron-egress-postapply-assert.sh \
  /app/infra/cron-egress-enforce-probe.sh \
  /app/infra/hooks.json.tmpl \
  /app/infra/journald-soleur.conf \
  /app/infra/soleur-host-bootstrap.sh \
  /app/infra/cosign-trusted-root.json \
  /app/infra/vector.toml \
  /app/infra/seccomp-bwrap.json \
  /app/infra/apparmor-soleur-bwrap.profile \
  /app/infra/orphan-reaper.sh \
  /app/infra/orphan-reaper.service \
  /app/infra/orphan-reaper.timer \
  /app/infra/99-bwrap-userns.conf \
  /app/infra/bwrap-userns-sysctl.service \
  /app/infra/web-private-nic-guard.sh \
  /app/infra/web-private-nic-guard.service \
  /app/infra/web-private-nic-guard.timer \
  /app/infra/web-zot-consumer-probe.sh \
  /app/infra/web-zot-consumer-probe.service \
  /app/infra/web-zot-consumer-probe.timer \
  /app/infra/web-git-data-probe.sh \
  /app/infra/web-git-data-probe.service \
  /app/infra/web-git-data-probe.timer \
  /app/infra/web-probe-envwrite.sh \
  /opt/soleur/host-scripts/
RUN chown -R 1001:1001 /opt/soleur

# Non-root user (UID 1001 avoids collision with node:22-slim's built-in node user at UID 1000)
RUN useradd --no-log-init --uid 1001 -m soleur \
    && chown -R soleur:soleur .next
USER soleur
RUN git config --global user.name "github-actions[bot]" \
    && git config --global user.email "41898282+github-actions[bot]@users.noreply.github.com"

EXPOSE 3000

# Health check (uses Node.js fetch -- no additional binary needed)
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD node -e "fetch('http://localhost:3000/health',{signal:AbortSignal.timeout(4_000)}).then(r=>{if(!r.ok)process.exit(1)}).catch(e=>{console.error(e.message);process.exit(1)})"

CMD ["node", "dist/server/index.cjs"]
