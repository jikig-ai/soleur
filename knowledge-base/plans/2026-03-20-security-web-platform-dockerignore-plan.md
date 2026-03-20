---
title: "security(web-platform): add .dockerignore to prevent secret leakage into build context"
type: fix
date: 2026-03-20
---

# security(web-platform): add .dockerignore to prevent secret leakage into build context

The web-platform Dockerfile uses `COPY . .` (line 12) but has no `.dockerignore`. Every `docker build` sends the entire directory as build context, including `.env` files, `.git/` history, `node_modules/`, `infra/` (Terraform state), `test/`, and `supabase/`. These files end up in the final image layers, leaking secrets and bloating image size.

## Acceptance Criteria

- [ ] `apps/web-platform/.dockerignore` exists and excludes at minimum: `node_modules`, `.env`, `.env.example`, `.env*.local`, `infra/`, `.git`, `.gitignore`, `*.md`, `tsconfig.json`, `test/`, `supabase/`, `.next/`, `*.pem`, `*.tsbuildinfo`, `next-env.d.ts`
- [ ] The pattern mirrors `apps/telegram-bridge/.dockerignore` for consistency, extended with Next.js-specific entries from `.gitignore`
- [ ] Docker build still succeeds: `docker build apps/web-platform/` produces a working image (Next.js build completes, health check passes)
- [ ] No secrets or unnecessary files are present in the built image layers

## Test Scenarios

- Given a `.dockerignore` exists, when `docker build apps/web-platform/` runs, then `.env`, `.git/`, `node_modules/`, `infra/`, `test/`, and `supabase/` are NOT in the build context
- Given `.dockerignore` excludes `node_modules`, when `docker build` runs, then `npm ci` in the Dockerfile installs fresh dependencies (existing behavior, no regression)
- Given `.dockerignore` excludes `tsconfig.json`, when `docker build` runs, then the Next.js build still succeeds because `next build` uses its internal config resolution (verify: `tsconfig.json` is read at dev time, but `next build` works without it in the `COPY . .` context since `package.json` and source files are present)
- Given `.dockerignore` excludes `test/`, when `docker build` runs, then test files are not shipped in the production image

## Context

### Security Risk (P2)

The `COPY . .` on line 12 of the Dockerfile copies everything in the build context into the image. Without `.dockerignore`, this includes:

| Path | Risk |
|------|------|
| `.env` / `.env*.local` | Direct secret exposure (API keys, DB credentials) |
| `.git/` | Full repo history, potentially including rotated secrets |
| `infra/` | Terraform configs with server IPs, SSH key references |
| `node_modules/` | Bloated image, supply-chain risk from dev dependencies |
| `test/` | Unnecessary test code in production |
| `supabase/` | Migration scripts, database templates |
| `*.pem` | Private keys |

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

The web-platform `.dockerignore` should mirror this and add Next.js-specific exclusions from the web-platform `.gitignore` (`.next/`, `out/`, `*.tsbuildinfo`, `next-env.d.ts`, `*.pem`).

### CI Pipeline

The `reusable-release.yml` workflow uses `docker/build-push-action` with `context: apps/web-platform`. Docker automatically reads `.dockerignore` from the build context root, so placing the file at `apps/web-platform/.dockerignore` is correct -- no CI changes needed.

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
```

**Note:** `tsconfig.json` is intentionally NOT excluded -- Next.js requires it at build time.

## References

- Issue: #807
- Pattern: `apps/telegram-bridge/.dockerignore`
- Dockerfile: `apps/web-platform/Dockerfile:12` (`COPY . .`)
- CI: `.github/workflows/reusable-release.yml` (docker_context: `apps/web-platform`)
- Learning: `knowledge-base/learnings/2026-03-19-docker-base-image-digest-pinning.md`
- Related PR: #803 (security review that found this gap)
