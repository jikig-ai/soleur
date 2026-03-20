FROM node:22-slim@sha256:4f77a690f2f8946ab16fe1e791a3ac0667ae1c3575c3e4d0d4589e9ed5bfaf3d AS base

# Install Claude Code CLI (needed by Agent SDK)
RUN npm install -g @anthropic-ai/claude-code@2.1.79

# Install git (needed for workspace provisioning)
RUN apt-get update && apt-get install -y git && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Install dependencies
COPY package.json package-lock.json ./
RUN npm ci --production=false

# Copy source
COPY . .

# NEXT_PUBLIC_ vars must be present at build time for client-side inlining
ARG NEXT_PUBLIC_SUPABASE_URL
ARG NEXT_PUBLIC_SUPABASE_ANON_KEY

# Build Next.js
RUN npm run build

# Non-root user (UID 1001 avoids conflict with node:22-slim's built-in 'node' user at UID 1000)
RUN useradd --no-log-init --uid 1001 -m soleur \
    && chown -R soleur:soleur .next
USER soleur
RUN git config --global user.name "Soleur" && git config --global user.email "soleur@localhost"

# Production
ENV NODE_ENV=production
ENV PORT=3000
EXPOSE 3000

# Health check (uses Node.js fetch -- curl is not available in node:22-slim)
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD node -e "fetch('http://localhost:3000/health',{signal:AbortSignal.timeout(4_000)}).then(r=>{if(!r.ok)process.exit(1)}).catch(e=>{console.error(e.message);process.exit(1)})"

CMD ["npm", "run", "start"]
