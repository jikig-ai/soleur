# Tasks: Docker Multi-Stage Build for Web Platform

## Phase 1: Setup

- [ ] 1.1 Verify current Docker build works (`docker build -t test-before apps/web-platform/`) to establish baseline
- [ ] 1.2 Record current image size for comparison (`docker images test-before`)

## Phase 2: Core Implementation

- [ ] 2.1 Rewrite `apps/web-platform/Dockerfile` as a 3-stage multi-stage build
  - [ ] 2.1.1 Stage 1 (`deps`): `FROM node:22-slim`, copy `package.json` + `package-lock.json`, run `npm ci`
  - [ ] 2.1.2 Stage 2 (`builder`): extend `deps`, copy source, accept `NEXT_PUBLIC_*` ARGs, run `npm run build`, run esbuild to compile `server/` to `dist/server/index.js`
  - [ ] 2.1.3 Stage 3 (`runner`): fresh `FROM node:22-slim`, install `@anthropic-ai/claude-code@2.1.79` globally, install `git`, copy `package.json` + `package-lock.json`, run `npm ci --omit=dev`, copy `.next/`, `public/`, `dist/server/`, `next.config.ts` from builder
- [ ] 2.2 Update `apps/web-platform/package.json`
  - [ ] 2.2.1 Add `build:server` script: `esbuild server/index.ts --bundle --platform=node --target=node22 --outfile=dist/server/index.js --external:next --external:react --external:react-dom --external:@supabase/supabase-js --external:@supabase/ssr --external:ws --external:stripe --external:@anthropic-ai/claude-agent-sdk`
  - [ ] 2.2.2 Update `start` script from `NODE_ENV=production tsx server/index.ts` to `NODE_ENV=production node dist/server/index.js`
  - [ ] 2.2.3 Add `esbuild` to devDependencies
- [ ] 2.3 Replace `curl`-based healthcheck with `node -e "fetch('http://localhost:3000/health').then(r=>{process.exit(r.ok?0:1)}).catch(()=>process.exit(1))"`
- [ ] 2.4 Update `CMD` from `["npm", "run", "start"]` to `["node", "dist/server/index.js"]`

## Phase 3: Testing

- [ ] 3.1 Build the multi-stage image locally (`docker build -t test-after apps/web-platform/ --build-arg NEXT_PUBLIC_SUPABASE_URL=test --build-arg NEXT_PUBLIC_SUPABASE_ANON_KEY=test`)
- [ ] 3.2 Verify no devDependencies in production image (`docker run --rm test-after npm ls --omit=dev 2>&1`)
- [ ] 3.3 Verify `claude` CLI is available (`docker run --rm test-after claude --version`)
- [ ] 3.4 Verify `git` is available (`docker run --rm test-after git --version`)
- [ ] 3.5 Compare image sizes (`docker images test-before` vs `docker images test-after`)
- [ ] 3.6 Start container and verify `/health` endpoint responds
- [ ] 3.7 Verify healthcheck passes inside container (`docker inspect --format='{{.State.Health.Status}}' <container>`)
