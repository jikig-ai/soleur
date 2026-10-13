# fix: OAuth broken in prod — `app.soleur.ai` build inlines `https://test.supabase.co`

**Date:** 2026-04-28
**Branch:** `feat-one-shot-fix-oauth-supabase-url`
**Worktree:** `.worktrees/feat-one-shot-fix-oauth-supabase-url/`
**Severity:** P1 (login fully broken for all OAuth users)
**Type:** prod-affecting bug fix + structural guardrail

## Enhancement Summary

**Deepened on:** 2026-04-28
**Sections enhanced:** Hypotheses, Files to Edit, Implementation Phases (2, 3, 4), Risks, Acceptance Criteria
**Research applied:** Supabase OAuth/custom-domain semantics, GitHub Actions `secrets.*` rotation forensics, Next.js `NEXT_PUBLIC_*` build-time inlining, learning `2026-04-07-ux-agent-placeholder-secrets-trigger-push-protection.md` (placeholder-secret class)

### Key Improvements

1. **Source-of-truth analysis converged on a structural fix:** the bug is not "wrong Doppler value" but **dual-source-of-truth divergence** — Doppler `prd` is correct, but the prod build reads GitHub repo secrets, and the two drifted. The plan now explicitly chooses Option A (CI-time consistency check between Doppler and GitHub secret) with Option B (Doppler-only build-args) as a tracked follow-up.
2. **Multi-layer defense** (4 layers): pre-build CI regex assertion → runtime client.ts production guard → post-deploy bundle probe → preflight Check 5. Each layer alone catches the bug class; together they make recurrence near-impossible.
3. **Custom-domain JWT-ref consistency** added as Risk R3 with concrete mitigation: cross-check `dig CNAME api.soleur.ai` against the anon-key JWT `ref` claim. Without this, a future Supabase project rotation would silently break auth while bundle probe still passes.
4. **Test-suite blast radius accounted for:** 24 test files use `https://test.supabase.co` as a placeholder. The runtime guard explicitly gates on `NODE_ENV === "production"` so tests are unaffected. Verified via grep before plan finalization.
5. **Rule citation fixed:** an earlier draft cited a non-existent rule `cq-ops-remediation-pr-uses-ref-not-closes`. Replaced with the actual rule `wg-use-closes-n-in-pr-body-not-title-to` and operator-procedure rationale (PR ships guardrail; bug fix is the operator-run secret rotation, so `Ref #N`, not `Closes #N`).

### New Considerations Discovered

- **JWT `ref` claim is the load-bearing consistency check** for custom-domain Supabase setups. The anon key encodes the project ref; the URL hostname is decoupled (custom domain). Drift between the two = silent auth misroute. Phase 1 step 5 captures this; consider promoting to a permanent Check 4.5.
- **GitHub repo secrets cannot be read back** — `gh secret list` returns name + `updated_at` only. The CI Validate step is the only place the value can be asserted before it's baked into a build. After-the-fact verification requires either a JS-bundle probe or a runtime `/health` extension.
- **`updated_at: 2026-04-27T10:50:45Z`** on `NEXT_PUBLIC_SUPABASE_URL` matches the operational origin hypothesis (operator-error during a credentials rotation). The bug has been live since that timestamp; `gh run list` history will identify the build that picked it up.
- **Supabase custom domains and OAuth redirect URIs:** when the URL changes (even from custom to canonical or vice versa), the OAuth provider's allowed redirect URIs in Supabase Dashboard must include the corresponding `<base>/auth/v1/callback`. Verify both `https://api.soleur.ai/auth/v1/callback` and `https://ifsccnjhymdmidffkzhl.supabase.co/auth/v1/callback` are in the allowlist before re-running the workflow — see Phase 3 step 0 below.
- **Placeholder-secret class** (per learning `2026-04-07-ux-agent-placeholder-secrets-trigger-push-protection.md`): operator-pasted placeholders into real secret slots is a known recurrent class. The CI Validate step generalizes that learning to the `NEXT_PUBLIC_*` build-arg surface.

## Overview

Clicking the Google OAuth button on `https://app.soleur.ai/login` redirects the browser to `https://test.supabase.co/auth/v1/authorize?provider=google&redirect_to=…` which fails with DNS NXDOMAIN. `test.supabase.co` is the **literal placeholder string used by every test file in `apps/web-platform/test/*` (24 occurrences)** and was inlined into the production JS bundle at Docker build time. All OAuth providers (Google, Apple, GitHub, Microsoft) are affected — Supabase's `signInWithOAuth` reuses the same base URL for every provider.

This plan does three things:

1. **Fix the immediate prod outage** by correcting the GitHub Actions secret feeding the Docker build and re-running the release workflow.
2. **Reconcile the dual-source-of-truth** that allowed the bug: Doppler `prd` holds `NEXT_PUBLIC_SUPABASE_URL=https://api.soleur.ai` (correct, custom-domain CNAME → real prd ref), but the prod image is built from `secrets.NEXT_PUBLIC_SUPABASE_URL` (a separate GitHub repo secret, currently `https://test.supabase.co`). These two paths drifted.
3. **Add a guardrail** that would catch the same drift class in the future — both pre-build (CI workflow validates the `NEXT_PUBLIC_SUPABASE_*` build-args before invoking `docker build`) and post-deploy (`/health` or a black-box probe verifies the served bundle resolves a canonical Supabase host).

Note: existing preflight `Check 4` already verifies dev/prd Doppler isolation (`hr-dev-prd-distinct-supabase-projects`). It does NOT catch this bug class because the prod image-build doesn't consume Doppler — it consumes GitHub repo secrets. The new guardrail extends Check 4 to the actually-load-bearing surface (CI build-args).

## Research Reconciliation — Spec vs. Codebase

| Spec claim (from feature description) | Codebase reality | Plan response |
|---|---|---|
| "production frontend built/deployed with placeholder `NEXT_PUBLIC_SUPABASE_URL`" | Confirmed: `curl https://app.soleur.ai/_next/static/chunks/app/(auth)/login/page-1145cd8d8475e73c.js \| grep -oE 'https?://[a-z0-9.-]*supabase\.co'` returns `https://test.supabase.co`. | Fix the source feeding that build-arg. |
| "check Doppler `prd` config and `NEXT_PUBLIC_*` references" (implies Doppler feeds the build) | **Doppler does NOT feed the production Docker build.** `.github/workflows/reusable-release.yml:298-302` consumes `${{ secrets.NEXT_PUBLIC_SUPABASE_URL }}` (GitHub repo secret), not Doppler. Doppler `prd` value is `https://api.soleur.ai` (the CNAME → `ifsccnjhymdmidffkzhl.supabase.co`); GitHub secret currently produces `https://test.supabase.co` in the bundle. | Fix the GitHub repo secret (the actual source). Document Doppler-vs-GitHub-secrets split. Decide whether to consolidate to a single source or keep both with a CI-time consistency check. |
| "Verify dev Supabase is unaffected" | Doppler `dev.NEXT_PUBLIC_SUPABASE_URL` = `https://mlwiodleouzwniehynfz.supabase.co` (canonical, distinct from prd). Distinct from `ifsccnjhymdmidffkzhl` (prd ref). Local dev and prd run on separate Supabase projects per `hr-dev-prd-distinct-supabase-projects`. ✓ | No change needed for dev. Verify dev OAuth flow as a control. |
| "extend `plugins/soleur/skills/preflight/`" | preflight Check 4 ALREADY validates Doppler dev/prd isolation. It does NOT validate GitHub repo secrets. The bug surface is Check 4's blind spot. | Add a new check (Check 5: build-arg parity) that compares `secrets.NEXT_PUBLIC_SUPABASE_URL` (via `gh secret list` + canary deploy verify) against canonical regex AND against Doppler `prd` value, OR move the source-of-truth to Doppler in `reusable-release.yml`. |
| "test.supabase.co is not a real Supabase project hostname" | Confirmed. Real refs match `^[a-z0-9]{20}\.supabase\.co$`. `test` is 4 chars. The string came from a test fixture (`apps/web-platform/test/*` uses it as a placeholder via `process.env.NEXT_PUBLIC_SUPABASE_URL ??= "https://test.supabase.co"` in 24 files). Likely path: an operator pasted the test fixture value into the GitHub repo secret on `2026-04-27T10:50:45Z`. | Fix the secret. Add a secret-write linter / CI assertion so a placeholder-shaped value can never be the live secret. |

## Hypotheses (Root Cause)

H1 (most likely, near-confirmed): The GitHub repository secret `NEXT_PUBLIC_SUPABASE_URL` was rotated/edited on `2026-04-27T10:50:45Z` (per `gh secret list`) to the literal test-fixture value `https://test.supabase.co`. The next release-workflow run (`reusable-release.yml`) inlined this value into the Docker image at build time as `ARG NEXT_PUBLIC_SUPABASE_URL`, baked into all `_next/static/chunks/app/(auth)/login/page-*.js` bundles. Every OAuth click since that build has called `https://test.supabase.co/auth/v1/authorize…`.

H2 (less likely, ruled out by JS-bundle inspection): The build-arg was empty and the runtime fallback in `lib/supabase/client.ts` (`DEV_PLACEHOLDER_URL = "https://placeholder.supabase.co"`) fired. This is ruled out — the bundle contains the literal `https://test.supabase.co`, not `placeholder.supabase.co`, and the client throws in production when the URL is missing (line 9-11). The placeholder fallback only triggers in non-production.

H3 (less likely): A test setup file leaked into the production build via Webpack tree-shaking failure. Ruled out — the `process.env.NEXT_PUBLIC_SUPABASE_URL ??= …` defaulting in test files only applies if the env var is unset; the build inlines the build-arg directly via Next.js `NEXT_PUBLIC_*` substitution, not via a `process.env` read at runtime.

H4 (operational origin): Operator confused dev/prd or copy-pasted a test fixture during a credentials rotation. Reachable signal: secret `updated_at` is `2026-04-27T10:50:45Z`, matches the start of the user-visible outage window (issue not yet filed).

## Open Code-Review Overlap

```bash
gh issue list --label code-review --state open --json number,title,body --limit 200 > /tmp/open-review-issues.json
for path in apps/web-platform/lib/supabase/client.ts apps/web-platform/Dockerfile .github/workflows/reusable-release.yml plugins/soleur/skills/preflight/SKILL.md; do
  jq -r --arg path "$path" '.[] | select(.body // "" | contains($path)) | "#\(.number): \(.title)"' /tmp/open-review-issues.json
done
```

To run during execution. Default disposition for any match: **Fold in** if the scope-out is about Supabase build-arg drift or CI secret hygiene; **Acknowledge** if unrelated.

## Files to Edit

| Path | Change |
|---|---|
| `.github/workflows/reusable-release.yml` | (a) Add a pre-build validation step that asserts `NEXT_PUBLIC_SUPABASE_URL` matches `^https://([a-z0-9]{20}\.supabase\.co\|api\.soleur\.ai)$` (canonical OR explicit allowlisted custom domain). Fail the workflow with a clear message if not. (b) Optionally migrate the source from `secrets.NEXT_PUBLIC_SUPABASE_URL` to a `doppler run -p soleur -c prd --` invocation so Doppler is the single source of truth. Defer (b) to a follow-up if scope grows. |
| `plugins/soleur/skills/preflight/SKILL.md` | Add Check 5 (build-arg parity): when changes touch `apps/web-platform/Dockerfile` or `.github/workflows/reusable-release.yml`, list `NEXT_PUBLIC_*` GitHub repo secrets via `gh secret list` and verify each `NEXT_PUBLIC_SUPABASE_*` value structurally. The secret VALUE cannot be read by `gh secret list`, so the check is a **canary deploy probe**: after a release, fetch the deployed `_next/static/chunks/app/**/page-*.js` and grep for the canonical Supabase host. Fail if the bundle contains a non-canonical host. |
| `apps/web-platform/lib/supabase/client.ts` | Tighten the production guard: currently throws if `NEXT_PUBLIC_SUPABASE_URL` is missing, but accepts ANY non-empty value. Add a runtime canonical-shape assertion (`^https://([a-z0-9]{20}\.supabase\.co\|api\.soleur\.ai)$`) that throws in `NODE_ENV === "production"` if the value matches the placeholder shape (`test\.supabase\.co`, `placeholder\.supabase\.co`, `example\.supabase\.co`, `localhost`). |
| `apps/web-platform/scripts/verify-required-secrets.sh` | Add a regex assertion for `NEXT_PUBLIC_SUPABASE_URL` shape (canonical OR allowlisted custom domain) — currently only checks presence. |

## Files to Create

| Path | Purpose |
|---|---|
| `apps/web-platform/test/lib/supabase/client-prod-guard.test.ts` | Unit test for the new client-side canonical-shape guard. RED first per `cq-write-failing-tests-before`. Covers: throws on `https://test.supabase.co`, `https://placeholder.supabase.co`, empty string, `https://[a-z0-9]{19}.supabase.co` (19-char first label, off-by-one), `http://...` (insecure), `https://evil.com/wrapper.supabase.co`. Passes on `https://ifsccnjhymdmidffkzhl.supabase.co` and `https://api.soleur.ai`. |
| `.github/workflows/build-arg-validate.yml` (or new step inside `reusable-release.yml`) | CI-time pre-build assertion that the `NEXT_PUBLIC_SUPABASE_URL` build-arg matches the canonical regex. |
| `knowledge-base/project/learnings/bug-fixes/2026-04-28-oauth-supabase-url-test-fixture-leaked-into-prod-build.md` | Compound-style learning capturing the dual-source-of-truth class: Doppler vs GitHub repo secrets divergence, why preflight Check 4 didn't catch it, fix and prevention. |
| `knowledge-base/project/specs/feat-one-shot-fix-oauth-supabase-url/spec.md` | Feature spec (use `skill: soleur:spec-templates`). |
| `knowledge-base/project/specs/feat-one-shot-fix-oauth-supabase-url/tasks.md` | Task breakdown derived from this plan. |

## Implementation Phases

### Phase 1 — Confirm root cause and gather evidence (READ-ONLY)

1. Re-confirm the deployed JS bundle still contains `https://test.supabase.co` (in case prod has rolled forward since plan write).

   ```bash
   curl -sL -A "Mozilla/5.0" https://app.soleur.ai/login -o /tmp/login.html
   grep -oE '/_next/static/chunks/app/\(auth\)/login/page-[a-f0-9]+\.js' /tmp/login.html | head -1
   # then for the matched chunk:
   curl -sL "https://app.soleur.ai<chunk_path>" | grep -oE 'https?://[a-z0-9.-]*supabase\.co' | sort -u
   # Expected current: https://test.supabase.co
   # Expected after fix: https://api.soleur.ai (or canonical ref)
   ```

2. Capture the current GitHub repo secret metadata (timestamps, names — values are not retrievable):

   ```bash
   gh secret list --json name,updatedAt | jq '.[] | select(.name | startswith("NEXT_PUBLIC_SUPABASE"))'
   ```

3. Capture the current Doppler `prd` and `dev` values for parity reference:

   ```bash
   doppler secrets get NEXT_PUBLIC_SUPABASE_URL -p soleur -c prd --plain
   doppler secrets get NEXT_PUBLIC_SUPABASE_URL -p soleur -c dev --plain
   ```

4. Verify `api.soleur.ai` resolves to the prd ref:

   ```bash
   dig +short CNAME api.soleur.ai
   # Expected: ifsccnjhymdmidffkzhl.supabase.co.
   ```

5. Decode the prd anon key JWT `ref` claim to confirm consistency:

   ```bash
   doppler secrets get NEXT_PUBLIC_SUPABASE_ANON_KEY -p soleur -c prd --plain | cut -d. -f2 | base64 -d 2>/dev/null | jq .ref
   # Expected: "ifsccnjhymdmidffkzhl"
   ```

### Phase 2.0 — Pre-flight: verify Supabase OAuth redirect URIs are configured for the chosen URL

Before changing the GitHub secret, verify that the Supabase Auth dashboard allows the chosen redirect-target host. If `app.soleur.ai/callback` is not in the Supabase project's "Redirect URLs" allowlist for the host the build will use, OAuth will return after Google consent but Supabase will reject the callback with `redirect_to is not allowed`.

```bash
# List allowed redirect URLs via Supabase Management API
# (token in Doppler prd as SUPABASE_ACCESS_TOKEN)
doppler secrets get SUPABASE_ACCESS_TOKEN -p soleur -c prd --plain > /tmp/sb-tok
PROJECT_REF=ifsccnjhymdmidffkzhl
curl -sH "Authorization: Bearer $(cat /tmp/sb-tok)" \
  "https://api.supabase.com/v1/projects/$PROJECT_REF/config/auth" \
  | jq '{site_url, uri_allow_list}'
shred -u /tmp/sb-tok
```

Expected: `uri_allow_list` contains `https://app.soleur.ai/callback` (and ideally also `https://app.soleur.ai/**` for query-param safety). If absent, this is a separate Supabase Dashboard fix that must precede Phase 2 — adding the allowlist entry is a Management-API PATCH; document the exact PATCH body in the operator handoff.

### Phase 2 — Set the GitHub repo secret to the correct value (DESTRUCTIVE PROD WRITE)

Per `hr-menu-option-ack-not-prod-write-auth`: show the exact command and **wait for explicit per-command go-ahead** before executing.

The correct value is `https://api.soleur.ai` (current Doppler `prd` value, matches the CNAME and JWT ref). Setting it to the canonical `https://ifsccnjhymdmidffkzhl.supabase.co` would also work but breaks the Supabase custom-domain abstraction; matching Doppler keeps drift surface low.

Exact command (DO NOT run until ack):

```bash
printf '%s' 'https://api.soleur.ai' | gh secret set NEXT_PUBLIC_SUPABASE_URL --body -
```

Verify the secret was updated:

```bash
gh secret list --json name,updatedAt | jq '.[] | select(.name == "NEXT_PUBLIC_SUPABASE_URL") | .updatedAt'
# Expected: timestamp within the last minute
```

### Phase 3 — Trigger production rebuild and verify

`NEXT_PUBLIC_*` are baked at Docker-build time, so updating the secret alone does NOT change running prod. A fresh release build is required.

1. Push a no-op commit on a tagged PR or trigger the release workflow manually:

   ```bash
   gh workflow run reusable-release.yml -f component_display=web-platform -f docker_image=ghcr.io/jikig-ai/soleur/web-platform -f docker_context=apps/web-platform
   ```

   (or whatever the release-workflow trigger surface looks like — verify by `gh workflow list` first.)

2. Poll the run to completion:

   ```bash
   gh run list --workflow=reusable-release.yml --limit 1 --json databaseId,status,conclusion
   ```

3. After the deploy webhook reports success (per `cq-deploy-webhook-observability-debug`), re-run the bundle probe from Phase 1.1:

   ```bash
   curl -sL https://app.soleur.ai/login -o /tmp/login.html
   chunk=$(grep -oE '/_next/static/chunks/app/\(auth\)/login/page-[a-f0-9]+\.js' /tmp/login.html | head -1)
   curl -sL "https://app.soleur.ai$chunk" | grep -oE 'https?://[a-z0-9.-]*supabase\.co' | sort -u
   # Expected: https://api.soleur.ai (NOT https://test.supabase.co)
   ```

4. Black-box OAuth verification with Playwright MCP — ABSOLUTE PATHS REQUIRED per `hr-mcp-tools-playwright-etc-resolve-paths`:

   - Navigate to `https://app.soleur.ai/login`.
   - Click the Google OAuth button. Capture `mcp__playwright__browser_network_requests` immediately.
   - Assert the first cross-origin request after click goes to a host matching `^https://(api\.soleur\.ai|[a-z0-9]{20}\.supabase\.co)/auth/v1/authorize`.
   - Per `hr-when-playwright-mcp-hits-an-auth-wall`, when Google's consent screen appears, keep the browser tab open and ask the operator to complete consent — do NOT hand off by URL.
   - Repeat for one additional provider (Apple, GitHub, or Microsoft — pick GitHub for fastest verification).

5. Capture `/health` to confirm the runtime supabase connection is healthy:

   ```bash
   curl -s https://app.soleur.ai/health | jq .
   # Expected: { "status": "ok", "supabase": "connected", ... }
   ```

### Phase 4 — Add the runtime + build-time guardrails (TDD)

Per `cq-write-failing-tests-before`, write failing tests first.

1. **Client-side canonical-shape guard** (`apps/web-platform/lib/supabase/client.ts`):

   - Test file: `apps/web-platform/test/lib/supabase/client-prod-guard.test.ts`.
   - Cases:
     - `NODE_ENV=production` + `NEXT_PUBLIC_SUPABASE_URL=https://test.supabase.co` → `createClient()` THROWS with message containing `placeholder` or `non-canonical`.
     - `NODE_ENV=production` + `NEXT_PUBLIC_SUPABASE_URL=https://placeholder.supabase.co` → THROWS.
     - `NODE_ENV=production` + `NEXT_PUBLIC_SUPABASE_URL=https://example.supabase.co` → THROWS (4-char first label).
     - `NODE_ENV=production` + `NEXT_PUBLIC_SUPABASE_URL=http://ifsccnjhymdmidffkzhl.supabase.co` → THROWS (insecure protocol).
     - `NODE_ENV=production` + `NEXT_PUBLIC_SUPABASE_URL=https://ifsccnjhymdmidffkzhl.supabase.co` → does NOT throw.
     - `NODE_ENV=production` + `NEXT_PUBLIC_SUPABASE_URL=https://api.soleur.ai` → does NOT throw (custom-domain allowlist).
     - `NODE_ENV=development` + `NEXT_PUBLIC_SUPABASE_URL=https://test.supabase.co` → does NOT throw (test-friendly fallback retained).
   - Implementation:
     - Maintain an explicit `PROD_ALLOWED_HOSTS = ["api.soleur.ai"]` allowlist constant for custom-domain values. Per `cq-test-mocked-module-constant-import`: the test file must NOT `vi.mock("./client")`; test imports the constant directly, or hardcodes the allowlist values verbatim with a `// sync with PROD_ALLOWED_HOSTS in client.ts` comment.
     - Regex: `^https:\/\/([a-z0-9]{20}\.supabase\.co|api\.soleur\.ai)$`.
     - Reject also: bare placeholder hosts (`test`, `placeholder`, `example`, `localhost`, `0.0.0.0`).
   - **Important:** Tighten in production only. Do not break the 24 test files that intentionally set `NEXT_PUBLIC_SUPABASE_URL=https://test.supabase.co` — they run with `NODE_ENV=test` (or unset). Verify by running `node ./apps/web-platform/node_modules/.bin/vitest run apps/web-platform/test/` after the change.

2. **CI-time pre-build assertion** (`.github/workflows/reusable-release.yml`):

   - Add a step BEFORE `docker/build-push-action` that fails if `${{ secrets.NEXT_PUBLIC_SUPABASE_URL }}` does not match the regex. Per `hr-in-github-actions-run-blocks-never-use`, no heredocs and no multi-line strings below the YAML literal block's base indentation.
   - Skeleton (verify exact YAML indent in the actual file before committing):

     ```yaml
     - name: Validate NEXT_PUBLIC_SUPABASE_URL build-arg
       env:
         SUPABASE_URL: ${{ secrets.NEXT_PUBLIC_SUPABASE_URL }}
       run: |
         set -euo pipefail
         if [[ ! "$SUPABASE_URL" =~ ^https://([a-z0-9]{20}\.supabase\.co|api\.soleur\.ai)$ ]]; then
           echo "::error::NEXT_PUBLIC_SUPABASE_URL has non-canonical value (likely a placeholder leak)"
           echo "::error::Expected: https://<20-char-ref>.supabase.co or https://api.soleur.ai"
           exit 1
         fi
     ```

   - Per `wg-after-merging-a-pr-that-adds-or-modifies`: trigger a manual run (`gh workflow run reusable-release.yml`) after merge and poll to completion to verify the new step works.

3. **Post-deploy bundle probe** (extend an existing post-deploy verification or add to `postmerge` skill):

   - After every release, fetch a known login chunk and grep for the canonical Supabase host. Fail if a non-canonical host is found in the bundle. Wire into `plugins/soleur/skills/postmerge/` or as a job in `.github/workflows/postmerge-verify.yml`.
   - This is the load-bearing guardrail per `wg-when-a-feature-creates-external` — black-box probe of user-visible outcome.

4. **Preflight Check 5** (`plugins/soleur/skills/preflight/SKILL.md`):

   - When `git diff --name-only origin/main...HEAD` includes `.github/workflows/reusable-release.yml`, `apps/web-platform/Dockerfile`, or `apps/web-platform/lib/supabase/client.ts`:
     - Read the deployed prod bundle (Phase 3 step 3 logic).
     - Assert it contains a canonical Supabase host.
     - PASS / FAIL / SKIP semantics per Check 4 conventions.
   - Document this is the GitHub-secret-blind-spot complement to Check 4.

5. **Decision: consolidate to Doppler as single source of truth?**

   - Option A (preferred, low-risk): Keep both sources, add CI-time consistency check (`gh secret list` shape + Doppler value match assertion).
   - Option B (cleaner, riskier): Migrate `reusable-release.yml` to fetch values via `doppler run` instead of GitHub repo secrets. Requires `DOPPLER_TOKEN_PRD` secret in CI per `cq-doppler-service-tokens-are-per-config`. Defer to follow-up if scope grows.
   - The plan adopts Option A unless review says otherwise.

### Phase 5 — Post-merge verification and operator handoff

1. Per `wg-after-a-pr-merges-to-main-verify-all`:
   - Watch the release workflow, deploy-docs workflow, and any postmerge probe.
   - Confirm `/health` continues to return `supabase: connected`.
   - Confirm the login chunk on `app.soleur.ai` resolves to the canonical host.

2. Capture the learning per `wg-before-every-commit-run-compound-skill` and the existing dual-source-of-truth class (Doppler vs GitHub secrets) in `knowledge-base/project/learnings/bug-fixes/2026-04-28-oauth-supabase-url-test-fixture-leaked-into-prod-build.md`.

3. Filing follow-ups (per `wg-when-deferring-a-capability-create-a`):
   - If Option B (consolidate to Doppler-only) is deferred, file a tracking issue.
   - If any of the 24 test files still using `https://test.supabase.co` should be migrated to a less foot-gunny placeholder (e.g., `https://placeholder.supabase.co.invalid` or a per-suite mock URL) to reduce risk of operator copy-paste, file a tracking issue.

## Acceptance Criteria

### Pre-merge (PR)

- [x] **AC1** A PR is open with the changes scoped to (a) preflight Check 5, (b) `reusable-release.yml` validation step, (c) `client.ts` runtime guard, (d) test file `client-prod-guard.test.ts`, (e) learning file. Per `wg-use-closes-n-in-pr-body-not-title-to`: PR body contains `Closes #<issue>` if a tracking issue is filed first; otherwise omit and file a follow-up.
- [x] **AC2** RED phase: the new `client-prod-guard.test.ts` fails before `client.ts` is changed (verified via a single test-run on the failing assertion).
- [x] **AC3** GREEN phase: all `apps/web-platform/test/**` tests pass, including the 24 existing files that set `NEXT_PUBLIC_SUPABASE_URL=https://test.supabase.co` for unit-test scope. Run via `cd apps/web-platform && ./node_modules/.bin/vitest run` per `cq-in-worktrees-run-vitest-via-node-node`.
- [x] **AC4** `tsc --noEmit` passes in `apps/web-platform`.
- [ ] **AC5** The `reusable-release.yml` Validate step is exercised on a non-prod branch (or via a draft release dry-run) and rejects a deliberately placeholder-shaped value (smoke-test the new regex). _Deferred to post-merge per `wg-after-merging-a-pr-that-adds-or-modifies` — the Validate step's regex matches `verify-required-secrets.sh` which is smoke-tested locally (placeholder rejected, canonical accepted, exit codes 1/0)._
- [ ] **AC6** Plan review (DHH/Kieran/Code-Simplicity) signs off OR has explicit fix-inline disposition per `rf-review-finding-default-fix-inline`.
- [x] **AC7** Per `cq-docs-cli-verification`: every `gh secret set`, `gh workflow run`, `doppler secrets get`, `dig`, and `curl` invocation prescribed above is verified against the tool's official help / tested locally with `<tool> --help` before committing.
- [x] **AC8** Verify no plan AC depends on un-run external state per `cq-plan-ac-external-state-must-be-api-verified` — Phase 1 collects all such state via API at execution start, not from this plan's prose.
- [x] **AC9** Per `hr-dev-prd-distinct-supabase-projects`: dev still resolves to `mlwiodleouzwniehynfz` and prd to `ifsccnjhymdmidffkzhl` after the fix (preflight Check 4 PASSES).
- [x] **AC9.1** JWT-ref consistency: prd anon-key `ref` claim equals the project ref the prd URL resolves to (canonical-ref decode for canonical hostnames; CNAME-target decode for custom domains). Fail-loud if drifted.
- [ ] **AC9.2** Phase 2.0 verified: Supabase project `uri_allow_list` includes `https://app.soleur.ai/callback`. If absent, the PATCH body is documented in PR description and operator-acked separately before the secret rotation. _Blocked: `SUPABASE_ACCESS_TOKEN` from Doppler `prd` returned 401 against `GET /v1/projects/<ref>/config/auth`. Operator must verify via Supabase Dashboard or refresh the access token to one with `read:auth_config` scope before Phase 2 secret rotation. Tracked in #2979._

### Post-merge (operator)

- [ ] **AC10** Phase 2 ack obtained from operator; `gh secret set NEXT_PUBLIC_SUPABASE_URL --body -` executed; secret `updated_at` advanced.
- [ ] **AC11** Release workflow re-run completes (deploy succeeds, container reports healthy).
- [ ] **AC12** Bundle probe confirms `_next/static/chunks/app/(auth)/login/page-*.js` contains `https://api.soleur.ai` (or canonical ref) and contains zero occurrences of `test.supabase.co`.
- [ ] **AC13** Playwright OAuth probe (Google + GitHub) reaches Google's / GitHub's consent screen — no DNS error, no `test.supabase.co` in network log.
- [ ] **AC14** Issue (filed at session start) closed via `gh issue close <N>` after Phase 3 verification passes (NOT `Closes #N` in PR body — the bug is fixed by an operator-run command **after merge**, not by the PR diff itself; the PR ships only the guardrail. Use `Ref #N` per `wg-use-closes-n-in-pr-body-not-title-to`).

### Research Insights — Phase 4 Implementation Details

**Best Practices (Next.js `NEXT_PUBLIC_*` build-time inlining):**

- `NEXT_PUBLIC_*` variables are inlined at build time via Webpack's `DefinePlugin`. Once a build is produced, the value is **immutable** — environment changes at runtime do NOT flow through. This is why the runtime guard in `client.ts` is load-bearing despite the build-time CI Validate step: belt-and-suspenders for the case where the Validate regex is broken or bypassed.
- Next.js docs explicitly warn against using `NEXT_PUBLIC_*` for secrets — values land in client JS visible to anyone. The Supabase URL is intentionally public (anon key is public too, RLS enforces access). This is consistent with our usage.
- Per `cq-test-mocked-module-constant-import`: if any test file `vi.mock("./client")`s the supabase client module, a `PROD_ALLOWED_HOSTS` constant exported from `client.ts` will resolve to the mock factory. Run `rg "vi\.mock\(['\"](.*)supabase/client['\"]" apps/web-platform/test/` before extracting the constant. If hits exist: copy the allowlist verbatim into the test with a `// sync with PROD_ALLOWED_HOSTS in client.ts` comment, OR put the allowlist in a separate non-mocked module (`apps/web-platform/lib/supabase/allowed-hosts.ts`).

**Implementation pattern for `client.ts` runtime guard (sketch — verify exact form during work phase):**

```ts
const PROD_ALLOWED_HOSTS = ["api.soleur.ai"] as const;
const CANONICAL_REF_RE = /^[a-z0-9]{20}\.supabase\.co$/;
const PLACEHOLDER_HOSTS = new Set(["test.supabase.co", "placeholder.supabase.co", "example.supabase.co", "localhost", "0.0.0.0"]);

function assertProdSupabaseUrl(raw: string | undefined): void {
  if (process.env.NODE_ENV !== "production") return;
  if (!raw) throw new Error("Missing NEXT_PUBLIC_SUPABASE_URL");
  let u: URL;
  try { u = new URL(raw); } catch { throw new Error(`Invalid NEXT_PUBLIC_SUPABASE_URL: ${raw}`); }
  if (u.protocol !== "https:") throw new Error(`Insecure NEXT_PUBLIC_SUPABASE_URL protocol: ${u.protocol}`);
  if (PLACEHOLDER_HOSTS.has(u.hostname)) {
    throw new Error(`NEXT_PUBLIC_SUPABASE_URL is a placeholder host (${u.hostname}). This indicates a build-arg leak from a test fixture.`);
  }
  const allowed = PROD_ALLOWED_HOSTS.includes(u.hostname as (typeof PROD_ALLOWED_HOSTS)[number]) || CANONICAL_REF_RE.test(u.hostname);
  if (!allowed) throw new Error(`NEXT_PUBLIC_SUPABASE_URL host ${u.hostname} is not canonical (^[a-z0-9]{20}\\.supabase\\.co$) and not in PROD_ALLOWED_HOSTS.`);
}
```

**Edge cases to cover in tests (T1-T5):**

- IDN/punycode hosts (`xn--…`) — reject; canonical refs are pure ASCII lowercase + digits.
- Trailing slash / path (`https://api.soleur.ai/`) — `new URL().hostname` strips path, so works. But add an explicit test that `https://api.soleur.ai/anything` still passes (path is irrelevant) and `https://api.soleur.ai.evil.com` rejects.
- Port specifiers (`https://api.soleur.ai:443`) — `new URL().hostname` returns the bare host without port; works.
- Wildcard ref pattern length (the canonical 20-char first label) — boundary tests at 19 (reject), 20 (accept), 21 (reject).

**References:**

- Next.js NEXT_PUBLIC_ docs: <https://nextjs.org/docs/app/api-reference/file-conventions/env#bundling-environment-variables-for-the-browser>
- Supabase Auth Management API (uri_allow_list): <https://api.supabase.com/api/v1#/projects/getProjectAuthConfig>
- Supabase custom domains: <https://supabase.com/docs/guides/platform/custom-domains>

## Test Scenarios

| ID | Scenario | Expected |
|---|---|---|
| T1 | `createClient()` in production with `NEXT_PUBLIC_SUPABASE_URL=https://test.supabase.co` | THROWS with message mentioning `non-canonical` / `placeholder` |
| T2 | `createClient()` in production with `NEXT_PUBLIC_SUPABASE_URL=https://api.soleur.ai` | Succeeds |
| T3 | `createClient()` in production with `NEXT_PUBLIC_SUPABASE_URL=https://ifsccnjhymdmidffkzhl.supabase.co` | Succeeds |
| T4 | `createClient()` in production with `NEXT_PUBLIC_SUPABASE_URL=https://placeholder.supabase.co` | THROWS |
| T5 | `createClient()` in test/dev with `NEXT_PUBLIC_SUPABASE_URL=https://test.supabase.co` | Succeeds (test-friendly behavior preserved) |
| T6 | CI Validate step run with `secrets.NEXT_PUBLIC_SUPABASE_URL=https://test.supabase.co` | Workflow FAILS at validation step, never invokes `docker build` |
| T7 | CI Validate step run with `secrets.NEXT_PUBLIC_SUPABASE_URL=https://api.soleur.ai` | Workflow proceeds to `docker build` |
| T8 | Bundle probe after correct deploy | Bundle contains canonical host, zero placeholder strings |
| T9 | Playwright Google-OAuth click after fix | First post-click XHR target host matches `^https://(api\.soleur\.ai\|[a-z0-9]{20}\.supabase\.co)/` |
| T10 | Playwright GitHub-OAuth click after fix | Same as T9 (one other provider verified per scope item 4) |
| T11 | `client.ts` guard with `https://api.soleur.ai/path?qs=1` (path + query) | Succeeds (path/query irrelevant; only hostname matters) |
| T12 | `client.ts` guard with `https://api.soleur.ai.evil.com` | THROWS (subdomain-bypass guard — hostname is `api.soleur.ai.evil.com`, not in allowlist and not canonical regex match) |
| T13 | `client.ts` guard with `https://abcdefghij1234567890.supabase.co` (exactly 20 lowercase alnum) | Succeeds |
| T14 | `client.ts` guard with `https://abcdefghij123456789.supabase.co` (19 chars — boundary) | THROWS |
| T15 | Phase 2.0 — `uri_allow_list` already includes `https://app.soleur.ai/callback` | Skip the Management API PATCH step |
| T16 | Phase 2.0 — `uri_allow_list` missing `https://app.soleur.ai/callback` | Halt Phase 2; document the Supabase Auth PATCH body and request operator ack |

## Risks

- **R1 (high) — Operator-error retrigger:** the same path that introduced the bug (operator pasted a test fixture into the GitHub secret) can recur. Mitigation: CI Validate step (Phase 4 step 2) catches it pre-build with zero blast radius. Acceptance criterion AC6 exercises the rejection path.
- **R2 (medium) — Test-file blast radius:** 24 test files use `https://test.supabase.co` as a placeholder. The runtime guard (`client.ts`) tightens in production only. If a future test ever sets `NODE_ENV=production`, those tests will start failing. Mitigation: cite the production-only gating explicitly in code comments using grep-stable symbol anchors per `cq-code-comments-symbol-anchors-not-line-numbers`; comment references `PROD_ALLOWED_HOSTS`, not line numbers.
- **R3 (medium) — `api.soleur.ai` custom domain abstraction:** if Supabase ever rotates the underlying ref (`ifsccnjhymdmidffkzhl`) or the CNAME drifts, the bundle would still have `https://api.soleur.ai` (correct on the surface) but the Auth API behind it would change. The anon-key JWT ref claim would no longer match the served project. Mitigation: extend Check 4 (or the new Check 5) to also cross-check `dig CNAME api.soleur.ai` resolves to the same project ref encoded in the anon key JWT. Defer to follow-up if scope grows.
- **R4 (low) — Doppler vs GitHub secrets divergence persists post-fix:** Option A keeps two sources of truth. The CI-time consistency check is mitigation, but a future operator could still update one without the other. Tracked via the deferred follow-up (Option B: consolidate to Doppler).
- **R5 (low) — Bundle probe brittleness:** chunk filenames are content-hashed and change every build. The probe must dynamically discover the chunk filename via the `/login` HTML, not hardcode a hash.
- **R6 (medium) — OAuth redirect URI allowlist drift:** if the Supabase project's `uri_allow_list` does not include `https://app.soleur.ai/callback`, OAuth will fail post-consent with `redirect_to is not allowed` even after the URL bundle is correct. Phase 2.0 (added in deepen-pass) verifies this. Sign of failure: Google consent succeeds, browser returns to Supabase, then redirects to a Supabase error page instead of `app.soleur.ai/callback`. Mitigation: Phase 2.0 is a preflight gate; AC10 cannot pass without it.
- **R7 (low) — Multi-arch / cache-warm builds reuse stale layers:** `docker/build-push-action` caches Stage 1 (deps) but Stage 2 (builder) re-runs because `COPY . .` invalidates on any source change. The build-arg change DOES invalidate Stage 2 because `ARG` lines participate in cache keys. Verified by inspection of `apps/web-platform/Dockerfile` — `ARG NEXT_PUBLIC_SUPABASE_URL` at line 13 is upstream of `RUN npm run build` at line 26. No additional cache-bust step needed.
- **R8 (medium) — Sentry-noise during the outage window:** the runtime guard added in Phase 4.1 will throw on any prod request once deployed if the build-arg is still wrong. This is the desired fail-loud behavior, but it will produce a Sentry burst. Per `cq-silent-fallback-must-mirror-to-sentry` the throw is correct; the burst is a feature, not a bug. Operator should expect a spike in `apps/web-platform` Sentry between rotation and rebuild — set Better Stack incident comment beforehand.

## Non-Goals

- **NG1** Migrating ALL `NEXT_PUBLIC_*` build-args from GitHub secrets to Doppler. Out of scope for this P1 fix; tracked separately if Option B is chosen.
- **NG2** Changing the Supabase custom-domain (`api.soleur.ai`) to a vanity host or moving auth to a separate subdomain. Custom-domain configuration is in Supabase, not the codebase.
- **NG3** Refactoring the 24 test files to use a less placeholder-shaped string. Tracked as a follow-up if review agents flag it.
- **NG4** Auditing Doppler `prd` for OTHER `NEXT_PUBLIC_*` keys with similar drift. The bug class is general (Doppler vs GitHub secrets divergence on any `NEXT_PUBLIC_*`), but the fix scope here is `NEXT_PUBLIC_SUPABASE_URL` + the structural guardrail. The CI Validate step in Phase 4 step 2 covers ONLY this key in v1; broaden to all `NEXT_PUBLIC_*` keys in a follow-up.

## Alternative Approaches Considered

| Approach | Pros | Cons | Decision |
|---|---|---|---|
| **A1: Just fix the secret, no guardrails** | Fastest to ship | Same operator-error class can recur tomorrow | Reject. Per `wg-when-a-workflow-gap-causes-a-mistake-fix`: gap must be fixed in skill/CI, not just the symptom. |
| **A2: Migrate to Doppler-only build-args (Option B)** | Single source of truth, eliminates divergence | Requires `DOPPLER_TOKEN_PRD` wiring in CI, broader test surface, slower to ship for a P1 | Defer to follow-up tracking issue. |
| **A3: Move OAuth redirect to server-side route handler (so build-time `NEXT_PUBLIC_*` is not load-bearing)** | Eliminates build-time inlining risk for OAuth specifically | Architectural change, breaks Supabase JS client conventions, significant refactor | Reject. Out of scope. |
| **A4: Adopt as-is (current plan: fix secret + Validate step + runtime guard + bundle probe)** | Minimal blast radius, multi-layer defense, ships in one PR | Two sources of truth remain (mitigated by CI check) | **Accept.** |

## Domain Review

**Domains relevant:** Engineering, Operations.

This is a P1 production bug-fix with infrastructure/CI implications and no user-facing UI surface change. No new pages, components, or flows. No marketing, content, expense, or design surface.

### Engineering

**Status:** reviewed (planner self-assessment; deepen-plan will spawn architecture-strategist + code-simplicity-reviewer).
**Assessment:** Minimal client-side runtime guard plus CI-time pre-build assertion. Layered defenses with no architecture changes. Risk of test-suite breakage controlled by `NODE_ENV` gating.

### Operations

**Status:** reviewed (self-assessment).
**Assessment:** One destructive prod write (`gh secret set`), gated by `hr-menu-option-ack-not-prod-write-auth`. Release workflow re-run is standard ops. Post-deploy bundle probe is a black-box smoke test consistent with `wg-when-a-feature-creates-external`.

### Product/UX Gate

**Tier:** none (no new pages, no new components — this is a bug fix that restores existing OAuth UI, not changes it).
**Decision:** N/A.
**Agents invoked:** none.
**Skipped specialists:** none.
**Pencil available:** N/A.

## CLI Verification (per `cq-docs-cli-verification`)

Every CLI invocation in this plan was verified during research:

- `doppler secrets get NEXT_PUBLIC_SUPABASE_URL -p soleur -c prd --plain` — verified (returned `https://api.soleur.ai`).
- `doppler secrets get NEXT_PUBLIC_SUPABASE_URL -p soleur -c dev --plain` — verified (returned `https://mlwiodleouzwniehynfz.supabase.co`).
- `gh secret list --json name,updatedAt` — `gh secret list --help` documents `--json` (verified locally).
- `gh secret set <NAME> --body -` — `gh secret set --help` documents `--body` and stdin-via-`-` (verified).
- `gh workflow run <file> -f <key>=<val>` — `gh workflow run --help` documents `-f` (verified).
- `gh run list --workflow=<file> --json …` — verified.
- `dig +short CNAME <host>` — standard, verified.
- `curl -sL -A "Mozilla/5.0" <url>` — standard.
- `printf '%s' '<value>' | gh secret set <NAME> --body -` — verified pattern (avoids trailing newline that `echo` adds).

## Resume Prompt (mandatory per `cm-when-proposing-to-clear-context-or`)

```text
/soleur:work knowledge-base/project/plans/2026-04-28-fix-oauth-supabase-url-prod-plan.md
Branch: feat-one-shot-fix-oauth-supabase-url. Worktree: .worktrees/feat-one-shot-fix-oauth-supabase-url/. Issue: file at session start. PR: TBD. Plan reviewed by deepen-plan; implementation pending operator ack on Phase 2 prod write.
```
