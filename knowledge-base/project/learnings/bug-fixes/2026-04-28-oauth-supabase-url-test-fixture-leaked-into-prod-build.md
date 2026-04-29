---
date: 2026-04-28
tags: [supabase, oauth, ci, secrets, build-time-inlining, dual-source-of-truth]
status: applied
issue: 2979
pr: 2975
---

# OAuth broken in prod — test fixture host leaked into the production JS bundle via `secrets.NEXT_PUBLIC_SUPABASE_URL`

## What happened

Clicking the Google OAuth button on `https://app.soleur.ai/login` redirected to `https://test.supabase.co/auth/v1/authorize?provider=google&redirect_to=https%3A%2F%2Fapp.soleur.ai%2Fcallback&...`, which failed with `Server Not Found` because `test.supabase.co` is not a real Supabase project. All four configured OAuth providers (Google, Apple, GitHub, Microsoft) were affected — Supabase's `signInWithOAuth` reuses the same base URL for every provider.

Forensics:

- `curl https://app.soleur.ai/login` → resolved login chunk `/_next/static/chunks/app/(auth)/login/page-1145cd8d8475e73c.js` → `grep -oE 'https?://[a-z0-9.-]*supabase\.co'` returned `https://test.supabase.co`. The literal placeholder string was inlined into the client bundle.
- `gh secret list --json name,updatedAt` showed `NEXT_PUBLIC_SUPABASE_URL.updatedAt = 2026-04-27T10:50:45Z` — matched the user-visible outage window.
- Doppler `prd.NEXT_PUBLIC_SUPABASE_URL = https://api.soleur.ai` (correct). Doppler `dev.NEXT_PUBLIC_SUPABASE_URL = https://mlwiodleouzwniehynfz.supabase.co` (correct, distinct).
- `dig +short CNAME api.soleur.ai` → `ifsccnjhymdmidffkzhl.supabase.co.` (CNAME healthy).
- JWT `ref` claim on `prd.NEXT_PUBLIC_SUPABASE_ANON_KEY` decoded to `ifsccnjhymdmidffkzhl` (matches CNAME target — anon key was not the broken thing).

The bug was therefore not "wrong Doppler value" but **dual-source-of-truth divergence**: Doppler held the right value while the prod Docker build read from `secrets.NEXT_PUBLIC_SUPABASE_URL` (a separate GitHub repo secret) — and only the latter had drifted.

## Why it happened

`apps/web-platform`'s production image is built by `.github/workflows/reusable-release.yml`. The build step (line 286-307 at the time of writing) consumes `${{ secrets.NEXT_PUBLIC_SUPABASE_URL }}` via Docker `build-args`. Next.js then inlines `process.env.NEXT_PUBLIC_*` references into client chunks at build time via Webpack `DefinePlugin`. Once a chunk is built, the value is **immutable**; runtime env changes do not flow through.

`apps/web-platform/test/*` uses `https://test.supabase.co` as a placeholder via `process.env.NEXT_PUBLIC_SUPABASE_URL ??= "https://test.supabase.co"` in 24 files. The most plausible operational origin is operator copy-paste during a credentials rotation on `2026-04-27T10:50:45Z` — pasting the test fixture into the GitHub repo secret slot.

This bug class is the same as `knowledge-base/project/learnings/2026-04-07-ux-agent-placeholder-secrets-trigger-push-protection.md` — placeholder-shaped values reaching live secret stores — generalized from CI tokens to `NEXT_PUBLIC_*` build-args.

Preflight `Check 4` (`hr-dev-prd-distinct-supabase-projects`) checks Doppler dev/prd isolation. It does **not** read GitHub repo secrets, because `gh secret list` cannot retrieve secret values. The bug surface was Check 4's blind spot.

## Fix

PR #2975 (this PR) ships a multi-layer defense. The actual prod outage is fixed by an operator-run command after merge.

1. **Pre-build CI assertion** (`.github/workflows/reusable-release.yml`): a step `Validate NEXT_PUBLIC_SUPABASE_URL build-arg` runs before `docker/build-push-action` and fails the workflow with `::error::` annotations if `${{ secrets.NEXT_PUBLIC_SUPABASE_URL }}` does not match `^https://([a-z0-9]{20}\.supabase\.co|api\.soleur\.ai)$`. Catches the bug class with zero blast radius (no image is built, no deploy webhook fires).
2. **Runtime canonical-shape guard** (`apps/web-platform/lib/supabase/allowed-hosts.ts`): a new module exports `assertProdSupabaseUrl(raw)` that throws on placeholder hosts (`test`, `placeholder`, `example`, `localhost`, `0.0.0.0`), insecure protocols, malformed URLs, and any host that doesn't match `^[a-z0-9]{20}\.supabase\.co$` or appear in `PROD_ALLOWED_HOSTS = ["api.soleur.ai"]`. **Gated on `process.env.NODE_ENV === "production"`** so the 24 test files using `https://test.supabase.co` are unaffected. `lib/supabase/client.ts` calls `assertProdSupabaseUrl(...)` at the top of `createClient()`; the validator's own module is not mocked by the 9 test files that `vi.mock("@/lib/supabase/client", ...)` (per `cq-test-mocked-module-constant-import`).
3. **Doppler-side shape check** (`apps/web-platform/scripts/verify-required-secrets.sh`): adds a regex assertion mirroring the CI step so a placeholder-shaped value entered into Doppler `prd` also fails the secret-verification job.
4. **Preflight Check 5** (`plugins/soleur/skills/preflight/SKILL.md`): a new path-gated check that fetches the deployed `_next/static/chunks/app/(auth)/login/page-*.js` chunk (filename discovered dynamically — chunks are content-hashed) and asserts the union of Supabase host references is canonical. This is the GitHub-secret-blind-spot complement to Check 4.

The actual bug is fixed by an operator-run sequence after merge:

1. Verify Supabase project `uri_allow_list` includes `https://app.soleur.ai/callback`. (Without this, OAuth fails post-consent with `redirect_to is not allowed` even after the URL is correct.) Note: a `SUPABASE_ACCESS_TOKEN` from Doppler `prd` returned 401 against `GET /v1/projects/<ref>/config/auth` during plan execution — confirm the allowlist via the Supabase Dashboard, or refresh the access token to one with `read:auth_config` scope.
2. Rotate the GitHub repo secret: `gh secret set NEXT_PUBLIC_SUPABASE_URL --body 'https://api.soleur.ai'`.
3. Trigger a release workflow run: `gh workflow run reusable-release.yml ...`. The new Validate step now runs before any Docker work — confirm it passes.
4. Re-probe the deployed bundle: `grep -oE 'https?://[a-z0-9.-]*supabase\.co'` against the freshly-built login chunk should return `https://api.soleur.ai` (or canonical ref) and zero placeholder strings.
5. Playwright OAuth probe (Google + GitHub) reaches the providers' consent screens with no DNS error.

## Lesson

GitHub repo secrets feeding `NEXT_PUBLIC_*` Docker build-args are a **silent deployment-time substitution**: the value is invisible after `gh secret set` (only `name` + `updatedAt` are queryable), survives only as text inlined into client JS chunks, and cannot be re-read or canary-tested without producing a fresh build. The natural defense-in-depth is **multiple shape-assertion gates** at different stages of the pipeline:

- Doppler write → `verify-required-secrets.sh` regex (Doppler-side gate).
- GitHub-secret write → CI Validate step (build-time gate; catches the GitHub-secrets surface).
- Build → runtime `assertProdSupabaseUrl` (post-build gate; catches the case where the regex itself drifts).
- Deploy → preflight Check 5 / post-deploy bundle probe (post-deploy gate; black-box truth).

Any single gate could be bypassed (regex broken, env drift, mock interference) — together they make the placeholder-leak class near-impossible.

The deferred follow-up is consolidating to a single source of truth: migrate `reusable-release.yml` to `doppler run -p soleur -c prd -- docker build ...` instead of `secrets.NEXT_PUBLIC_*`, eliminating the dual-source-of-truth class entirely. Tracked in PR #2975 as Non-Goal NG1, filed as issues #2980 (generalize CI shape validation to other 5 NEXT_PUBLIC build-args) and #2981 (Doppler-only build-args migration / Option B / AP-008 alignment).

## Session Errors

- **Plan subagent cited non-existent rule `cq-ops-remediation-pr-uses-ref-not-closes`** — Recovery: caught and corrected during deepen-plan to the actual `wg-use-closes-n-in-pr-body-not-title-to`. Prevention: plan/deepen-plan skills should `grep -nE '^- .*\[id: cq-ops' AGENTS.md` before citing any rule ID; cite-or-fail.
- **PreToolUse `security_reminder_hook` fires on every workflow YAML edit even when the safe `env:` pattern is already in use** — Recovery: re-issued the identical Edit call, landed on retry. Prevention: hook is broadly advisory (intended); no fix needed, but the hook output should clearly say "advisory only — not blocking" when the diff already uses the safe pattern, or treat the second invocation of the same edit as auto-pass.
- **`gh issue create --label P1` rejected** — Recovery: ran `gh label list --limit 200 | grep -i p1` to discover `priority/p1-high`. Prevention: align with `cq-gh-issue-label-verify-name` — always verify label namespacing (`priority/p1-high`, not bare `P1`) before `gh issue create`.
- **Supabase Management API 401 on `GET /v1/projects/<ref>/config/auth`** — Recovery: documented blocker in #2979 + plan AC9.2; deferred `uri_allow_list` verification to operator via Supabase Dashboard. Prevention: extend Doppler `prd` to also expose a Management API token with `read:auth_config` scope (separate from the deploy token), OR document in the runbook that auth-config reads route through Dashboard until that token exists.
- **Pre-existing flaky test (`chat-page.test.tsx > does NOT send msg when sessionConfirmed is false`)** — Recovery: re-ran in isolation and confirmed it passes; verified no diff overlap with the PR. Prevention: not actionable in this PR's scope; pre-existing flake should be tracked separately if it recurs.
- **Forgot to Read after `git mv` rename** — Recovery: Read the new path then Write succeeded. Prevention: when `git mv` renames a file, treat the new path as if it had never been read; the harness tracks state by path. Add to `hr-always-read-a-file-before-editing-it` understanding: rename invalidates prior reads.
