# Tasks: security(web-platform) add .dockerignore

Source: `knowledge-base/project/plans/2026-03-20-security-web-platform-dockerignore-plan.md`
Issue: #807

## Phase 1: Implementation

- [ ] 1.1 Create `apps/web-platform/.dockerignore` with exclusions mirroring telegram-bridge pattern plus Next.js-specific entries
  - Exclude: `node_modules`, `.env`, `.env.example`, `.env*.local`, `infra/`, `.git`, `.gitignore`, `*.md`, `test/`, `supabase/`, `.next/`, `out/`, `*.pem`, `*.tsbuildinfo`, `next-env.d.ts`, `Dockerfile`, `.dockerignore`, `docker-compose*.yml`
  - Do NOT exclude: `tsconfig.json` (Next.js TypeScript compilation), `next.config.ts` (build config), `postcss.config.mjs` (Tailwind CSS 4), `middleware.ts`, `server/`, `app/`, `lib/`

## Phase 2: Verification

- [ ] 2.1 Run `docker build apps/web-platform/` locally to confirm the build still succeeds with the new `.dockerignore`
- [ ] 2.2 Verify excluded files are not in the build context (check `docker build` output for context size reduction)
- [ ] 2.3 Inspect image layers to confirm no `.env`, `.git/`, or `infra/` files are present

## Phase 3: Ship

- [ ] 3.1 Commit with `security(web-platform): add .dockerignore to prevent secret leakage`
- [ ] 3.2 Push and create PR with `Closes #807` in body
- [ ] 3.3 Merge and verify CI release workflow builds successfully
