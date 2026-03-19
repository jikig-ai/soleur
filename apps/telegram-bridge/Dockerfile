FROM oven/bun:1.3.11@sha256:0733e50325078969732ebe3b15ce4c4be5082f18c4ac1a0f0ca4839c2e4e42a7

# Install system dependencies (nodejs/npm needed for claude-code CLI)
RUN apt-get update && \
    apt-get install -y --no-install-recommends git curl openssh-client nodejs npm && \
    rm -rf /var/lib/apt/lists/*

# Install Claude Code CLI via npm (avoids curl-pipe-shell antipattern)
RUN npm install -g @anthropic-ai/claude-code@2.1.79

WORKDIR /app

# Install dependencies (cached layer)
COPY package.json bun.lock ./
RUN bun install --frozen-lockfile

# Copy application source
COPY src/ ./src/

# Non-root user
RUN useradd -m soleur
USER soleur

# Persistent data volume
VOLUME /home/soleur/data

# Health check (long-polling bot, no inbound ports needed except internal health)
HEALTHCHECK --interval=30s --timeout=5s --start-period=120s --retries=3 \
  CMD curl -f http://localhost:8080/health || exit 1

CMD ["bun", "run", "src/index.ts"]
