# Learning: .dockerignore patterns differ between Next.js and Bun runtimes

## Problem

When creating a .dockerignore for web-platform by mirroring the telegram-bridge pattern, the plan initially excluded tsconfig.json. This would break the Next.js build because `next build` reads tsconfig.json for path aliases and TypeScript options.

## Solution

Verified each file in the existing pattern against the target app's build requirements before copying:

- tsconfig.json: Required by Next.js (excluded in Bun app) — DO NOT exclude
- postcss.config.mjs: Required by Tailwind CSS 4 during next build — DO NOT exclude
- next.config.ts: Required for serverExternalPackages — DO NOT exclude

Also consolidated .env patterns to single `.env*` glob for broader coverage.

## Key Insight

When adapting Docker configurations between apps with different runtimes (Bun vs Node.js/Next.js), verify which config files each build tool actually reads. The same filename (tsconfig.json) can be optional in one runtime and required in another.

## Session Errors

None — clean session.

## Tags

category: build-errors
module: web-platform, docker
