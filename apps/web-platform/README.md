# Web Platform

The Soleur Command Center — a Next.js 15 web app that hosts the chat router (`/soleur:go`), KB Concierge sidebar, and the Claude Agent SDK runners.

## Requirements

- **Node.js ≥ 22.3** (`engines.node` in `package.json`). The PDF text extractor lazy-imports `pdfjs-dist@5`, which calls `process.getBuiltinModule()` during module init — that API was added in Node 22.3 / 20.16. The production Dockerfile uses `node:22-slim`, so the floor is pinned to 22.3 to keep contributor and runtime matrices aligned. Node 21.x will fail with `process.getBuiltinModule is not a function` on any code path that exercises the in-process PDF extractor. Run `nvm use` (or `fnm use` / `asdf install`) from `apps/web-platform/` to land on the binding floor — this directory's `.nvmrc` pins `22.3.0`.

## Running locally

From `apps/web-platform`, with Node ≥ 22.3 active and Doppler available:

```bash
doppler run -p soleur -c dev -- npm run dev
```

If port 3000 is bound, set `PORT=3099` (the user may have a parallel dev server running).

### Dev-only sign-in panel (multi-account QA)

Supabase's free-tier email-OTP cap (~4/hour, project-wide) blocks rapid multi-account QA. The login page conditionally renders a `DevSignInPanel` that authenticates against three pre-seeded test users via password — bypassing the OTP rate limit entirely.

The panel renders only when **both** conditions hold:
1. `NODE_ENV === "development"` (strict literal — `NODE_ENV=test` does NOT match), AND
2. `FLAG_DEV_SIGNIN === "1"` in Doppler `dev`.

The matching API route (`POST /api/auth/dev-signin`) enforces the same gate and authenticates against `dev-{1,2,3}@example.com` using passwords from `DEV_USER_{1,2,3}_PASSWORD`. `verify-required-secrets.sh` exits non-zero in CI's prd run if any of those keys are present in Doppler `prd`.

**One-time setup** (operator, separate terminal — never via the `!` Claude Code shell prefix per `hr-never-paste-secrets-via-bang-prefix`):

```bash
# 1. Set the flag and three passwords in Doppler dev.
doppler secrets set FLAG_DEV_SIGNIN=1                       -p soleur -c dev
doppler secrets set DEV_USER_1_PASSWORD=$(openssl rand -hex 16) -p soleur -c dev
doppler secrets set DEV_USER_2_PASSWORD=$(openssl rand -hex 16) -p soleur -c dev
doppler secrets set DEV_USER_3_PASSWORD=$(openssl rand -hex 16) -p soleur -c dev

# 2. Verify presence (length-only — never echo values).
for k in FLAG_DEV_SIGNIN DEV_USER_1_PASSWORD DEV_USER_2_PASSWORD DEV_USER_3_PASSWORD; do
  printf '%-24s %s\n' "$k" "$(doppler secrets get "$k" -p soleur -c dev --plain | wc -c)"
done

# 3. Confirm prd-side absence.
doppler secrets -p soleur -c prd | grep -E "^(FLAG_DEV_SIGNIN|DEV_USER_)" \
  && echo "FAIL — leak in prd" \
  || echo "OK — prd is clean"

# 4. Seed the three test users in dev Supabase (idempotent).
doppler run -p soleur -c dev -- bash apps/web-platform/scripts/seed-dev-users.sh
```

After setup, `npm run dev` shows the panel above the OTP form. Click "Sign in as dev-N" and you land on `/` authenticated as that user.

**Vercel preview note:** Vercel previews default `NODE_ENV` to `production`, so the panel will not render in preview deployments even if `FLAG_DEV_SIGNIN` were ever set there. Verify via `vercel env ls preview` that `NODE_ENV` is unset and `FLAG_DEV_SIGNIN` is absent before merging any change to this surface.

## Testing

```bash
./node_modules/.bin/vitest run            # unit + integration suite
./node_modules/.bin/vitest run path/to/file.test.ts
npx tsc --noEmit                          # type-check (covers test files vitest skips)
```

See `test/README.md` for the integration suite's env flags.
