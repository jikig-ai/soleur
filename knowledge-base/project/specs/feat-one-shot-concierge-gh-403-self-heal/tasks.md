---
feature: feat-one-shot-concierge-gh-403-self-heal
lane: cross-domain
plan: knowledge-base/project/plans/2026-06-08-fix-concierge-gh-403-self-heal-hardening-plan.md
brand_survival_threshold: single-user incident
---

# Tasks — Harden Concierge GitHub-App installation self-heal (residual gh-403 bugs)

> Premise: PR #4946 already shipped the self-heal + entitlement gate + mint observability + reproduce harness. This closes 3 residual bugs. Write failing tests FIRST (`cq-write-failing-tests-before`). Never log token values (`hr-github-app-auth-not-pat`). Fail-closed: an `indeterminate` membership probe after retries DENIES promotion.

## Phase 0 — Preconditions

- [ ] 0.1 Confirm `cc-dispatcher.ts:260-271` `GH_403_PROMPT_DIRECTIVE` ends with the contradictory "...ask the user to confirm the Soleur GitHub App is installed..." clause (the Bug-C target). Verify the AC6 negative-match phrases (`sanctioned next step`, `persists across retries`) each live within a single `" +\n  "` source segment (lines 268 / 269); confirm `confirm the Soleur GitHub App is installed` is split across the 269→270 boundary (do NOT use it).
- [ ] 0.2 Read the canonical retry idiom (`server/github-api.ts:22-89`, `isRetryable` `:29-51`) and the sibling 401-retry loop + constants (`server/github-app.ts:591-592, 631-651`). Decide: reuse the `github-api.ts` retry helper for the members probe, or a local loop matching the same shape/constants.
- [ ] 0.3 Confirm `reportSilentFallback` (`observability.ts:184`) accepts `err: unknown` so a non-Error first arg routes to `Sentry.captureMessage` (skip-mirror needs a queryable EVENT, not a breadcrumb-only `log.info`).

## Phase 1 — RED (failing tests first)

- [ ] 1.1 (Bug A) Extend `test/github-app-mint-observability.test.ts` with `describe("findRepoOwnerInstallationForUser — transient probe robustness")`:
  - [ ] 1.1.1 (AC1) members probe 500 → retry → 204 ⇒ returns owner install.
  - [ ] 1.1.2 (AC2) members probe 500 on every attempt ⇒ returns `null`, no throw.
  - [ ] 1.1.3 (AC2) `memberCheck` fetch rejects (AbortSignal.timeout) ⇒ caught → `indeterminate` → `null`, no throw.
  - [ ] 1.1.4 (AC3) members probe 404 ⇒ `null`, fetch called exactly once for the members endpoint (no retry); same for 302.
  - [ ] 1.1.5 (AC5) assert no `ghs_`/`gho_`/`ghp_` token substring in any logged arg.
- [ ] 1.2 (Bug B) Create `test/cc-dispatcher-self-heal-observability.test.ts` (under `test/**` — vitest node project `include`):
  - [ ] 1.2.1 (AC4) deny path (probe `not-member`/`indeterminate`, or org-type stored install) ⇒ `reportSilentFallback` called once with `feature:"cc-dispatcher"`, skip `op`, and `extra` = { storedInstallationId, owner, membershipProbeOutcome, effectiveInstallationId(==stored) }. `alreadyCorrect` (no-op) does NOT mirror.
  - [ ] 1.2.2 (AC5) no token substring in the mirror payload.
  - [ ] If the deny branch can't be unit-invoked whole, extract a pure `mirrorSelfHealSkip(...)` helper (per the `buildConnectedRepoContext` export precedent) and test it directly + source-presence assert the orchestration calls it on the deny branch.
- [ ] 1.3 (Bug C) Extend `test/cc-dispatcher-gh-403-directive.test.ts`:
  - [ ] 1.3.1 (AC6) assert directive body does NOT match `/sanctioned next step/i` AND does NOT match `/persists across retries/i`.
  - [ ] 1.3.2 (AC7) assert directive still matches `/speculate/i`, `/re-consent/i`, `/change GitHub App permissions/i`.
- [ ] 1.4 Run the three test files; confirm the new assertions FAIL against current `main`.

## Phase 2 — GREEN (Bug A: membership-probe robustness)

- [ ] 2.1 In `server/github-app.ts`, refactor the `findRepoOwnerInstallationForUser` members probe (529-561) to a helper returning `member` | `not-member` | `indeterminate`: try/catch the `memberCheck` fetch; `204→member`, `404`/`302`→`not-member`, `>= 500`/`isRetryable(throw)`→`indeterminate`; retry `indeterminate` only, reusing the canonical idiom (`github-api.ts` helper or a local loop matching `MAX_RETRIES=2`/`BASE_DELAY=1000`/`2**attempt`/fresh signal/body-drain). Fail-closed: post-retry `indeterminate` ⇒ `null`. Owner install returned ONLY on `member`.
- [ ] 2.2 Apply the same 3-value classification to `findOrgInstallationForUser` (401-457, probe at `:447`).
- [ ] 2.3 Do NOT touch `verifyInstallationOwnership` (`:330`) — connect-time, out of scope. Note it in the PR body as the deliberately-untouched third `/members/` site.
- [ ] 2.4 Surface the probe outcome to the caller (`{ installationId, outcome }` or via the helper) so Phase 3 can mirror it.
- [ ] 2.5 Run Bug-A tests → green.

## Phase 3 — GREEN (Bug B: mirror skip/abort decisions)

- [ ] 3.1 In `server/cc-dispatcher.ts` self-heal block (1396-1449), route the deny/skip decisions (probe `not-member`/`indeterminate`; org-type stored install) through `reportSilentFallback` with `feature:"cc-dispatcher"`, a skip `op` (e.g. `self-heal-skip`), and `extra` = { storedInstallationId, owner, membershipProbeOutcome ("204"/"404"/"302"/"indeterminate"), effectiveInstallationId }. Keep the existing success `log.info` (1413-1421). Do NOT mirror `alreadyCorrect` (no-op). NEVER include a token value.
- [ ] 3.2 Run Bug-B tests → green.

## Phase 4 — GREEN (Bug C: directive contradiction)

- [ ] 4.1 In `server/cc-dispatcher.ts` (260-271), delete the clause "The one sanctioned next step you may offer: if the 403 persists across retries, ask the user to confirm the Soleur GitHub App is installed on the repository's owner account." — directive now ends at "...with the correct installation automatically." (line 267 segment).
- [ ] 4.2 Run Bug-C tests → green.

## Phase 5 — Verify

- [ ] 5.1 `cd apps/web-platform && ./node_modules/.bin/vitest run test/github-app-mint-observability.test.ts test/cc-dispatcher-gh-403-directive.test.ts test/cc-dispatcher-self-heal-observability.test.ts` — all green (AC9).
- [ ] 5.2 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` — clean (AC9).
- [ ] 5.3 (Optional, read-only) re-confirm live signature: `doppler run -p soleur -c dev -- ./node_modules/.bin/tsx scripts/spike/reproduce-gh-403.ts`.
- [ ] 5.4 PR body: `Ref #...` the source (screenshot bug); enumerate the 3 `/members/` sites + the untouched one; state the Sentry discoverability path (`feature:cc-dispatcher op:self-heal-skip`). CPO sign-off (directive copy deletion) confirmed before merge; `user-impact-reviewer` + `security-sentinel` at review confirm fail-closed direction.
