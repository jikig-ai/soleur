---
title: "fix: KB-drift walker ingest — correct host + add route to PUBLIC_PATHS"
type: bug
date: 2026-05-29
branch: feat-one-shot-kb-drift-ingest-host-publicpath
lane: single-domain
status: planned
brand_survival_threshold: none
---

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
<!-- Phase 2.8 reviewed: no new infrastructure, no manual provisioning step is
     prescribed. The single TF edit (doppler_secret.kb_drift_ingest_url.value)
     stays in apps/web-platform/infra/kb-drift.tf — already IaC. The only
     "operator" reference is a statement of already-completed external fact
     (the live Doppler value was pre-corrected out of band); this PR mutates
     no live secret and the IaC section documents the apply path in full. -->

# 🐛 fix: KB-drift walker cron POST to ingest fails (wrong host + middleware session-gate)

## Enhancement Summary

**Deepened on:** 2026-05-29
**Sections enhanced:** Research Insights added (precedent-diff + verify-the-negative)
**Gates run:** 4.4 precedent-diff, 4.45 verify-the-negative + post-edit self-audit, 4.6 User-Brand Impact (pass, threshold `none` + scope-out bullet), 4.7 Observability (pass, 5 fields, no-SSH), 4.8 PAT-shaped variable (pass, none)

### Key Improvements

1. Confirmed `/api/inngest` is the exact canonical precedent for the `PUBLIC_PATHS` edit (same #4017 regression class, same comment style) — pattern is NOT novel.
2. Verified all three negative claims against the implementation (narrow path exposes nothing else; HMAC stays load-bearing; matcher rejects `/api/internal/other`).
3. Added the canonical `threshold: none, reason:` scope-out bullet required by Phase 4.6 for sensitive-path diffs.

## Research Insights (deepen-plan)

**Precedent-diff (Phase 4.4) — pattern is NOT novel.** The `PUBLIC_PATHS` edit has an exact sibling precedent already in `apps/web-platform/lib/routes.ts`:

- `/api/webhooks` (line 9), `/api/inngest` (line 16, with a multi-line comment documenting the HMAC-gated-no-session rationale + the #4017 regression), `/api/shared` (line 20) are all signature-authed routes that bypass the Supabase session redirect. The new `/api/internal/kb-drift-ingest` entry is the same shape: HMAC-gated by the route handler, no session cookie, middleware would 307→/login. Adopt the `/api/inngest` comment block verbatim in style (cite #4017 as the regression class).

**Verify-the-negative (Phase 4.45) — all claims confirmed against implementation:**

| Negative claim | Verification | Result |
| --- | --- | --- |
| "narrow path exposes nothing else" | `find app/api/internal -name route.ts` → only `kb-drift-ingest/route.ts` | confirms — no sibling internal route to expose |
| "HMAC stays load-bearing post-fix" | `route.ts:97` `verifyHmac(...)` gate returns 401 (`route.ts:103`) before any DB write; independent of middleware | confirms — bypassing the session redirect does not weaken the route's own auth |
| "matcher rejects `/api/internal/other`" | `middleware.ts:129` matcher is `pathname === p \|\| pathname.startsWith(p + "/")`; narrow path `p` = `/api/internal/kb-drift-ingest` → `/api/internal/other` is neither equal nor a `p + "/"` prefix | confirms — prefix-collision guard holds |

**Post-edit self-audit (Phase 4.45):** No infrastructure was dropped/renamed by this plan; no dangling-symbol references. The only TF mutation is a single `value` literal; `ignore_changes = [value]` is preserved (no resource dropped).

## Overview

The nightly `.github/workflows/kb-drift-walker.yml` cron walks the KB for broken links/anchors, HMAC-signs the JSON findings, and `POST`s them to `KB_DRIFT_INGEST_URL`. The POST is failing for **two independent reasons**, both verified live and against the codebase:

1. **Wrong host (live already fixed; code default still wrong).** `KB_DRIFT_INGEST_URL` pointed at the apex `https://soleur.ai/...`, which is the Cloudflare static marketing site and returns **405 Not Allowed** for POST. The app lives at `app.soleur.ai`. The live Doppler secret (`prd_kb_drift_walker`) has **already** been corrected to `https://app.soleur.ai/api/internal/kb-drift-ingest`. The hardcoded Terraform default in `apps/web-platform/infra/kb-drift.tf` (resource `doppler_secret.kb_drift_ingest_url`, line 52) is **still** `https://soleur.ai/...`, so a fresh `terraform apply` would re-introduce the wrong host on a fresh tenant. The `lifecycle { ignore_changes = [value] }` block (lines 55-57) means apply does NOT clobber the live value today — but the default is the wrong baseline and MUST be corrected for first-apply correctness.

2. **Middleware session gate (primary code fix).** The route `/api/internal/kb-drift-ingest` is **not** in `PUBLIC_PATHS` (`apps/web-platform/lib/routes.ts`). The Supabase auth middleware (`apps/web-platform/middleware.ts:289-291`) therefore 307/redirects the unauthenticated (HMAC-only, no session cookie) POST to `/login`. The route handler never runs, so the workflow's gate `test "$HTTP_CODE" -ge 200 -a "$HTTP_CODE" -lt 300` (line 67) fails. Verified live: `POST https://app.soleur.ai/api/internal/kb-drift-ingest` → **307 → /login**.

This is the exact same class of regression that #4017 caused for `/api/inngest`: a signature-authed route that carries no session cookie gets bounced by Supabase middleware before its own auth gate runs. The fix mirrors the `/api/inngest` precedent already present in `PUBLIC_PATHS`.

### Verification of the diagnosed root cause (all confirmed)

| Claim | File:line | Status |
| --- | --- | --- |
| TF default is wrong-host apex | `apps/web-platform/infra/kb-drift.tf:52` (`value = "https://soleur.ai/api/internal/kb-drift-ingest"`) | confirmed |
| `ignore_changes = [value]` present, must keep | `apps/web-platform/infra/kb-drift.tf:55-57` | confirmed |
| Route NOT in `PUBLIC_PATHS` | `apps/web-platform/lib/routes.ts:5-22` | confirmed — no `/api/internal*` entry |
| Middleware redirects unauthed POST to `/login` | `apps/web-platform/middleware.ts:289-291` | confirmed |
| Route returns 401 bad sig / 2xx good sig once reached | `apps/web-platform/app/api/internal/kb-drift-ingest/route.ts:103,166` | confirmed |
| Workflow asserts 2xx | `.github/workflows/kb-drift-walker.yml:67` | confirmed |
| Signature header matches | workflow `X-Soleur-Kb-Drift-Signature` (line 63) == route `SIGNATURE_HEADER` (line 40), case-insensitive | confirmed |
| Only `/api/internal/*` route today | `apps/web-platform/app/api/internal/` → `kb-drift-ingest` only | confirmed — narrow path exposes nothing else |

## Research Reconciliation — Spec vs. Codebase

| Diagnosed claim | Codebase reality | Plan response |
| --- | --- | --- |
| "Live Doppler secret already updated to `app.soleur.ai`" | Cannot be re-verified from the repo (external state); the prompt asserts it and it is the operator's already-applied change | Trust the assertion. Do NOT mutate Doppler in this PR. Code-fix only. Post-merge `workflow_dispatch` is the live verification. |
| "Add the broad `/api/internal` prefix" (rejected by prompt) | Only `kb-drift-ingest` exists under `/api/internal/` today; middleware uses `pathname === p \|\| pathname.startsWith(p + "/")` matching | Use the **narrow exact path** `/api/internal/kb-drift-ingest`. A broad `/api/internal` prefix would session-bypass any *future* internal route — a latent security footgun. Narrow is correct. |
| "There may be a middleware/routes test asserting PUBLIC_PATHS membership" | `apps/web-platform/test/middleware.test.ts` exists with an `isPublicPath()` helper + a "prefix collision prevention" describe block — exact fit | Extend `middleware.test.ts` (not just the route test) so the bypass-session assertion lives where PUBLIC_PATHS membership is already covered. |

## User-Brand Impact

**If this lands broken, the user experiences:** the nightly KB-drift walker silently never persists findings — broken links/anchors in the knowledge base accumulate undetected, and the operator's `knowledge`-domain draft queue never receives drift alerts. No user-visible UI breakage; this is an internal infra signal cron.

**If this leaks, the user's data / workflow / money is exposed via:** the narrow path `/api/internal/kb-drift-ingest` becoming session-public. Mitigation is structural — the route's own HMAC-SHA256 gate (`KB_DRIFT_INGEST_SIGNING_KEY`, route.ts:97-104) is the load-bearing auth; making it session-public only removes the Supabase redirect, not the HMAC check. Bad/absent signature still returns 401. The narrow exact path ensures no *other* internal route inherits session-bypass.

**Brand-survival threshold:** none. Internal infra-signal cron; HMAC remains load-bearing post-fix; no regulated-data surface widened (the route already exists and already writes to `messages` under the operator founder id — this PR does not change what it writes or who can reach the handler logically, only removes a redirect that prevented the legitimate caller from reaching it). The sensitive-path note: `middleware.ts` + an `/api/*` route + `apps/web-platform/infra/` are touched, but the change is *removing a redirect in front of an already-HMAC-gated route* plus a TF string-default correction, not adding a new data path.

- **threshold: none, reason:** the diff touches sensitive paths (`middleware.ts`, `app/api/internal/...`, `infra/kb-drift.tf`) but adds no new processing activity, no schema change, and no new lawful-basis surface — it removes a Supabase redirect in front of an already-HMAC-gated route (HMAC stays load-bearing) and corrects a Terraform string default.

## Files to Edit

1. **`apps/web-platform/lib/routes.ts`** — add the narrow exact path `/api/internal/kb-drift-ingest` to the `PUBLIC_PATHS` array, with a sibling-style comment mirroring the `/api/inngest` block (explain: HMAC-authed by the route handler, no session cookie, Supabase middleware would 307→/login, regression class of #4017, fixed for KB-drift-walker cron). Place it adjacent to the other signature-authed entries (`/api/webhooks`, `/api/inngest`, `/api/shared`).

   ```ts
   // /api/internal/kb-drift-ingest: HMAC-SHA256-gated POST (signing key
   // KB_DRIFT_INGEST_SIGNING_KEY) from the nightly KB-drift walker cron.
   // No session cookie — Supabase middleware would 307→/login and the
   // route's own HMAC gate (route.ts:97) would never run, failing the
   // workflow's 2xx assertion. Same class as #4017 (/api/inngest).
   // NARROW exact path — do NOT broaden to /api/internal (would session-
   // bypass future internal routes). Verified live: apex POST → 307 → /login.
   "/api/internal/kb-drift-ingest",
   ```

2. **`apps/web-platform/infra/kb-drift.tf`** — change line 52 `value` from `"https://soleur.ai/api/internal/kb-drift-ingest"` to `"https://app.soleur.ai/api/internal/kb-drift-ingest"`. **Keep** the `lifecycle { ignore_changes = [value] }` block (lines 55-57) intact. Optionally update the resource comment to note the `app.` subdomain is the canonical app host (apex is the Cloudflare static marketing site → 405 on POST).

3. **`apps/web-platform/test/middleware.test.ts`** — add coverage in the existing "public paths" + "prefix collision prevention" describe blocks:
   - `expect(isPublicPath("/api/internal/kb-drift-ingest")).toBe(true)` — the route bypasses the session redirect.
   - `expect(isPublicPath("/api/internal")).toBe(false)` and `expect(isPublicPath("/api/internal/other-future-route")).toBe(false)` — prefix-collision guard proving the narrow path does NOT expose sibling/future internal routes (the `pathname === p || pathname.startsWith(p + "/")` matcher means `/api/internal/kb-drift-ingest/...` subpaths match, but `/api/internal/other` does not). Add a comment citing #4017 + the regression class.
   - Reuse the existing `isPublicPath()` helper (lines 6-8) — no new helper needed.

4. **`apps/web-platform/test/server/internal/kb-drift-ingest-route.test.ts`** (optional/light) — the existing suite already asserts 401-bad-sig / 401-missing-sig / 2xx-good-sig (lines 77-99, 123-138), which is exactly the post-deploy contract. No new assertion is strictly required here; the *middleware* test (file 3) is where the new coverage belongs (the bug was the redirect, not the handler). If desired, add a one-line comment at the top of this file cross-referencing the middleware PUBLIC_PATHS entry so a future reader sees the two-part auth story (middleware-bypass + handler-HMAC). Do NOT add a Doppler/host assertion here — the dummy `https://soleur.ai/...` Request URL on line 44 is irrelevant to the handler (only the path + headers + body matter).

## Files to Create

None.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `apps/web-platform/lib/routes.ts` `PUBLIC_PATHS` contains the exact string `/api/internal/kb-drift-ingest` and does NOT contain a bare `/api/internal` entry. Verify: `grep -n "api/internal/kb-drift-ingest" apps/web-platform/lib/routes.ts` returns 1 array entry; `grep -nE '"/api/internal"' apps/web-platform/lib/routes.ts` returns nothing.
- [ ] `apps/web-platform/infra/kb-drift.tf` line for `doppler_secret.kb_drift_ingest_url` `value` reads `https://app.soleur.ai/api/internal/kb-drift-ingest`. Verify: `grep -n 'kb_drift_ingest_url' -A4 apps/web-platform/infra/kb-drift.tf` shows the `app.soleur.ai` value AND the `ignore_changes = [value]` lifecycle block still present.
- [ ] `terraform fmt -check apps/web-platform/infra/kb-drift.tf` passes (no formatting drift introduced by the edit).
- [ ] `apps/web-platform/test/middleware.test.ts` asserts `isPublicPath("/api/internal/kb-drift-ingest") === true` AND `isPublicPath("/api/internal") === false`.
- [ ] Test suite passes. Runner is **vitest** (NOT bun — `apps/web-platform/bunfig.toml` sets `[test] pathIgnorePatterns = ["**"]`, blocking bun test discovery, per #1469). Run from `apps/web-platform/`:
  `./node_modules/.bin/vitest run test/middleware.test.ts test/server/internal/kb-drift-ingest-route.test.ts`
- [ ] `tsc --noEmit` (web-platform) clean.

### Post-merge (operator / CI)

- [ ] **Automation: feasible — bake into post-merge verification, do NOT punt to operator.** After merge + deploy of `app.soleur.ai`, dispatch the walker workflow: `gh workflow run "KB-drift walker"` then poll `gh run list --workflow "KB-drift walker" --limit 1 --json status,conclusion`. Expected `conclusion: success`. The workflow's own gate (`test "$HTTP_CODE" -ge 200 -a "$HTTP_CODE" -lt 300`, line 67) is the live acceptance check — a green run proves the POST reached the handler and got a 2xx (HMAC verified end-to-end).
- [ ] An unauthenticated `POST https://app.soleur.ai/api/internal/kb-drift-ingest` with a **bad/absent** signature returns **401** (not 307, not 405). Verify: `curl -sS -o /dev/null -w '%{http_code}' -X POST https://app.soleur.ai/api/internal/kb-drift-ingest -H 'Content-Type: application/json' --data '{}'` → `401`. (Confirms the redirect is gone AND the HMAC gate is now load-bearing.)
- [ ] No Doppler mutation in this PR — the live `KB_DRIFT_INGEST_URL` is already correct (operator pre-applied). The TF default correction is for fresh-tenant first-apply only.

## Domain Review

**Domains relevant:** none

Infrastructure/tooling bug fix. The change removes a Supabase-middleware redirect in front of an already-HMAC-gated internal cron route and corrects a Terraform string default. No user-facing UI surface, no new data processing, no product/marketing/legal/finance implications. Security posture is *improved* (the HMAC gate becomes the sole, load-bearing auth as designed, instead of being masked by a session redirect that prevented the legitimate caller from reaching it). Narrow-path choice explicitly avoids exposing sibling/future `/api/internal/*` routes.

## Infrastructure (IaC)

This plan edits an existing Terraform-managed resource value; it introduces no new infrastructure, no new secret, no new vendor, no new runtime process. The Doppler config `prd_kb_drift_walker`, the signing key, the service token, and the GH Actions secret all already exist (provisioned by `apps/web-platform/infra/kb-drift.tf`). No manual provisioning step is prescribed.

### Terraform changes

- `apps/web-platform/infra/kb-drift.tf` — single-attribute change: `doppler_secret.kb_drift_ingest_url.value` apex → `app.` subdomain. No provider/version changes, no new variables, no new resources.

### Apply path

- **No apply required for live correctness.** The live Doppler value is already correct (operator pre-applied out of band). The `lifecycle.ignore_changes = [value]` block means a routine `terraform apply` will NOT touch the live value and will NOT show drift on this attribute. The code edit is purely to make the *baseline default* correct for a fresh-tenant first apply (where `ignore_changes` has nothing to ignore yet and the literal default is what lands).
- Blast radius: zero on existing prd (ignored attribute). On a fresh tenant: the correct host lands on first apply.

### Distinctness / drift safeguards

- `lifecycle.ignore_changes = [value]` is preserved verbatim — required so the operator's live override is never clobbered by future applies.
- No state-storage concern beyond the existing R2 backend; the value is `masked` visibility in Doppler and already lands in `terraform.tfstate` (unchanged by this PR).

### Vendor-tier reality check

N/A — no tier-gated resource creation; this is a string default edit on an existing free-to-create Doppler secret resource.

## Observability

```yaml
liveness_signal:
  what: "KB-drift walker workflow run conclusion (GitHub Actions)"
  cadence: "nightly cron 0 3 * * * + on-demand workflow_dispatch"
  alert_target: "GitHub Actions run-failure notification on the soleur repo"
  configured_in: ".github/workflows/kb-drift-walker.yml (gate: test HTTP_CODE 2xx, line 67)"
error_reporting:
  destination: "Sentry (route.ts: captureMessage on secret-unset/HMAC-fail/operator-id-unset; captureException on persist-fail)"
  fail_loud: true
failure_modes:
  - mode: "middleware 307 to /login (the bug)"
    detection: "workflow gate fails (curl gets 307, not 2xx); post-fix curl probe returns 401 not 307"
    alert_route: "GitHub Actions failed-run notification"
  - mode: "bad/missing HMAC signature"
    detection: "route returns 401 + Sentry captureMessage op:signature"
    alert_route: "Sentry feature=kb-drift-ingest"
  - mode: "wrong host (405 from apex Cloudflare site)"
    detection: "workflow gate fails with HTTP 405; post-fix INGEST_URL points at app.soleur.ai"
    alert_route: "GitHub Actions failed-run notification"
  - mode: "persist DB error (non-conflict)"
    detection: "route returns 500 + Sentry captureException op:persist"
    alert_route: "Sentry feature=kb-drift-ingest"
logs:
  where: "GitHub Actions run log (echoes HTTP_CODE + ingest response body, lines 65-66); server-side pino logger.error in route.ts"
  retention: "GitHub Actions default (90d); pino to server log sink"
discoverability_test:
  command: curl -fsS -o /dev/null -w "%{http_code}" --max-time 10 https://app.soleur.ai/login
  expected_output: "200"
```

## Open Code-Review Overlap

1 open scope-out touches a file this plan edits:
- **#2591** (`docs(security): document CSP middleware + route intersection for binary types`) touches `middleware.ts`. **Disposition: Acknowledge.** Different concern — #2591 is about documenting CSP behavior for binary content types, not PUBLIC_PATHS routing. This plan adds one `PUBLIC_PATHS` entry in `lib/routes.ts` (consumed by middleware) and does not touch CSP logic. The scope-out remains open; no fold-in, no rework risk.

## Test Scenarios

1. **Middleware bypass (unit, `middleware.test.ts`):** `isPublicPath("/api/internal/kb-drift-ingest")` → `true`; `isPublicPath("/api/internal")` → `false`; `isPublicPath("/api/internal/other")` → `false`.
2. **Handler HMAC contract (already covered, `kb-drift-ingest-route.test.ts`):** bad sig → 401; missing sig → 401; good sig + valid payload → 200; PG unique violation → silent dedup 200; non-conflict DB error → 500.
3. **Live post-deploy (post-merge AC):** `workflow_dispatch` of "KB-drift walker" → green; `curl` bad-sig POST to `app.soleur.ai` → 401 (not 307/405).

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. (This plan's section is filled with threshold `none` + sensitive-path reason.)
- **Do NOT broaden to `/api/internal`.** The middleware matcher `pathname === p || pathname.startsWith(p + "/")` means a bare `/api/internal` entry would session-bypass every future `/api/internal/*` route. Use the exact path only. (Prompt-prescribed; verified only one route exists today.)
- **Runner is vitest, not bun.** `apps/web-platform/bunfig.toml` sets `[test] pathIgnorePatterns = ["**"]` (#1469) — `bun test <file>` reports "filter did not match" even when the file exists. Use `./node_modules/.bin/vitest run <path>`.
- **Keep `lifecycle.ignore_changes = [value]`** on `doppler_secret.kb_drift_ingest_url`. Removing it would let a future apply clobber the operator's live override. Edit only the `value` literal.
- **No Doppler mutation in this PR.** The live secret is already correct (operator pre-applied). This PR is code-only; the TF edit fixes the fresh-tenant baseline default.
- The dummy `https://soleur.ai/...` URL in `kb-drift-ingest-route.test.ts:44` is a Request-object placeholder — the handler reads path/headers/body, not host. Do NOT "fix" it; it is not the bug.
