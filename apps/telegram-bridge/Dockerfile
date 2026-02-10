FROM oven/bun:latest

# Install system dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends git curl openssh-client && \
    rm -rf /var/lib/apt/lists/*

# Install Claude Code CLI
RUN curl -fsSL https://claude.ai/install.sh | sh

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
HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
  CMD curl -f http://localhost:8080/health || exit 1

CMD ["bun", "run", "src/index.ts"]
