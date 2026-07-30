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

## Local Supabase stack (RLS-fuzz substrate)

The disposable local stack backing the ADR-111 RLS-fuzz harness. **Always start it through the
wrapper, never with bare `supabase start`:**

```bash
npm run db:start              # start, bound to 127.0.0.1
npm run db:stop               # stop it when you are not using it
npm run db:status
npm run db:assert-loopback    # verify the binding; exit 1 = exposed
npm run db:cli -- db diff     # passthrough: db diff / db reset / migration / gen types
```

**Why the wrapper.** The Supabase CLI has **no bind-address setting** — `config.toml` declares
no *listener* host key at any level (the one `host =` it contains is a commented outbound SMTP
relay), and the CLI sets Docker `PortBindings` with no `HostIP`, so a bare `supabase start`
publishes *every* service on `0.0.0.0` **and** `::`. That puts Postgres (54322) and the
**unauthenticated Studio admin UI** (54323) on whatever network your laptop is attached to. Upstream
implemented a bind option and closed it unmerged on policy (`supabase/cli#4613`), prescribing a
Docker network instead — so the wrapper is the permanent, vendor-documented fix, not a stopgap.
See [ADR-153](../../knowledge-base/engineering/architecture/decisions/ADR-153-local-supabase-loopback-binding-via-docker-network.md).

**Stop it when not in use.** Loopback binding reduces blast radius; it does not eliminate the local
surface.

**Caveat:** the `host_binding_ipv4` bridge option is a rootful-Linux-Docker feature. On Docker
Desktop or rootless setups the binding may differ. `npm run db:assert-loopback` reports what the
Docker API recorded for every labelled container, regardless of how the stack was started — note
that on Desktop that record lives inside the VM, so it is authoritative about the declared
binding, not about a host socket. Exit codes: 0 = loopback-only or no stack, 1 = exposed,
2 = could not verify (never read 2 as safe).

**Fixtures are synthesized only.** Never seed this stack from production data.

## Testing

```bash
./node_modules/.bin/vitest run            # unit + integration suite
./node_modules/.bin/vitest run path/to/file.test.ts
npx tsc --noEmit                          # type-check (covers test files vitest skips)
```

See `test/README.md` for the integration suite's env flags.

## Lockfile note

`apps/web-platform/package-lock.json` is regenerated by CI under **npm 11**.
If you run `npm install --package-lock-only` locally to sync the lockfile
after a `package.json` change (or a `bun add`), use:

```bash
npx --yes npm@11 install --package-lock-only
```

Using a different npm version will produce a divergent lockfile shape (npm 10
emits `"dev": true` on optional transitive packages where npm 11 does not),
and the `lockfile-sync` CI gate will fail on the PR.
