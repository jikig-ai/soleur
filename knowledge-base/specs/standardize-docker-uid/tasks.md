# Tasks: standardize soleur UID across all Dockerfiles

## Phase 1: Dockerfile Changes

- [ ] 1.1 Update `apps/telegram-bridge/Dockerfile` line 21: replace `useradd -m soleur` with `useradd --no-log-init --uid 1001 -m soleur`
- [ ] 1.2 Update `apps/web-platform/Dockerfile` lines 47-49: replace `USER node` with `useradd --no-log-init --uid 1001 -m soleur`, `chown -R soleur:soleur .next`, and `USER soleur`
  - [ ] 1.2.1 Add `RUN useradd --no-log-init --uid 1001 -m soleur && chown -R soleur:soleur .next` before `USER` directive
  - [ ] 1.2.2 Change `USER node` to `USER soleur`
  - [ ] 1.2.3 Update comment from "(node:22-slim includes a 'node' user at uid 1000)" to "(UID 1001 avoids collision with node:22-slim's built-in node user at UID 1000)"

## Phase 2: Verification

- [ ] 2.1 Build telegram-bridge image: `docker build -t soleur-bridge-test apps/telegram-bridge/`
- [ ] 2.2 Verify telegram-bridge UID: `docker run --rm soleur-bridge-test id` -- expect `uid=1001(soleur)`
- [ ] 2.3 Build web-platform image (requires build args): `docker build --build-arg NEXT_PUBLIC_SUPABASE_URL=test --build-arg NEXT_PUBLIC_SUPABASE_ANON_KEY=test -t soleur-web-test apps/web-platform/`
- [ ] 2.4 Verify web-platform UID: `docker run --rm soleur-web-test id` -- expect `uid=1001(soleur)`
- [ ] 2.5 Verify web-platform git config: `docker run --rm soleur-web-test git config --global user.name` -- expect "Soleur"
