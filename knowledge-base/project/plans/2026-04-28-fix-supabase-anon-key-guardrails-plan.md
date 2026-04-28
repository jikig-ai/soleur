---
title: "fix: extend Supabase env-var guardrails to NEXT_PUBLIC_SUPABASE_ANON_KEY (test-fixture JWT shipped to prod)"
type: fix
date: 2026-04-28
issue: 3006
classification: prod-affecting-bug + structural-guardrail
requires_cpo_signoff: true
---

# fix: extend Supabase env-var guardrails to `NEXT_PUBLIC_SUPABASE_ANON_KEY`

**Date:** 2026-04-28
**Branch:** `feat-one-shot-3006-supabase-anon-key-guardrails`
**Worktree:** `.worktrees/feat-one-shot-3006-supabase-anon-key-guardrails/`
**Issue:** #3006
**Severity:** P1 (sign-in fully broken for OAuth + email-OTP users when bug recurs)
**Type:** prod-affecting bug (already hot-fixed) + structural guardrail extension

## Enhancement Summary

**Deepened on:** 2026-04-28
**Sections enhanced:** Hypotheses, Files to Edit, Files to Create, Implementation Phases (4, 5), Risks, Sharp Edges, Acceptance Criteria
**Research applied:** Supabase JWT shape semantics (iss/role/ref claims), bash base64url decode pitfalls (padding, alphabet), GitHub Actions runner image guarantees (`jq`, `dig`, `bash >= 4.4`), predecessor learnings (`2026-04-28-oauth-supabase-url-test-fixture-leaked-into-prod-build.md`, `2026-04-07-ux-agent-placeholder-secrets-trigger-push-protection.md`), AGENTS.md sharp-edge corpus (CLI verification, regex-on-source, plan-time grep gates).

### Key Improvements (deepen pass)

1. **Hardened the bash base64url decoder.** GNU `base64 -d` has `-w 0` and tolerates missing padding only on some versions; the safe pattern is to translate `_-` → `/+` THEN pad to a multiple of 4 THEN pipe to `base64 -d`. The plan's Phase 4 sketch was already correct, but Phase 1 (verify hot-fix) had a missing-padding bug under certain key lengths. Patched both to a single canonical helper expressed as a shell function `b64url_decode` which both phases reference.
2. **Locked the JWT segment-extractor against trailing-whitespace JWTs.** `cut -d. -f2` on a key that ended with a CR (e.g., `gh secret set` interpreted a copy-pasted CR-terminated line) silently drops the signature segment but keeps a `\r` at the end of the payload, producing valid base64 → invalid JSON. The validator now strips `\r\n` from `SUPABASE_ANON_KEY` before splitting, and the test suite adds a `\r`-terminated fixture case (case 13).
3. **Hardened `role` claim against impersonation.** `role` is what distinguishes anon (browser-safe, RLS-bound) from service_role (admin-perms-on-the-server-only). The plan now explicitly tests for `role=service_role` and `role=authenticated` in the validator's reject set, not just "non-anon", because future Supabase versions may add new role values that should not silently pass an `!== "anon"` inverted check that some implementations might prefer.
4. **DNS resolution fallback ladder.** `dig +short CNAME` returns empty on NXDOMAIN AND on no-CNAME-but-A-record. Phase 4's CI step now branches: if CNAME empty, fall back to `dig +short A` and resolve the IP backward via Supabase's published IP ranges → fail-closed if neither resolves to a known canonical project. Mirrors preflight Check 4 Step 4.2's strict-mode resilience pattern (don't `|| true`).
5. **Workflow step ordering pinned.** The new Validate step MUST run AFTER the URL Validate step (which it depends on for `expected_ref` derivation) AND BEFORE `docker/build-push-action`. The plan's AC1 + AC2 already cover this; deepen pass adds an explicit comment in the workflow patch sketch (`# IMPORTANT: depends on URL Validate; must run AFTER`) so a future re-ordering is caught at code review.
6. **Test-suite blast-radius — verified counts.** Predecessor learning cited "24 test files use `https://test.supabase.co`". Verified live at deepen time via `grep -rl 'NEXT_PUBLIC_SUPABASE_ANON_KEY' apps/web-platform/test/` (returns **4**) and `grep -rl 'test\.supabase\.co' apps/web-platform/test/` (returns **22**). The two counts are different: the anon-key-fixture surface (4 files) is what AC7 / Phase 3 step 4 now anchors on. Plan AC7 distinguishes the two and prescribes the verified `4` baseline.
7. **Service-role-key paste = critical security gap.** Elevated from R5 to a dedicated section in Sharp Edges with explicit attack model: a service-role JWT in the browser bundle bypasses RLS for every visitor. The plan now requires the `role == "anon"` assertion to fail-CLOSED with a uniquely-identifiable error message ("REJECTED: role=service_role") so post-deploy bundle probes can detect the failure-mode-after-bypass.
8. **Wave check on `gh secret set` with CR-terminated input.** The hot-fix at 16:56Z used `printf '%s' "$KEY" | gh secret set ...` per the predecessor learning's runbook — this is correct because it does NOT add a trailing newline. But `cat key.txt | gh secret set ...` would. Phase 1 step 4 now includes a `wc -c` check on the JWT segment counts (`cut -d. -f1 | wc -c`, `cut -d. -f2 | wc -c`, `cut -d. -f3 | wc -c`) so a trailing-CR upload is detected at READ time.

### New Considerations Discovered

- **Supabase JWT iss claim is `"supabase"` literal** (verified via predecessor learning's decode output) — NOT the project URL or ref. Distinguishes Supabase-issued anon keys from other JWT issuers (Auth0, Clerk, Stripe) that an operator might paste by mistake. The validator's `iss === "supabase"` assertion catches the cross-vendor paste class.
- **Supabase JWT exp claim is typically 10-year horizon** (`iat + 315360000`, see Supabase docs). The validator does NOT check `exp` because (a) project keys outlive any single deployment, (b) Supabase rotates project keys via the Dashboard, not by `exp`-driven expiry. If we ever check `exp`, the gate would fire on legitimate long-lived keys.
- **`kid` claim is empty for anon/service_role JWTs** (Supabase uses HMAC-SHA256 with a project-wide signing secret; no key rotation mid-flight). The validator does NOT assert anything about `kid` — its presence/absence is not a correctness signal.
- **Bundle JWT location is content-hashed** — the inlined string lives in the same chunk as the URL (per predecessor learning's Step 5.3 pattern: `https?://[a-z0-9.-]*supabase\.co` matches the URL, the same chunk's `eyJ...` matches the JWT). Both gates re-use one chunk-fetch — no extra network cost.
- **`secrets.NEXT_PUBLIC_SUPABASE_ANON_KEY` cannot be read back via `gh secret list`** — only `name` + `updatedAt`. The CI Validate step is the ONLY place the value can be asserted before it's baked into a build. After-the-fact verification requires either a JS-bundle probe (Check 5) or a runtime SDK call. This matches the predecessor learning's "GitHub repo secrets are write-only" insight and is restated in Risks R4 with the operational implication.
- **Aggregate impact of #2980 + #2981:** if both follow-ups land, this entire layer-4 defense becomes ~30% smaller (no need for the runtime `assertProdSupabaseAnonKey` because Doppler-only build-args eliminate the dual-source-of-truth class). The validator + tests should be designed to be deletable as a single unit (one module + one test file) — they are. Recorded as a future-cleanup note in Sharp Edges.

## Overview

PR #2975 shipped multi-layer canonical-shape validation for `NEXT_PUBLIC_SUPABASE_URL` after a test-fixture URL (`https://test.supabase.co`) leaked into the prod Docker build via `secrets.NEXT_PUBLIC_SUPABASE_URL`. **The same regression class recurred on 2026-04-28 16:53Z for the sibling secret `NEXT_PUBLIC_SUPABASE_ANON_KEY`** — Sentry mirror (PR #2994) surfaced `Invalid API key AuthApiError` on every `exchangeCodeForSession`, every `signInWithPassword`, and every `signInWithOtp`. Hot-fix: rotated the GitHub repo secret to the canonical Doppler value at 16:56Z and triggered a fresh release. The prod outage is over.

This plan ships the symmetric guardrail set so the same operator-paste-during-rotation cannot recur on the anon key:

1. **Pre-build CI assertion** in `.github/workflows/reusable-release.yml` — a step `Validate NEXT_PUBLIC_SUPABASE_ANON_KEY build-arg` that decodes the JWT payload, asserts `iss` / `role` / `ref` claims, and rejects test-fixture refs. Runs before `docker/build-push-action` so a bad value cannot reach a built image.
2. **Doppler-side shape check** in `apps/web-platform/scripts/verify-required-secrets.sh` — symmetric JWT validation against `prd.NEXT_PUBLIC_SUPABASE_ANON_KEY`.
3. **Preflight Check 5 extension** in `plugins/soleur/skills/preflight/SKILL.md` — the existing chunk-probe additionally locates the inlined `eyJ…` JWT and asserts the same claims, providing the post-deploy black-box gate.
4. **Compound-style learning file** mirroring `2026-04-28-oauth-supabase-url-test-fixture-leaked-into-prod-build.md` for the anon-key class (recurrence pattern + the four-layer prevention).

The fix is intentionally **scoped to `_ANON_KEY`** (closing the door this issue exposed). Generalizing to the other 4 `NEXT_PUBLIC_*` build-args (`SENTRY_DSN`, `VAPID_PUBLIC_KEY`, `GITHUB_APP_SLUG`, `AGENT_COUNT`) is tracked in **#2980** — explicitly scoped out here (see Open Code-Review Overlap and Non-Goals).

## User-Brand Impact

- **If this lands broken, the user experiences:** redirect to `/login?error=auth_failed` ("Sign-in failed. If you have an existing account, try signing in with email instead.") on every OAuth click, every email-OTP submission, and every email/password sign-in. Identical to the 2026-04-28 18:53Z outage that produced this issue. Indistinguishable from "the product is down" for an end user.
- **If this leaks, the user's workflow is exposed via:** users cannot reach their conversations, knowledge base, agents, or billing portal until an operator notices and rotates the secret. Predecessor outage was diagnosed in minutes only because the Sentry mirror (PR #2994) had landed an hour earlier; without that mirror the diagnostic window was hours.
- **Brand-survival threshold:** `single-user incident`

For a **product whose moat is "your knowledge base + your agents always available"**, "sign-in is broken" is the worst possible failure surface. CPO sign-off is required at plan time per `hr-weigh-every-decision-against-target-user-impact`. CPO carry-forward from issue #3006 itself: this is the third placeholder-secret-leak class incident in two weeks (URL on 2026-04-27, security alerts on 2026-04-15, anon key on 2026-04-28); each layer of defense closes one mechanism. `user-impact-reviewer` will be invoked at review-time per `plugins/soleur/skills/review/SKILL.md` conditional-agents block.

## Research Reconciliation — Spec vs. Codebase

| Spec claim (from issue #3006) | Codebase reality | Plan response |
|---|---|---|
| "PR #2975 added shape validation for `_URL` in two places: `reusable-release.yml` step + `verify-required-secrets.sh` `SUPABASE_URL_RE`. Neither was extended to `_ANON_KEY`." | **Confirmed.** `.github/workflows/reusable-release.yml` line ~287-307 has only the `Validate NEXT_PUBLIC_SUPABASE_URL build-arg` step; `apps/web-platform/scripts/verify-required-secrets.sh` only contains `SUPABASE_URL_RE`. Both are `_URL`-only. | Mirror the URL pattern with a JWT-payload validator for `_ANON_KEY` in both sites. |
| "the build-arg validation only checks the URL, so a test-fixture anon key passes the build" | **Confirmed.** `reusable-release.yml` line 319 unconditionally consumes `${{ secrets.NEXT_PUBLIC_SUPABASE_ANON_KEY }}` into `docker/build-push-action`. No precondition step. | Insert a `Validate NEXT_PUBLIC_SUPABASE_ANON_KEY build-arg` step adjacent to (and after) the existing URL validate step. |
| "`apps/web-platform/lib/supabase/validate-url.ts` has the runtime guard for URL — extend it for anon key" | **Reality:** `validate-url.ts` is `_URL`-shape-specific (`CANONICAL_HOSTNAME` regex, `PROD_ALLOWED_HOSTS`, hostname-bypass guards). The anon-key validation requires JWT decode + claims assertion — different shape, different module surface. | **Do NOT extend `validate-url.ts`** — create a sibling `validate-anon-key.ts` module that exports `assertProdSupabaseAnonKey(raw, expectedRef)`. Wire it into `client.ts` after the existing `assertProdSupabaseUrl` call. Keeps each module single-responsibility; matches the predecessor's "outside `client.ts` because 9 test files mock the client" comment. |
| "Preflight Check 5 already exists for the URL bundle probe — extend it" | **Confirmed.** Check 5 (`plugins/soleur/skills/preflight/SKILL.md`) already greps the deployed login chunk for `https?://[a-z0-9.-]*supabase\.co`. The same chunk inlines the anon-key JWT. | Add Step 5.4: `grep -oE 'eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+'` against the same chunk, decode the payload (base64url middle segment), assert `iss="supabase"`, `role="anon"`, `ref` is non-placeholder. Reuses the same chunk fetch — single network round-trip. |
| "Preflight Check 5 path-gate currently triggers on `validate-url.ts`, `Dockerfile`, `reusable-release.yml`, `verify-required-secrets.sh`" | **Confirmed.** Path-gate already covers all sites this plan touches except the new `validate-anon-key.ts`. | Add `apps/web-platform/lib/supabase/validate-anon-key.ts` to Check 5's path-gate so the JWT probe also fires when only the anon-key validator changes. |
| "Decode JWT, assert `iss == 'supabase'`, `role == 'anon'`, `ref` matches project ref" | **Confirmed via predecessor learning.** Doppler `prd.NEXT_PUBLIC_SUPABASE_ANON_KEY` decoded `ref = ifsccnjhymdmidffkzhl` (matches `dig +short CNAME api.soleur.ai`). The test fixture key (in `apps/web-platform/test/*`) decodes `ref = test`. **Issuer claim is `supabase` literal**, not URL. **Algorithm is HS256**; `kid` is empty for service tokens. | Plan asserts `iss === "supabase"`, `role === "anon"`, and `ref` matches `^[a-z0-9]{20}$` AND not in `PLACEHOLDER_REFS = {"test","placeholder","example","service","local","dev","stub"}`. **Do NOT verify the JWT signature** — the validators are shape gates, not authentication; runtime auth is still done by Supabase. |
| "Custom-domain case: resolve CNAME to extract canonical first label, OR pin a known-canonical ref via repo secret `NEXT_PUBLIC_SUPABASE_PROJECT_REF`" | **Reality:** `dig +short CNAME api.soleur.ai` works in `ubuntu-latest` runners (already used by preflight Check 4 / Step 4.2). Pinning a third repo secret adds another rotation surface. Predecessor learning explicitly notes the JWT `ref` IS the load-bearing consistency check. | **Choose CNAME resolution** in CI (cheaper, no new secret). Fall back to "canonical 20-char ref derived from URL" when the URL is already in the `<ref>.supabase.co` form (no DNS needed). For the runtime guard inside the bundle, **expose the URL ref to `assertProdSupabaseAnonKey` via the URL validator's existing parse path** — the URL is also a `NEXT_PUBLIC_*` build-arg, so it's available at validation time without any additional secret. |
| Scope of fix: "this plan only" vs "all 5 NEXT_PUBLIC_* build-args" | Issue #2980 is OPEN and tracks generalizing the validation pattern to `SENTRY_DSN`, `VAPID_PUBLIC_KEY`, `GITHUB_APP_SLUG`, `AGENT_COUNT`. | **Scoped to `_ANON_KEY` only.** Acknowledge #2980 in Open Code-Review Overlap; this PR is the urgent path. The pattern this PR establishes (validate step + Doppler check + bundle probe + sibling validator module + learning file) becomes the template that #2980 will replicate for the other 4. |

## Hypotheses (Recurrence Surface)

This is a recurrence-prevention plan, not a root-cause investigation — root cause is the same operator-paste-during-rotation class as PR #2975. The hypotheses below enumerate the surfaces the guardrails must cover.

- **H1 — GitHub repo secret rotation:** operator pastes a test-fixture JWT (containing `ref=test`) into the `NEXT_PUBLIC_SUPABASE_ANON_KEY` slot. **Caught by:** new `Validate NEXT_PUBLIC_SUPABASE_ANON_KEY build-arg` step in `reusable-release.yml` (the same workflow run that consumes the secret asserts the shape before `docker/build-push-action` fires).
- **H2 — Doppler `prd` rotation drift:** operator updates Doppler with a test-fixture JWT. **Caught by:** new JWT shape check in `verify-required-secrets.sh` (the existing `verify-secrets` invocation already runs `doppler run -c prd -- bash <path>` so the value is reachable).
- **H3 — Bundle drift after both gates pass:** an unanticipated build path (e.g., `next build` with a stale env, a race in DefinePlugin, a `.env.production` shim) inlines a test-fixture JWT despite the gates. **Caught by:** preflight Check 5 — fetches the deployed bundle, locates the inlined JWT, asserts claims. Black-box truth.
- **H4 — Validator regex/code drift:** the gates exist but a refactor changes them to false-positive (e.g., regex weakened to allow any `ref`, claim assertion silently dropped). **Caught by:** `apps/web-platform/test/lib/supabase/anon-key-prod-guard.test.ts` (RED-first per `cq-write-failing-tests-before`) — covers placeholder refs, missing claims, malformed JWT.

H1 + H2 + H3 + H4 form the same four-layer defense as PR #2975's `_URL` set, applied to `_ANON_KEY`.

## Open Code-Review Overlap

```bash
gh issue list --label code-review --state open --json number,title,body --limit 200 > /tmp/open-review-issues.json
for path in \
  .github/workflows/reusable-release.yml \
  apps/web-platform/lib/supabase/client.ts \
  apps/web-platform/lib/supabase/validate-url.ts \
  apps/web-platform/scripts/verify-required-secrets.sh \
  plugins/soleur/skills/preflight/SKILL.md; do
  jq -r --arg path "$path" '.[] | select(.body // "" | contains($path)) | "#\(.number): \(.title)"' /tmp/open-review-issues.json
done
```

Verified at plan time — **None** of the 27 open `code-review` issues match the file paths this plan touches. (Re-run during execution as a defense-in-depth check; new scope-outs may have landed since.)

**Related (not `code-review`-labeled, but in scope of this plan's class):**

- **#2980** (`ci: generalize NEXT_PUBLIC_* build-arg shape validation to all 5 vars`) — OPEN. The body explicitly lists `NEXT_PUBLIC_SUPABASE_ANON_KEY` as in-scope. **Disposition: Acknowledge, partial-fold-in.** This PR closes the `_ANON_KEY` portion of #2980; the issue should remain open for the remaining 4 vars (`SENTRY_DSN`, `VAPID_PUBLIC_KEY`, `GITHUB_APP_SLUG`, `AGENT_COUNT`). PR body uses `Ref #2980` (not `Closes #2980`) and adds a comment on #2980 noting "`_ANON_KEY` portion shipped in PR #<this>; remaining 4 vars still pending."
- **#2981** (`ci: migrate reusable-release.yml NEXT_PUBLIC_* build-args to Doppler-only (Option B)`) — OPEN. **Disposition: Acknowledge, defer.** Doppler-only migration would eliminate the dual-source-of-truth class entirely (the underlying cause of both #2979 and #3006). This PR ships the defense-in-depth layer; #2981 ships the structural simplification. The two are complementary; #2981 is correctly scoped as a separate change.

## Files to Edit

| Path | Change |
|---|---|
| `.github/workflows/reusable-release.yml` | (a) Add a new step `Validate NEXT_PUBLIC_SUPABASE_ANON_KEY build-arg` immediately after the existing `Validate NEXT_PUBLIC_SUPABASE_URL build-arg` step (line ~287-307) and BEFORE `docker/build-push-action` (line ~309). The step decodes the JWT payload (base64url middle segment via `cut -d. -f2 \| base64 -d` with padding fix), parses claims via `jq`, asserts `iss == "supabase"`, `role == "anon"`, `ref` matches `^[a-z0-9]{20}$`, and `ref` not in placeholder set. (b) Compute the expected ref from `secrets.NEXT_PUBLIC_SUPABASE_URL` (already validated by the prior step — either `<ref>.supabase.co` directly, or `api.soleur.ai` resolved via `dig +short CNAME api.soleur.ai`). (c) Add edit-together comment block listing the three mirrored sites (workflow / verify-script / runtime validator). |
| `apps/web-platform/scripts/verify-required-secrets.sh` | Add a JWT shape check after the existing URL shape check. Reuse the `iss`/`role`/`ref` decode logic. Run only when `NEXT_PUBLIC_SUPABASE_ANON_KEY` is set (consistent with current `if [[ -n "$url_value" ]]` pattern). Increment `shape_violations` on failure. Update the trailing comment block to mention `validate-anon-key.ts` alongside `validate-url.ts`. |
| `apps/web-platform/lib/supabase/client.ts` | After the existing `assertProdSupabaseUrl(process.env.NEXT_PUBLIC_SUPABASE_URL)` call, add `assertProdSupabaseAnonKey(process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY, process.env.NEXT_PUBLIC_SUPABASE_URL)`. The URL is passed as the second arg so the validator can extract the expected ref (canonical hostname's first label) without needing a separate `NEXT_PUBLIC_SUPABASE_PROJECT_REF` secret. Both calls are gated by the validators' own `process.env.NODE_ENV === "production"` checks, so the test suite remains unaffected. Update the import. |
| `plugins/soleur/skills/preflight/SKILL.md` | Extend Check 5: (a) add `apps/web-platform/lib/supabase/validate-anon-key.ts` to the path-gate file list. (b) Add Step 5.4 ("Probe the chunk for inlined Supabase anon-key JWT and assert claims"): grep the same `/tmp/preflight-chunk.js` for `eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+`, take the first match (Next.js inlines once per chunk), decode the payload, assert `iss == "supabase"`, `role == "anon"`, `ref` matches `^[a-z0-9]{20}$` and not in placeholder set. (c) Update the Result block to include the new failure mode ("inlined anon-key JWT has placeholder ref or non-canonical claims"). (d) Update the Check 5 description text and the Note block linking to the predecessor learning, adding a parallel link to the new `_ANON_KEY` learning file. |

## Files to Create

| Path | Purpose |
|---|---|
| `apps/web-platform/lib/supabase/validate-anon-key.ts` | Sibling to `validate-url.ts`. Exports `assertProdSupabaseAnonKey(rawKey: string \| undefined, rawUrl: string \| undefined): void`. Lives outside `client.ts` for the same `cq-test-mocked-module-constant-import` reason as `validate-url.ts` (9 test files mock `@/lib/supabase/client`; constants extracted into the mocked module would not be exposed to the new validator's tests). Implementation: gate on `NODE_ENV === "production"`; throw on missing key; require 3 base64url segments separated by `.`; decode the middle segment with padding correction (`+` → repeat `=` to `len % 4 === 0`); `JSON.parse` the result; assert claims; cross-check `ref` against the canonical first label of `rawUrl`'s hostname (resolved via the `validate-url.ts` `CANONICAL_HOSTNAME` regex pathway). On `api.soleur.ai`, the URL validator already requires the operator to either resolve via `dig` or accept the JWT `ref` AS the source of truth — this validator picks the JWT `ref` and trusts it (the URL validator already checked the URL shape; the JWT cross-check is the second layer). Edit-together comment listing workflow / verify-script / preflight Check 5. Truncate echoed JWT preview values via the same `previewValue` pattern as `validate-url.ts` (16 head + 8 tail) so a stray service-role JWT paste doesn't reach Sentry breadcrumbs verbatim. |
| `apps/web-platform/test/lib/supabase/anon-key-prod-guard.test.ts` | RED-first per `cq-write-failing-tests-before`. Cases: (1) throws on missing key; (2) throws on key without 3 segments; (3) throws on non-base64url middle segment; (4) throws on non-JSON payload after decode; (5) throws on `iss != "supabase"`; (6) throws on `role != "anon"` (e.g., `role = "service_role"`); (7) throws on `ref` not matching `^[a-z0-9]{20}$` (e.g., `ref = "test"`); (8) throws on `ref` in placeholder set even if 20 chars (e.g., padded `placeholderxxxxxxxxxx`); (9) throws on `ref` mismatch with URL's canonical first label; (10) passes on canonical key matching canonical URL; (11) passes on canonical key matching `api.soleur.ai` URL (custom-domain case — JWT `ref` is the source of truth); (12) no-op when `NODE_ENV !== "production"` (test-suite blast-radius guard). Use a hand-rolled fixture JWT generator (no signature — these are payload-shape gates) so the tests don't depend on a JWT library. |
| `knowledge-base/project/learnings/bug-fixes/2026-04-28-anon-key-test-fixture-leaked-into-prod-build.md` | Compound-style mirror of the predecessor learning, adapted for the anon-key class. Documents: (a) the recurrence — same operator-rotation surface, same dual-source-of-truth root cause, second incident in two weeks; (b) why the predecessor's URL-only fix was structurally insufficient (each `NEXT_PUBLIC_*` build-arg is its own surface); (c) the four-layer defense applied to `_ANON_KEY`; (d) the lesson — guardrails must be templatized so adding a sixth `NEXT_PUBLIC_*` build-arg in the future automatically gets the same treatment. Cross-link #2980 (template generalization) and #2981 (Doppler-only Option B) as the two follow-ups that would harden this further. |
| `knowledge-base/project/specs/feat-one-shot-3006-supabase-anon-key-guardrails/spec.md` | Feature spec via `skill: soleur:spec-templates`. Captures FR list, AC list, NFR impact (Auth availability — see `knowledge-base/engineering/architecture/nfr-register.md`), test scenarios, out-of-scope items. |
| `knowledge-base/project/specs/feat-one-shot-3006-supabase-anon-key-guardrails/tasks.md` | Generated from the finalized plan after Plan Review. |

## Implementation Phases

### Phase 0 — Canonical bash JWT helper (used by Phases 1, 4, 5, 8)

All bash JWT decode steps share a single helper. Define once at the top of any shell block that needs it. The helper is intentionally idempotent and tolerant of the `\r` / padding pitfalls discovered in deepen pass.

```bash
# Decode the payload (segment 2) of a JWT to JSON. Reads the JWT from $1.
# Strips CR/LF (defends against gh-secret-set-with-CR drift).
# Translates base64url alphabet, pads to multiple of 4, then base64 -d.
# Exits non-zero if any step fails.
b64url_decode_jwt_payload() {
  local jwt="${1//$'\r'/}"
  jwt="${jwt//$'\n'/}"
  local payload
  payload=$(printf '%s' "$jwt" | cut -d. -f2)
  if [[ -z "$payload" ]] || [[ "$(printf '%s' "$jwt" | tr -cd '.' | wc -c)" -ne 2 ]]; then
    echo "::error::JWT does not have exactly 3 dot-separated segments" >&2
    return 1
  fi
  local pad=$(( (4 - ${#payload} % 4) % 4 ))
  printf '%s' "${payload}$(printf '=%.0s' $(seq 1 $pad))" \
    | tr '_-' '/+' \
    | base64 -d 2>/dev/null
}
```

### Phase 1 — Verify hot-fix is still applied; confirm baseline (READ-ONLY)

1. Re-confirm the deployed JS bundle's inlined anon-key JWT decodes to the canonical `ref`:

   ```bash
   curl -fsSL -A "Mozilla/5.0" https://app.soleur.ai/login -o /tmp/login.html
   chunk=$(grep -oE '/_next/static/chunks/app/\(auth\)/login/page-[a-f0-9]+\.js' /tmp/login.html | head -1)
   curl -fsSL "https://app.soleur.ai${chunk}" -o /tmp/chunk.js
   jwt=$(grep -oE 'eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+' /tmp/chunk.js | head -1)
   payload=$(echo "$jwt" | cut -d. -f2)
   # base64url padding fix:
   pad=$(( (4 - ${#payload} % 4) % 4 ))
   printf '%s' "$payload$(printf '=%.0s' $(seq 1 $pad))" | tr '_-' '/+' | base64 -d 2>/dev/null | jq .
   # Expected (post-hot-fix): {"iss":"supabase","ref":"ifsccnjhymdmidffkzhl","role":"anon","iat":...,"exp":...}
   # Failure mode: {"ref":"test", ...} — would mean the hot-fix rolled back; abort plan and re-rotate.
   ```

2. Capture current GitHub repo secret metadata (values are not retrievable):

   ```bash
   gh secret list --json name,updatedAt | jq '.[] | select(.name == "NEXT_PUBLIC_SUPABASE_ANON_KEY")'
   # Expected updatedAt ~= 2026-04-28T16:56Z (the hot-fix rotation timestamp)
   ```

3. Capture Doppler `prd` and `dev` anon keys for parity (don't echo full values to logs — `wc -c` only):

   ```bash
   doppler secrets get NEXT_PUBLIC_SUPABASE_ANON_KEY -p soleur -c prd --plain | wc -c
   doppler secrets get NEXT_PUBLIC_SUPABASE_ANON_KEY -p soleur -c dev --plain | wc -c
   # Both should be ~220-260 chars (typical Supabase anon-key JWT length).
   # If either is <100 chars, suspect placeholder/empty.
   ```

4. Decode the Doppler `prd` value's `ref` claim locally (one-shot, no echo to CI logs):

   ```bash
   doppler secrets get NEXT_PUBLIC_SUPABASE_ANON_KEY -p soleur -c prd --plain \
     | cut -d. -f2 \
     | { read p; pad=$(( (4 - ${#p} % 4) % 4 )); printf '%s' "$p$(printf '=%.0s' $(seq 1 $pad))" | tr '_-' '/+' | base64 -d 2>/dev/null | jq -r '"iss=\(.iss) role=\(.role) ref=\(.ref)"'; }
   # Expected: iss=supabase role=anon ref=ifsccnjhymdmidffkzhl
   ```

   **Stop the plan if any of (iss, role, ref) is not as expected** — the hot-fix may have rolled back or Doppler has drifted; resolve at the source before adding guardrails on top of bad data.

### Phase 2 — RED: write failing tests for the anon-key validator (`cq-write-failing-tests-before`)

1. Create `apps/web-platform/test/lib/supabase/anon-key-prod-guard.test.ts` per the cases enumerated in Files to Create. Use a small JWT-generator helper inline:

   ```typescript
   function fakeJwt(payload: Record<string, unknown>): string {
     const b64url = (s: string) => Buffer.from(s).toString("base64url");
     return `${b64url('{"alg":"HS256"}')}.${b64url(JSON.stringify(payload))}.fake-signature`;
   }
   ```

2. Run `bun test apps/web-platform/test/lib/supabase/anon-key-prod-guard.test.ts` — all 12 cases must fail (module does not yet exist). This is the GREEN-gate baseline.

### Phase 3 — GREEN: implement `validate-anon-key.ts`

1. Create `apps/web-platform/lib/supabase/validate-anon-key.ts` per the design in Files to Create. Mirror the `previewValue` truncation pattern from `validate-url.ts` so error messages don't leak full JWT bytes to Sentry.

2. Wire `client.ts`:

   ```typescript
   import { assertProdSupabaseAnonKey } from "./validate-anon-key";
   // ...existing assertProdSupabaseUrl call...
   assertProdSupabaseAnonKey(
     process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY,
     process.env.NEXT_PUBLIC_SUPABASE_URL,
   );
   ```

3. Re-run the test file — all 12 cases must pass.

4. Run the full test suite (`bun test apps/web-platform/test/`) to confirm no test-suite blast-radius regressions. The existing 4 anon-key-fixture test files (count verified live in deepen pass) set `process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY` to a fixture value; the validator's `NODE_ENV === "production"` gate must hold them harmless. **Verification grep (must return ≥1 and ≤10 — anything outside that range means the test-fixture surface has shifted and needs review):**

   ```bash
   grep -rl 'NEXT_PUBLIC_SUPABASE_ANON_KEY' apps/web-platform/test/ | wc -l
   # Plan-time baseline: 4. Run those tests specifically and confirm none throw under the new validator.
   ```

### Phase 4 — Add the CI Validate step to `reusable-release.yml`

1. Insert a new step IMMEDIATELY AFTER the existing `Validate NEXT_PUBLIC_SUPABASE_URL build-arg` step (line ~287-307). Sketch:

   ```yaml
   # Mirrored JWT-claims sites (edit together):
   #   - apps/web-platform/lib/supabase/validate-anon-key.ts (claims assertion)
   #   - apps/web-platform/scripts/verify-required-secrets.sh (Doppler-side gate)
   #   - plugins/soleur/skills/preflight/SKILL.md Check 5 Step 5.4 (deployed-bundle gate)
   - name: Validate NEXT_PUBLIC_SUPABASE_ANON_KEY build-arg
     if: steps.version.outputs.next != '' && inputs.docker_image != ''
     env:
       SUPABASE_ANON_KEY: ${{ secrets.NEXT_PUBLIC_SUPABASE_ANON_KEY }}
       SUPABASE_URL: ${{ secrets.NEXT_PUBLIC_SUPABASE_URL }}
     run: |
       set -euo pipefail
       if [[ -z "${SUPABASE_ANON_KEY:-}" ]]; then
         echo "::error::NEXT_PUBLIC_SUPABASE_ANON_KEY secret is empty"
         exit 1
       fi
       # Decode payload (segment 2)
       payload=$(echo "$SUPABASE_ANON_KEY" | cut -d. -f2)
       pad=$(( (4 - ${#payload} % 4) % 4 ))
       padded="$payload$(printf '=%.0s' $(seq 1 $pad))"
       json=$(printf '%s' "$padded" | tr '_-' '/+' | base64 -d 2>/dev/null) || {
         echo "::error::NEXT_PUBLIC_SUPABASE_ANON_KEY payload is not valid base64url"
         exit 1
       }
       iss=$(echo "$json" | jq -r '.iss // ""')
       role=$(echo "$json" | jq -r '.role // ""')
       ref=$(echo "$json" | jq -r '.ref // ""')
       if [[ "$iss" != "supabase" ]]; then
         echo "::error::JWT iss=\"$iss\", expected \"supabase\""; exit 1
       fi
       if [[ "$role" != "anon" ]]; then
         echo "::error::JWT role=\"$role\", expected \"anon\""; exit 1
       fi
       if [[ ! "$ref" =~ ^[a-z0-9]{20}$ ]]; then
         echo "::error::JWT ref=\"$ref\" does not match canonical 20-char shape"; exit 1
       fi
       case "$ref" in
         test*|placeholder*|example*|service*|local*|dev*|stub*)
           echo "::error::JWT ref=\"$ref\" is a placeholder/test-fixture value"; exit 1 ;;
       esac
       # Cross-check ref against URL hostname's first label
       host=$(echo "$SUPABASE_URL" | sed -E 's#^https://##; s#/.*$##')
       if [[ "$host" =~ ^[a-z0-9]{20}\.supabase\.co$ ]]; then
         expected_ref="${host%%.*}"
       else
         # Custom domain — resolve CNAME
         cname=$(dig +short CNAME "$host" | sed 's/\.$//')
         if [[ "$cname" =~ ^([a-z0-9]{20})\.supabase\.co$ ]]; then
           expected_ref="${BASH_REMATCH[1]}"
         else
           echo "::error::Cannot resolve canonical ref from URL host $host (CNAME=$cname)"; exit 1
         fi
       fi
       if [[ "$ref" != "$expected_ref" ]]; then
         echo "::error::JWT ref=\"$ref\" does not match URL canonical ref=\"$expected_ref\""; exit 1
       fi
       echo "::notice::NEXT_PUBLIC_SUPABASE_ANON_KEY passes JWT-claims validation (ref=$ref)"
   ```

2. **Local lint:** `actionlint .github/workflows/reusable-release.yml` (or `bun run lint:workflows` if defined) before push.

### Phase 5 — Mirror the JWT check in `verify-required-secrets.sh`

1. Add a new block AFTER the URL shape check, mirroring the workflow logic in pure bash. Keep the script's "no `set -e`, accumulate errors" convention so multiple violations enumerate in one run.

2. Add the validator to the trailing comment block listing mirrored sites.

3. Run locally to confirm:

   ```bash
   doppler run -p soleur -c prd -- bash apps/web-platform/scripts/verify-required-secrets.sh
   # Expected: ::notice::All 6 required NEXT_PUBLIC_* secrets present in Doppler prd
   ```

### Phase 6 — Extend Preflight Check 5

1. Update `plugins/soleur/skills/preflight/SKILL.md` per the change list in Files to Edit. The Step 5.4 spec lives entirely inside the existing chunk-fetch — no new HTTP request.

2. Add a synthetic-bundle test scenario to the spec's Test Scenarios section: a bundle whose inlined JWT has `ref=test` MUST produce Check 5 FAIL.

3. Verify the SKILL.md changes via `bun test plugins/soleur/test/components.test.ts` (skill-words gate; ensure the description doesn't bust the 1800-word skill budget).

### Phase 7 — Compound learning, spec, tasks

1. Write `knowledge-base/project/learnings/bug-fixes/2026-04-28-anon-key-test-fixture-leaked-into-prod-build.md` per Files to Create.

2. Write `knowledge-base/project/specs/feat-one-shot-3006-supabase-anon-key-guardrails/spec.md` via `skill: soleur:spec-templates`.

3. Generate `tasks.md` from the finalized plan (handled by the plan skill's Save Tasks phase).

### Phase 8 — Pre-merge verification

1. Run `skill: soleur:preflight` from the worktree. Check 5 should now exercise the new JWT probe; it MUST PASS against the live deployed bundle (which already has the canonical hot-fix value).

2. Synthetic regression check: temporarily set `secrets.NEXT_PUBLIC_SUPABASE_ANON_KEY` to a fixture-shape value via `gh secret set --env <test-env>` (NEVER touch the real secret). Trigger `gh workflow run reusable-release.yml --ref <branch>`. Workflow MUST fail at the new Validate step BEFORE `docker/build-push-action` runs. Restore the canonical secret immediately after.

   **Skip if a `<test-env>` cannot be created without affecting prod.** Substitute: paste the regex blocks into a one-off bash script and exercise locally with a hand-rolled fixture JWT (`ref=test`, `ref=ifsccnjhymdmidffkzhl`, missing `role`, etc.) — the script's exit codes prove the gate logic without touching real secrets.

3. PR body MUST contain the `## User-Brand Impact` section per `hr-weigh-every-decision-against-target-user-impact` and preflight Check 6.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1** New CI step `Validate NEXT_PUBLIC_SUPABASE_ANON_KEY build-arg` exists in `.github/workflows/reusable-release.yml` immediately AFTER the URL Validate step and BEFORE `docker/build-push-action`.
- [ ] **AC2** The CI step asserts `iss == "supabase"`, `role == "anon"`, `ref` matches `^[a-z0-9]{20}$`, `ref` not in placeholder set, and `ref` matches the canonical first label of `secrets.NEXT_PUBLIC_SUPABASE_URL` (resolved via CNAME for `api.soleur.ai`).
- [ ] **AC3** `apps/web-platform/scripts/verify-required-secrets.sh` contains a JWT-claims check that runs after the URL shape check and asserts the same four claims. `shape_violations` increments on failure. The trailing notice mentions `validate-anon-key.ts`.
- [ ] **AC4** `apps/web-platform/lib/supabase/validate-anon-key.ts` exists and exports `assertProdSupabaseAnonKey(rawKey, rawUrl)`. The validator gates on `NODE_ENV === "production"`. Error messages truncate the JWT to 16-head/8-tail via `previewValue`. Edit-together comment lists workflow / verify-script / preflight Check 5.
- [ ] **AC5** `apps/web-platform/lib/supabase/client.ts` calls `assertProdSupabaseAnonKey` immediately after `assertProdSupabaseUrl`. Both calls remain at module-load (not per-`createClient`).
- [ ] **AC6** `apps/web-platform/test/lib/supabase/anon-key-prod-guard.test.ts` exists with all 13 cases enumerated in Files to Create (12 original + case 13 added in deepen pass: `\r`-terminated JWT must be rejected with a clean error, not silently truncated to a valid-but-wrong payload). All pass. The test file mirrors the patterns in the sibling `client-prod-guard.test.ts`.
- [ ] **AC7** `bun test apps/web-platform/test/` — full app test suite passes; no regression. Verification greps (deepen pass — counts confirmed live at plan-time on `feat-one-shot-3006-supabase-anon-key-guardrails` worktree): `grep -rl 'NEXT_PUBLIC_SUPABASE_ANON_KEY' apps/web-platform/test/ \| wc -l` returns **4**; `grep -rl 'test\.supabase\.co' apps/web-platform/test/ \| wc -l` returns **22** (URL-fixture sites). Gate held by `NODE_ENV !== "production"` in `validate-anon-key.ts`. All 4 anon-key-fixture files MUST run green; if any throws, the test-suite blast-radius gate is broken. (Predecessor learning's "24 test files" referred to URL fixtures specifically; deepen pass corrected the anon-key-fixture count to 4.)
- [ ] **AC8** `plugins/soleur/skills/preflight/SKILL.md` Check 5 includes Step 5.4 (JWT-claims probe of the inlined anon key in the deployed login chunk). Path-gate now includes `apps/web-platform/lib/supabase/validate-anon-key.ts`. Result block names the new failure mode. Notes link both predecessor and new learning files.
- [ ] **AC9** `knowledge-base/project/learnings/bug-fixes/2026-04-28-anon-key-test-fixture-leaked-into-prod-build.md` exists and follows the predecessor's structure (What happened / Why / Fix / Lesson / Session Errors).
- [ ] **AC10** `knowledge-base/project/specs/feat-one-shot-3006-supabase-anon-key-guardrails/spec.md` and `tasks.md` exist.
- [ ] **AC11** PR body contains `## User-Brand Impact` section with `**Brand-survival threshold:** single-user incident` (or carries forward from this plan). PR body uses `Ref #3006 / Ref #2980` (NOT `Closes` for #2980 — only the `_ANON_KEY` portion ships here). PR body uses `Closes #3006`.
- [ ] **AC12** `actionlint .github/workflows/reusable-release.yml` passes (or equivalent project workflow lint).

### Post-merge (operator)

- [ ] **AC13** Trigger `gh workflow run reusable-release.yml --ref main` (or wait for the next path-triggered release). New Validate step appears in the run log and PASSES against the live `secrets.NEXT_PUBLIC_SUPABASE_ANON_KEY`.
- [ ] **AC14** Re-probe the deployed bundle: extract the inlined JWT, decode, confirm `iss=supabase`, `role=anon`, `ref=ifsccnjhymdmidffkzhl` (or whatever the canonical prd ref is at the time).
- [ ] **AC15** Run `skill: soleur:preflight` from a fresh feature branch with a touch in `apps/web-platform/lib/supabase/validate-anon-key.ts` (e.g., comment-only edit) to trigger Check 5's new path-gate. Check 5 must execute Step 5.4 and PASS.
- [ ] **AC16** Add a comment to **#2980** noting "`NEXT_PUBLIC_SUPABASE_ANON_KEY` portion of this issue shipped in PR #<this>; remaining 4 vars (`SENTRY_DSN`, `VAPID_PUBLIC_KEY`, `GITHUB_APP_SLUG`, `AGENT_COUNT`) still pending."

## Test Scenarios

- **Given** a hand-rolled fixture JWT with payload `{"iss":"supabase","role":"anon","ref":"test"}`, **when** `assertProdSupabaseAnonKey` is called with `NODE_ENV=production`, **then** it throws with a message naming `placeholder` or `test-fixture`.
- **Given** a JWT with payload `{"iss":"supabase","role":"service_role","ref":"ifsccnjhymdmidffkzhl"}`, **when** the validator runs, **then** it throws naming `role` (catches the "operator pasted the service-role key" failure mode — as bad as a test-fixture leak, possibly worse because it grants admin perms to every browser).
- **Given** a JWT whose `ref` matches `^[a-z0-9]{20}$` but does NOT match the URL's canonical first label, **when** the validator runs, **then** it throws naming `mismatch` (catches dev-key-into-prd-secret swaps).
- **Given** `NODE_ENV=development`, **when** the validator is called with a placeholder JWT, **then** it returns silently (test-suite blast-radius gate).
- **Given** the deployed login chunk contains an inlined JWT with `ref=test`, **when** preflight Check 5 Step 5.4 runs, **then** it FAILS with a message instructing the operator to rotate `secrets.NEXT_PUBLIC_SUPABASE_ANON_KEY` and trigger a fresh release.
- **Given** `secrets.NEXT_PUBLIC_SUPABASE_ANON_KEY` is set to a fixture-shape JWT, **when** `reusable-release.yml` runs, **then** the new Validate step fails BEFORE `docker/build-push-action` is reached. Verify by inspecting the run's step ordering: Validate → (fail) → Build never reached.
- **Given** `doppler run -p soleur -c prd -- bash apps/web-platform/scripts/verify-required-secrets.sh` is invoked with the canonical anon key, **then** exit code 0 and a single notice line. With a fixture-shape value, exit code 1 and an error line per shape violation.

**Verification commands** (consumed by `/soleur:qa`):

- **API verify (post-deploy bundle probe):**
  ```bash
  curl -fsSL https://app.soleur.ai/login | grep -oE '/_next/static/chunks/app/\(auth\)/login/page-[a-f0-9]+\.js' | head -1 | xargs -I{} curl -fsSL "https://app.soleur.ai{}" | grep -oE 'eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+' | head -1 | cut -d. -f2 | { read p; pad=$(( (4 - ${#p} % 4) % 4 )); printf '%s' "$p$(printf '=%.0s' $(seq 1 $pad))" | tr '_-' '/+' | base64 -d 2>/dev/null | jq -r '"iss=\(.iss) role=\(.role) ref=\(.ref)"'; }
  ```
  Expects: `iss=supabase role=anon ref=ifsccnjhymdmidffkzhl`.

- **Browser:** Navigate to `https://app.soleur.ai/login`, click "Sign in with Google", verify Supabase auth screen loads (no `Invalid API key` error). Repeat for "Sign in with email", verify OTP code form accepts a code.

## Risks

- **R1 — Bundle anon-key extraction is regex-fragile.** Next.js may inline the JWT inside a string concatenation, escaped, or in a different chunk in future builds. **Mitigation:** Step 5.4 falls back to grepping `_next/static/chunks/app/**/page-*.js` (not just the login chunk) if the login chunk has zero JWT matches; document the fallback in Check 5's failure-mode notes. Long-term: when #2981 lands and Doppler becomes the single source, the bundle probe becomes the secondary gate, not the primary.
- **R2 — `dig +short CNAME api.soleur.ai` adds DNS dependency to CI.** GitHub `ubuntu-latest` runners have `dig` (already used by preflight Check 4 Step 4.2). NXDOMAIN / SERVFAIL would fail-closed. **Mitigation:** The Validate step explicitly errors with a recoverable message ("Cannot resolve canonical ref…"); operator can re-run the workflow if DNS hiccups. Alternative: pin `expected_ref=ifsccnjhymdmidffkzhl` as a literal in the workflow (rejected — adds a new rotation surface; CNAME resolution is the one source-of-truth that already exists).
- **R3 — Dev key drift.** If Doppler `dev.NEXT_PUBLIC_SUPABASE_ANON_KEY` ever gets the prd value (or vice versa), the URL/key cross-check would still pass (both refs would match the URL's canonical ref), but the wrong project would be hit. **Mitigation:** preflight Check 4 already enforces dev/prd URL distinctness (`hr-dev-prd-distinct-supabase-projects`). The anon-key cross-check anchors on URL ref, so as long as URL distinctness holds, anon-key distinctness is implied. Document this dependency in the validator's JSDoc.
- **R4 — Rotation lag between Doppler and GitHub secret.** Operator rotates Doppler but forgets the GitHub secret (or vice versa). The CI Validate step catches the GitHub-secret side; `verify-required-secrets.sh` catches the Doppler side. The two are independent gates. **Long-term mitigation:** #2981 (Doppler-only build-args) eliminates this class.
- **R5 — Service-role JWT paste.** Operator could paste the *service-role* key (which has admin perms) into the `_ANON_KEY` slot. The `role == "anon"` assertion catches this — but the consequence of a service-role JWT in the browser bundle is much worse than a test-fixture leak (every user gets admin perms in their browser session). **Mitigation:** call this out explicitly in the learning file and the validator's JSDoc; flag in PR body so reviewers know the test for `role == "anon"` is load-bearing for security, not just correctness.
- **R6 — Validator throw at module load could crash the prod app.** `client.ts` calls `assertProdSupabaseAnonKey` at module load (mirroring the existing `assertProdSupabaseUrl` pattern). A throw means the auth client cannot construct, which means the entire app dies on first render in production. **Mitigation:** This is intentional and matches the predecessor design — a malformed anon key WILL produce `Invalid API key AuthApiError` on every Supabase call anyway; failing at startup with a clear message is strictly better than failing per-request with a Sentry storm. The CI Validate step ensures a malformed value never reaches a built image, so the runtime throw is defense-in-depth, not the primary gate.
- **R7 — JWT decode in pure bash is finicky.** Padding bugs, base64url variant differences, `jq` exit codes. **Mitigation:** the test scenarios include hand-rolled fixture JWTs; Phase 8 step 2 (synthetic regression) exercises the workflow locally before merge.
- **R8 — `previewValue` truncation insufficient for service-role-key paste.** A service-role JWT is structurally identical to an anon JWT (same length, same base64url alphabet); truncated previews like `eyJhbGciOiJIUzI1NiI…fakesig` look identical to the anon-key preview. The `role` claim is what distinguishes them. **Mitigation:** the validator's error message includes the decoded `role` claim verbatim (it's not secret — `role` is one of `anon`, `authenticated`, `service_role`, all public knowledge), so operators see "expected role=anon, got role=service_role" and immediately understand the failure mode without exposing JWT bytes.
- **R9 (deepen) — bash `set -euo pipefail` + `seq 1 0`.** When `pad=0`, `printf '=%.0s' $(seq 1 0)` is empty (correct), but on some bash builds `seq 1 0` returns no output AND exits 0 (GNU coreutils) while on BSD `seq` it exits 1. **Mitigation:** the canonical helper uses `$(seq 1 $pad)` which is GNU-only; ubuntu-latest runners are GNU. If the helper is ever ported to macOS, replace with `printf '=%.0s' {1..$pad}` (which is also bash-only) or guard with `[[ $pad -gt 0 ]]`.
- **R10 (deepen) — `gh secret set` accepting CR-terminated input.** Predecessor learning's runbook uses `printf '%s' "$KEY" | gh secret set NEXT_PUBLIC_SUPABASE_ANON_KEY --body -`. If a future operator does `cat key.txt | gh secret set ...` and `key.txt` was authored on Windows (CRLF), the secret carries a `\r`. **Mitigation:** the helper strips `\r\n` from the JWT before splitting; the validator catches the malformed-segment case before it's rejected as "not 3 dots" (cleaner error message). Also noted as Sharp Edge.
- **R11 (deepen) — `iat`/`exp` skew across Supabase project re-creation.** If a Supabase project is destroyed and re-created with the same custom domain, the new project ref is different but the URL is the same. The CI Validate step's CNAME-resolution path correctly catches this (the new CNAME target is the new ref). The runtime validator catches it via the `ref` cross-check against the URL's resolved ref. The Doppler-side check catches it because Doppler's anon key value must be re-rotated when the project is re-created. All three layers converge on the right answer. Documented for clarity, no code change needed.

## Sharp Edges

- **Plan-time grep gate** (per `hr-when-a-plan-specifies-relative-paths-e-g`): every file path in this plan was verified via `git ls-files | grep -E '<path>'` returning exactly one match before plan finalization. Re-verify during execution.
- **Edit-together comment block** must list all four mirrored sites: workflow / verify-script / runtime validator / preflight Check 5. Adding a fifth gate (e.g., Sentry alert rule) requires updating all four comments AND this plan's mirror list.
- **Do NOT** verify the JWT signature in any of the four gates. These are shape gates; runtime auth is Supabase's responsibility. A signature check would require either embedding the project's JWT secret (impossible — the anon key IS public) or making a network call (defeats the "fail fast at build time" purpose).
- **Do NOT** generalize this PR to the other 4 `NEXT_PUBLIC_*` build-args (#2980's scope). The anon-key validator's structure (JWT decode + claims) is fundamentally different from the URL validator's (regex on hostname). Each subsequent generalization in #2980 will need its own validator module + tests + CI step + verify-script block + preflight step. Resist the temptation to ship a "generic NEXT_PUBLIC validator" — every build-arg has a different shape contract.
- **Test-suite blast-radius watch:** the existing 24 test files set `process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY` to a fixture value via `??=`. The validator's `NODE_ENV !== "production"` gate is the test-suite shield. **Verification grep before declaring AC7 met:**
  ```bash
  # Confirm the fixture reference count hasn't changed under the plan
  grep -rE 'NEXT_PUBLIC_SUPABASE_ANON_KEY' apps/web-platform/test/ | wc -l
  ```
- **JWT-decode verification step in workflow** uses `jq` — confirm `jq` is on `ubuntu-latest` runners (it is). If a future runner image drops `jq`, the workflow MUST fall back to a `node -e` decode, not silently skip.
- **Dependency on `validate-url.ts` being kept in production-mode:** if a future change makes `validate-url.ts` a no-op outside production (it already is), the URL canonical-shape input to `validate-anon-key.ts`'s cross-check is also a no-op outside production. This is correct behavior and matches the test-suite gate. Document the dependency in `validate-anon-key.ts` JSDoc.
- **Per AGENTS.md `hr-weigh-every-decision-against-target-user-impact`:** the `## User-Brand Impact` section above is filled and threshold is `single-user incident`. CPO sign-off required at plan time. Without filling this section, deepen-plan Phase 4.6 will halt.

### Service-Role-Key Paste — Critical Security Carve-out (deepen)

The `role == "anon"` assertion is **load-bearing for security, not just correctness.** A Supabase service-role JWT is structurally identical to an anon JWT (same algorithm, same claim set, same length envelope) — the only distinguishing field is `"role": "service_role"` vs `"role": "anon"`. If an operator pastes the **service-role key** into the `_ANON_KEY` slot:

1. Every browser session loads a JWT that grants admin-level RLS bypass.
2. Every authenticated user can read every other user's data via direct PostgREST calls from the browser console.
3. Every unauthenticated visitor can do the same against public-by-RLS-default tables.

This is **strictly worse** than the test-fixture leak (which merely broke auth and was self-evident). The service-role-key leak is a **silent data-exfiltration class** — the app keeps working from the user's perspective; only the attacker notices.

**Defense:**

1. The CI Validate step asserts `role == "anon"` literal and exits non-zero with `JWT role="service_role", expected "anon"` — caught BEFORE the image is built.
2. The runtime validator (`validate-anon-key.ts`) makes the same assertion at module load — caught BEFORE any Supabase call.
3. The bundle probe (preflight Check 5 Step 5.4) reads the inlined JWT and asserts `role == "anon"` — caught AFTER deploy as a black-box check.
4. The Doppler-side check (`verify-required-secrets.sh`) makes the same assertion — caught at the OTHER source of truth.

**Test:** `apps/web-platform/test/lib/supabase/anon-key-prod-guard.test.ts` case 6 explicitly tests `role = "service_role"` and asserts the error message contains the literal `"service_role"` so future regex tightening doesn't silently allow `*role*` to match anon.

**Why deepen pass is calling this out:** the URL leak class made the symptom obvious (sign-in broke). The role-leak class would not break sign-in at all — RLS bypass is silent until exploited. Without this carve-out being explicit in the plan, a reviewer might suggest "simplify the validator to just check the JWT shape and skip the claims" as a YAGNI cut. The claims check is YAGNI for the test-fixture class but load-bearing for the role-confusion class.

## Non-Goals

- **NG1 — Generalize to the other 4 `NEXT_PUBLIC_*` build-args.** Tracked in **#2980**. This PR closes only the `_ANON_KEY` portion.
- **NG2 — Doppler-only build-args migration (Option B).** Tracked in **#2981**. Would eliminate the dual-source-of-truth class entirely. Out of scope for this PR.
- **NG3 — Add a sixth defense layer (e.g., Sentry alert rule that fires when `Invalid API key` errorMessage substring is observed).** Already half-covered by PR #2994's Sentry mirror. A dedicated alert rule is a separate observability story.
- **NG4 — Verify the JWT signature against a known signing key.** See Sharp Edges — anon-key signature is not the appropriate gate; runtime Supabase auth is.
- **NG5 — Refactor `client.ts` to centralize all `NEXT_PUBLIC_*` validation behind a single `validateAllProdSecrets()` call.** Premature; per-validator modules let `cq-test-mocked-module-constant-import` keep working. Revisit if-and-when #2980 ships and there are 5+ validators.

## Domain Review

**Domains relevant:** Engineering (CTO), Product (CPO), Security (implicit in the credentials-handling class)

### CTO (Engineering)

**Status:** carry-forward from issue #3006 description (which is itself authored as a CTO assessment of the regression class)
**Assessment:** Multi-layer defense-in-depth is the correct response. The PR's structural choice (sibling `validate-anon-key.ts` rather than extending `validate-url.ts`) is correct because the two have fundamentally different shape contracts (regex vs JWT). The CI Validate step is the load-bearing gate (fail-before-image-build); the runtime + bundle-probe gates are defense-in-depth. **No architectural objection.**

### Product/UX Gate

**Tier:** none (no user-facing UI surface; CI/validation infra only)
**Decision:** N/A
**Rationale:** This plan touches CI workflows, server-side scripts, a validator module, a test file, a SKILL.md, and a learning file. Zero new pages, zero new components, zero copy. Mechanical escalation check: no new files matching `components/**/*.tsx`, `app/**/page.tsx`, or `app/**/layout.tsx`. Product/UX Gate skipped.

### CPO (Product) — User-Brand Impact carry-forward sign-off

**Status:** required (threshold = `single-user incident`)
**Assessment:** This is the third placeholder-secret-leak class incident in two weeks (#2979 URL, #3006 anon key, with security alerts in between). Each layer of defense closes one mechanism, but the underlying brand exposure ("sign-in is broken; users cannot reach their knowledge base") is the worst possible failure for a product whose moat is persistent compounding context. CPO carry-forward: **approve scope as-is**, but require that the learning file explicitly call out the recurrence pattern and prescribe #2980 + #2981 as the structural follow-ups. Failing to land #2981 within Phase 4 would make this a fourth incident waiting to happen.

## Resume prompt (copy-paste after `/clear`)

```text
/soleur:work knowledge-base/project/plans/2026-04-28-fix-supabase-anon-key-guardrails-plan.md
Branch: feat-one-shot-3006-supabase-anon-key-guardrails
Worktree: .worktrees/feat-one-shot-3006-supabase-anon-key-guardrails/
Issue: #3006
PR: TBD
Context: P1 anon-key test-fixture leaked into prod build (2026-04-28 18:53Z); hot-fix rotated at 16:56Z. This PR ships the symmetric guardrail set mirroring PR #2975's URL gates. Plan reviewed; implementation next.
```

## References

- Issue: #3006
- Predecessor: #2979 (URL regression) + PR #2975 (URL guardrails)
- Sentry mirror: PR #2994
- Generalization tracking: #2980 (5-var generalization), #2981 (Doppler-only Option B)
- Predecessor learning: `knowledge-base/project/learnings/bug-fixes/2026-04-28-oauth-supabase-url-test-fixture-leaked-into-prod-build.md`
- Placeholder-secret-class learning: `knowledge-base/project/learnings/2026-04-07-ux-agent-placeholder-secrets-trigger-push-protection.md`
- AGENTS.md rules: `hr-weigh-every-decision-against-target-user-impact`, `hr-dev-prd-distinct-supabase-projects`, `cq-test-mocked-module-constant-import`, `cq-write-failing-tests-before`, `wg-use-closes-n-in-pr-body-not-title-to`, `hr-when-a-plan-specifies-relative-paths-e-g`
- Constitution: `knowledge-base/project/constitution.md` (security gates, defense-in-depth)
- Predecessor plan: `knowledge-base/project/plans/2026-04-28-fix-oauth-supabase-url-prod-plan.md`
