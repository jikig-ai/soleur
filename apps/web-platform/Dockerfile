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

RUN npm run build
RUN npm run build:server
# Compile next.config.ts to .mjs so the runner stage doesn't need TypeScript
RUN npx esbuild next.config.ts --format=esm --outfile=next.config.mjs

# Stage 3: Production image with only runtime artifacts
FROM node:22-slim@sha256:4f77a690f2f8946ab16fe1e791a3ac0667ae1c3575c3e4d0d4589e9ed5bfaf3d AS runner

# Install Claude Code CLI (needed by Agent SDK)
RUN npm install -g @anthropic-ai/claude-code@2.1.79

# Install git (needed for workspace provisioning)
RUN apt-get update && apt-get install -y --no-install-recommends git && rm -rf /var/lib/apt/lists/*

WORKDIR /app
ENV NODE_ENV=production
ENV PORT=3000

# Production dependencies only
COPY package.json package-lock.json ./
RUN npm ci --omit=dev

# Next.js build output
COPY --from=builder /app/.next ./.next

# Compiled custom server
COPY --from=builder /app/dist/server ./dist/server

# Config file (compiled from .ts to .mjs to avoid TypeScript dep at runtime)
COPY --from=builder /app/next.config.mjs ./next.config.mjs

# Non-root user (node:22-slim includes a 'node' user at uid 1000)
USER node
RUN git config --global user.name "Soleur" && git config --global user.email "soleur@localhost"

EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD node -e "fetch('http://localhost:3000/health').then(r=>{process.exit(r.ok?0:1)}).catch(()=>process.exit(1))"

CMD ["node", "dist/server/index.js"]
