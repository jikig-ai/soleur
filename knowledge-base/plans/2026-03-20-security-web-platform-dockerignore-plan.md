---
title: "security(web-platform): add .dockerignore to prevent secret leakage into build context"
type: fix
date: 2026-03-20
---

## Enhancement Summary

**Deepened on:** 2026-03-20
**Sections enhanced:** 5
**Research sources used:** Docker official docs (Context7), Node.js best practices, Next.js Docker guides, web-platform source analysis

### Key Improvements
1. Fixed contradiction: removed `tsconfig.json` from acceptance criteria exclusion list (Next.js requires it at build time)
2. Added `postcss.config.mjs` and `next.config.ts` to explicit "must NOT exclude" list after verifying they are required for Tailwind CSS and Next.js build
3. Added `Dockerfile` and `.dockerignore` self-exclusion per Docker official best practices
4. Added `docker-compose*.yml` exclusion per Docker official patterns
5. Identified that `server/`, `lib/`, `app/`, `middleware.ts` are all required at runtime (custom server pattern via `tsx server/index.ts`)

### New Considerations Discovered
- The Dockerfile uses `npm ci --production=false` (installs devDependencies including `@tailwindcss/postcss`), so `postcss.config.mjs` must be in the build context
- `next.config.ts` sets `serverExternalPackages` for ws and claude-agent-sdk -- excluding it would break the build
- Docker official docs recommend excluding the `Dockerfile` itself from the build context to avoid unnecessary layer invalidation

---

# security(web-platform): add .dockerignore to prevent secret leakage into build context

The web-platform Dockerfile uses `COPY . .` (line 12) but has no `.dockerignore`. Every `docker build` sends the entire directory as build context, including `.env` files, `.git/` history, `node_modules/`, `infra/` (Terraform state), `test/`, and `supabase/`. These files end up in the final image layers, leaking secrets and bloating image size.

## Acceptance Criteria

- [ ] `apps/web-platform/.dockerignore` exists and excludes at minimum: `node_modules`, `.env`, `.env.example`, `.env*.local`, `infra/`, `.git`, `.gitignore`, `*.md`, `test/`, `supabase/`, `.next/`, `out/`, `*.pem`, `*.tsbuildinfo`, `next-env.d.ts`, `Dockerfile`, `.dockerignore`, `docker-compose*.yml`
- [ ] The pattern mirrors `apps/telegram-bridge/.dockerignore` for consistency, extended with Next.js-specific entries
- [ ] `tsconfig.json`, `next.config.ts`, `postcss.config.mjs`, and `middleware.ts` are NOT excluded (required at build time)
- [ ] Docker build still succeeds: `docker build apps/web-platform/` produces a working image (Next.js build completes, health check passes)
- [ ] No secrets or unnecessary files are present in the built image layers

## Test Scenarios

- Given a `.dockerignore` exists, when `docker build apps/web-platform/` runs, then `.env`, `.git/`, `node_modules/`, `infra/`, `test/`, and `supabase/` are NOT in the build context
- Given `.dockerignore` excludes `node_modules`, when `docker build` runs, then `npm ci` in the Dockerfile installs fresh dependencies (existing behavior, no regression)
- Given `.dockerignore` does NOT exclude `tsconfig.json`, `next.config.ts`, or `postcss.config.mjs`, when `docker build` runs, then the Next.js build succeeds with Tailwind CSS processing and TypeScript path resolution
- Given `.dockerignore` excludes `test/`, when `docker build` runs, then test files are not shipped in the production image
- Given `.dockerignore` excludes `Dockerfile` and `.dockerignore`, when `docker build` runs, then these meta-files do not appear in the image

### Research Insights (Test Scenarios)

**Edge case -- glob pattern matching:**
Docker's `.dockerignore` uses Go's `filepath.Match` rules. The pattern `.env*.local` matches `.env.local` and `.env.development.local` but NOT `.env` (no trailing match). The separate `.env` line handles the base case. Verify both patterns work independently.

**Edge case -- build-arg secrets:**
The Dockerfile passes `NEXT_PUBLIC_SUPABASE_URL` and `NEXT_PUBLIC_SUPABASE_ANON_KEY` as build args. These are public keys (anon key is safe for client-side), but they persist in image layer metadata. This is a pre-existing concern outside this PR's scope -- document it but don't block on it.

## Context

### Security Risk (P2)

The `COPY . .` on line 12 of the Dockerfile copies everything in the build context into the image. Without `.dockerignore`, this includes:

| Path | Risk | Severity |
|------|------|----------|
| `.env` / `.env*.local` | Direct secret exposure (API keys, DB credentials) | Critical |
| `.git/` | Full repo history, potentially including rotated secrets | Critical |
| `*.pem` | Private keys | Critical |
| `infra/` | Terraform configs with server IPs, SSH key references | High |
| `node_modules/` | Bloated image (~264KB lockfile suggests large tree), supply-chain risk from dev dependencies | Medium |
| `test/` | Unnecessary test code in production | Low |
| `supabase/` | Migration scripts, database templates | Low |

### Research Insights (Security)

**Docker official guidance:** The `.dockerignore` file should exclude development-specific files, temporary artifacts, version control metadata, and sensitive configuration. Docker's own containerization guides for React/Node.js projects recommend excluding `*.env*`, `.git/`, `node_modules/`, `*.tsbuildinfo`, coverage directories, IDE configs, and the `Dockerfile` itself.

**Node.js best practices (goldbergyoni/nodebestpractices):** `.dockerignore` acts as a safety net that filters out potential secrets. Development and CI folders (`.npmrc`, `.aws`, `.env`) can be exposed if not properly excluded. The `.dockerignore` should be treated as a security control, not just a build optimization.

**Supply-chain consideration:** Excluding `node_modules` is both a size optimization and a security measure. The Dockerfile's `npm ci` installs from the lockfile, ensuring reproducible, verified dependencies rather than whatever happens to be in the local `node_modules/`.

### Existing Pattern

`apps/telegram-bridge/.dockerignore` (the only other Docker-built app) already excludes:

```
node_modules
.env
.env.example
infra/
scripts/
.git
.gitignore
*.md
tsconfig.json
```

The web-platform `.dockerignore` mirrors this with two deliberate deviations:
1. **Does NOT exclude `tsconfig.json`** -- Next.js requires it at build time for path aliases and TypeScript compilation (telegram-bridge uses Bun which has its own resolution)
2. **Does NOT have `scripts/`** -- web-platform has no `scripts/` directory at its root (the `supabase/scripts/` subdirectory is covered by the `supabase/` exclusion)

### CI Pipeline

The `reusable-release.yml` workflow uses `docker/build-push-action` with `context: apps/web-platform`. Docker automatically reads `.dockerignore` from the build context root, so placing the file at `apps/web-platform/.dockerignore` is correct -- no CI changes needed.

### Research Insights (CI Pipeline)

**BuildKit context handling:** When using `docker/build-push-action` (which uses BuildKit), the `.dockerignore` is read from the root of the build context directory. Since `docker_context` is set to `apps/web-platform`, the file at `apps/web-platform/.dockerignore` is the correct location. No `docker_file` override is needed since the `Dockerfile` is also at the context root.

### Files Required at Build Time (Must NOT Exclude)

Analysis of the Dockerfile, `next.config.ts`, `postcss.config.mjs`, and `package.json` reveals these files must remain in the build context:

| File | Reason |
|------|--------|
| `package.json` | Copied explicitly on line 9 (`COPY package.json package-lock.json ./`) |
| `package-lock.json` | Copied explicitly on line 9; used by `npm ci` |
| `tsconfig.json` | Required by `next build` for TypeScript path aliases and compilation options |
| `next.config.ts` | Required by `next build`; configures `serverExternalPackages` for ws and claude-agent-sdk |
| `postcss.config.mjs` | Required by Tailwind CSS 4 during `next build`; referenced by `@tailwindcss/postcss` plugin |
| `middleware.ts` | Next.js middleware, loaded at build time |
| `app/` | Next.js App Router pages and components |
| `lib/` | Shared utilities imported by app and server code |
| `server/` | Custom server (`tsx server/index.ts`) -- the production entry point |

### tsconfig.json Exclusion

The telegram-bridge pattern excludes `tsconfig.json`. For web-platform, `next build` reads `tsconfig.json` to resolve path aliases and TypeScript options. **Do NOT exclude `tsconfig.json`** -- unlike the telegram-bridge (which uses `bun run` with its own resolution), Next.js needs `tsconfig.json` at build time. This is a deliberate deviation from the telegram-bridge pattern.

## MVP

### `apps/web-platform/.dockerignore`

```dockerignore
# Dependencies (installed fresh via npm ci in Dockerfile)
node_modules

# Environment files (secrets)
.env
.env.example
.env*.local

# Infrastructure (Terraform configs)
infra/

# Version control
.git
.gitignore

# Documentation
*.md

# Test files
test/

# Supabase (migrations/templates not needed at runtime)
supabase/

# Next.js build output (rebuilt in Docker)
.next/
out/

# Security-sensitive files
*.pem

# TypeScript build artifacts
*.tsbuildinfo
next-env.d.ts

# Docker meta-files (not needed inside the image)
Dockerfile
.dockerignore
docker-compose*.yml
```

**Files intentionally NOT excluded (required at build time):**
- `tsconfig.json` -- Next.js TypeScript compilation
- `next.config.ts` -- Next.js build configuration (serverExternalPackages)
- `postcss.config.mjs` -- Tailwind CSS 4 processing
- `middleware.ts` -- Next.js middleware
- `server/` -- Custom server entry point (production runtime)
- `app/`, `lib/` -- Application source code

### Research Insights (MVP)

**Docker official best practices applied:**
- Self-exclusion of `Dockerfile` and `.dockerignore` prevents unnecessary context transmission and layer invalidation (from Docker's React containerization guide)
- `*.env*` pattern is intentionally NOT used as a single glob because it would also match `.env.production` files that some Next.js setups legitimately need; instead, specific patterns (`.env`, `.env.example`, `.env*.local`) provide precise control
- Comments explain the "why" for each exclusion group, following Docker's recommended documentation pattern

**Compared with Docker's official Node.js template:**
The official Docker docs `.dockerignore` for Node.js projects also excludes `npm-debug.log`, `.DS_Store`, `.vscode/`, `.vs/`, `charts/`, and `docker-compose*`. Of these, only `docker-compose*.yml` is relevant here (the others are either OS-specific or not present in this project).

## References

- Issue: #807
- Pattern: `apps/telegram-bridge/.dockerignore`
- Dockerfile: `apps/web-platform/Dockerfile:12` (`COPY . .`)
- CI: `.github/workflows/reusable-release.yml` (docker_context: `apps/web-platform`)
- Learning: `knowledge-base/learnings/2026-03-19-docker-base-image-digest-pinning.md`
- Learning: `knowledge-base/learnings/2026-03-19-npm-global-install-version-pinning.md`
- Related PR: #803 (security review that found this gap)
- Docker official `.dockerignore` guide: https://docs.docker.com/build/building/best-practices/#exclude-with-dockerignore
- Node.js best practices (`.dockerignore`): https://github.com/goldbergyoni/nodebestpractices/blob/master/sections/docker/docker-ignore.md
- Docker containerization guide (React/Node.js): https://github.com/docker/docs/blob/main/content/guides/reactjs/containerize.md
- Docker secrets best practices: https://docs.docker.com/build/building/secrets/
