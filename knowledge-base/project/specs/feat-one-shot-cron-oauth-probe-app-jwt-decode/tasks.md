---
title: "Tasks — cron-oauth-probe App-JWT 'could not be decoded' root-cause"
lane: cross-domain
plan: knowledge-base/project/plans/2026-05-29-fix-cron-oauth-probe-app-jwt-decode-recurrence-plan.md
---

# Tasks — cron-oauth-probe App-JWT decode recurrence

> Evidence-first. Phase 1 selects the fix; exactly ONE Phase 2 branch ships.
> Do NOT ship a 7th format/retry patch (PKCS#8 + retry-on-401 both disproven).

> **VERDICT (Phase 1, 2026-05-29): H2 — credential CONTENT wrong.** `ghStatus:401`
> + `attempts:3` (persistent across retries) ruled out transient-401/format/clock.
> Doppler `prd` `GITHUB_APP_PRIVATE_KEY` does NOT match App `soleur-ai` (3261325)
> — `GET /app` oracle returned 401 even with a trimmed App ID + normalized key.
> Latent contributor: `GITHUB_APP_ID` was `"3261325\n"` (correct ID, trailing \n).
> H3/H4 branches NOT taken.

## Phase 0 — Preconditions (read-only)

- [x] 0.1 Re-assert recurrence is post-fix: `git merge-base --is-ancestor 9da77d86 db87c27d && echo OK`. → OK (9da77d86 is ancestor of db87c27d).
- [x] 0.2 Re-read `probe-octokit.ts` (`extractGitHubErrorDiag` + breadcrumb shape). Actual path: `server/github/probe-octokit.ts:58-89,136-144`.

## Phase 1 — Pull #4568 diagnostic evidence (decisive)

- [x] 1.1 Sentry events API: fetched event `00bdfdf1…` via project-scoped events endpoint (the 32-hex is the EVENT id, not a numeric issue group). `ghStatus:401, clockSkewMs:345, attempts:3, ghBody:[Filtered], release:0.101.100+db87c27d`.
- [x] 1.2 Decision rule → **H2** (ghStatus:401 = GitHub rejected a SENT JWT; persisted 3×). Recorded in PR body.
- [x] 1.3 `GITHUB_APP_ID` shape: `{len:8, trimmedLen:7, numeric:true, looksLikeClientId:false, hasWhitespace:true}` — correct numeric ID `3261325` with a trailing `\n`.
- [x] 1.4 `GET /app` oracle via hand-rolled signer (trimmed ID + normalized key) → **401 "could not be decoded"** ⇒ key↔App mismatch (H2). Public `GET /apps/soleur-ai` confirms App ID 3261325 is correct.

## Phase 2 — Targeted fix (exactly ONE branch)

### H1/H2 — credential drift (operator + code hardening) ✅ SELECTED
- [ ] 2a.1 (operator, post-merge ack) Re-set correct numeric `GITHUB_APP_ID` (strip `\n`) / re-mint matching PKCS#8 key for App `soleur-ai` in Doppler `prd`. → tracked, Phase 6.
- [x] 2a.2 (code, ships regardless) Added `readAppId()` trim+numeric guard in `app-private-key.ts`; routed all three `new App()` sites (`createProbeOctokit`, `createAppJwtOctokit`, `createGitHubAppClient`) AND the immune `github-app.ts getAppId()` through it; throws a specific error naming the client-id confusion. RED→GREEN.

### H3 — clock skew (IaC) — NOT TAKEN (clockSkewMs:345, trivial)
- [ ] 2b.1 (not applicable — H2)
- [ ] 2b.2 (not applicable — H2)

### H4 — octokit DER extraction (code) — NOT TAKEN (ghStatus:401 present ⇒ GitHub-side rejection, not pre-request throw)
- [ ] 2c.1 (not applicable — H2)

## Phase 3 — Correct the runbook (always)

- [x] 3.1 Rewrote `oauth-probe-failure.md` `probe_app_jwt_decode`: "Fix shipped (this class)" → two distinct classes; #4569 "necessary but insufficient — recurred on a release containing it (verified)".
- [x] 3.2 Appended STEP 1-4 evidence recipes (Sentry events-by-id, App-ID shape, `GET /app` oracle, public App-ID lookup).
- [x] 3.3 Bumped runbook `related_prs` (added 4498, 4513, 4565, 4568, 4569).

## Phase 4 — Regression test

- [x] 4.1 `app-private-key-readappid.test.ts`: `readAppId()` rejects non-numeric/client-id/whitespace-only/internal-space; strips trailing `\n` (exact prod shape); accepts clean numeric. (RED→GREEN, pure string tests, no key.)
- [ ] 4.2 (H4 only — not applicable)

## Phase 5 — Verify (pre-merge)

- [x] 5.1 `tsc --noEmit` EXIT=0 + full vitest (581 files, 7180 passed, 0 failed).
- [x] 5.2 PR body carries the H2 verdict + evidence; diff confirms no retry-widening, no PEM-format change (only the App-ID guard + runbook).

## Phase 6 — Post-merge (operator)

- [ ] 6.1 Re-mint `soleur-ai` private key (consent-gated; no REST path) + strip `GITHUB_APP_ID` `\n` in Doppler `prd` (explicit ack).
- [ ] 6.2 `inngest send cron/oauth-probe.manual-trigger`; confirm checkins API returns `ok`.
- [ ] 6.3 `gh issue close <N>` AFTER recovery confirmed (PR body uses `Ref #N`, not `Closes #N`).
