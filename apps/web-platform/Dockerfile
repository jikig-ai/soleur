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

RUN npm run build
RUN npm run build:server
# Compile next.config.ts to .mjs so the runner stage doesn't need TypeScript
RUN ./node_modules/.bin/esbuild next.config.ts --bundle --format=esm --platform=node --external:@sentry/nextjs --outfile=next.config.mjs

# Stage 3: Production image with only runtime artifacts
FROM node:22-slim@sha256:4f77a690f2f8946ab16fe1e791a3ac0667ae1c3575c3e4d0d4589e9ed5bfaf3d AS runner

# Install Claude Code CLI (needed by Agent SDK)
RUN npm install -g @anthropic-ai/claude-code@2.1.79

# Install git (workspace provisioning) + bubblewrap/socat (Agent SDK sandbox)
# ca-certificates: required for git HTTPS clone — node:22-slim omits it (#1645)
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates git bubblewrap socat \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
ENV NODE_ENV=production
ENV PORT=3000

# Version injected at build time for /health endpoint verification
ARG BUILD_VERSION=dev
ENV BUILD_VERSION=$BUILD_VERSION

# Production dependencies only
COPY package.json package-lock.json ./
RUN npm ci --omit=dev

# Next.js build output + public assets (icons, service worker)
COPY --from=builder /app/public ./public
COPY --from=builder /app/.next ./.next

# Compiled custom server
COPY --from=builder /app/dist/server ./dist/server

# Config file (compiled from .ts to .mjs to avoid TypeScript dep at runtime)
COPY --from=builder /app/next.config.mjs ./next.config.mjs

# Non-root user (UID 1001 avoids collision with node:22-slim's built-in node user at UID 1000)
RUN useradd --no-log-init --uid 1001 -m soleur \
    && chown -R soleur:soleur .next
USER soleur
RUN git config --global user.name "Soleur" && git config --global user.email "soleur@localhost"

EXPOSE 3000

# Health check (uses Node.js fetch -- curl is not available in node:22-slim)
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD node -e "fetch('http://localhost:3000/health',{signal:AbortSignal.timeout(4_000)}).then(r=>{if(!r.ok)process.exit(1)}).catch(e=>{console.error(e.message);process.exit(1)})"

CMD ["node", "dist/server/index.cjs"]
