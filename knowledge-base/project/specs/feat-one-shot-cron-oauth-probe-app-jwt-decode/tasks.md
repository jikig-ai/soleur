---
title: "Tasks — cron-oauth-probe App-JWT 'could not be decoded' root-cause"
lane: cross-domain
plan: knowledge-base/project/plans/2026-05-29-fix-cron-oauth-probe-app-jwt-decode-recurrence-plan.md
---

# Tasks — cron-oauth-probe App-JWT decode recurrence

> Evidence-first. Phase 1 selects the fix; exactly ONE Phase 2 branch ships.
> Do NOT ship a 7th format/retry patch (PKCS#8 + retry-on-401 both disproven).

## Phase 0 — Preconditions (read-only)

- [ ] 0.1 Re-assert recurrence is post-fix: `git merge-base --is-ancestor 9da77d86 db87c27d && echo OK`.
- [ ] 0.2 Re-read `probe-octokit.ts:58-89` (`extractGitHubErrorDiag`) + `:136-144` (breadcrumb shape).

## Phase 1 — Pull #4568 diagnostic evidence (decisive)

- [ ] 1.1 Sentry events API: fetch latest event for issue `00bdfdf1543c472e91552d45565f1e74`; read `extra.{ghStatus,ghBody,ghRequestId,clockSkewMs,attempts}` + `release`.
- [ ] 1.2 Apply Decision rule → record H-verdict (H1/H2/H3/H4) in PR body.
- [ ] 1.3 `GITHUB_APP_ID` shape check (non-SSH, never prints value): numeric? client-id-shaped? whitespace?
- [ ] 1.4 `GET /app` credential oracle via the hand-rolled signer (doppler run). 200 ⇒ H4; 401/decode ⇒ H1/H2.

## Phase 2 — Targeted fix (exactly ONE branch)

### H1/H2 — credential drift (operator + code hardening)
- [ ] 2a.1 (operator, post-merge ack) Re-set correct numeric `GITHUB_APP_ID` / re-mint matching PKCS#8 key in Doppler `prd`.
- [ ] 2a.2 (code, ships regardless) Add `readAppId()` numeric/`trim()` guard in `app-private-key.ts`; route all three `new App()` sites (`createProbeOctokit`, `createAppJwtOctokit`, `app-client.ts createGitHubAppClient`) through it; throw a specific error naming the client-id confusion.

### H3 — clock skew (IaC)
- [ ] 2b.1 Add `chrony`/`systemd-timesyncd` to `apps/web-platform/infra/cloud-init.yml` `runcmd` (line 290) + idempotent `inngest-timesync-bootstrap.sh`; document apply path. (invoke terraform-architect)
- [ ] 2b.2 Promote `clockSkewMs` to a Sentry tag (alertable).

### H4 — octokit DER extraction (code)
- [ ] 2c.1 Route probe JWT minting through the immune `crypto.createSign` shape via `createAppAuth`/`authStrategy` override (NOT a JWT hand-off — constructor has no explicit-JWT option). Precedent-diff vs `github-app.ts:119-152`.

## Phase 3 — Correct the runbook (always)

- [ ] 3.1 Rewrite `oauth-probe-failure.md` `probe_app_jwt_decode` "Fix shipped (this class)" → "insufficient; recurred on a release containing #4569 (verified)".
- [ ] 3.2 Append Phase 1 Sentry-events + `GET /app` oracle recipes.
- [ ] 3.3 Bump `related_prs`/`related_issues` frontmatter.

## Phase 4 — Regression test

- [ ] 4.1 Synthesized-keypair unit test: `readAppId()` rejects non-numeric/client-id/whitespace; accepts clean numeric. (RED→GREEN, no real key.)
- [ ] 4.2 (H4 only) JWT round-trip test: unified mint verifies under the App public key; header/iss/exp shape matches `github-app.ts`.

## Phase 5 — Verify (pre-merge)

- [ ] 5.1 `tsc --noEmit` + vitest (web-platform runner) pass.
- [ ] 5.2 PR body carries the H-verdict + evidence; diff review confirms no retry-widening / no PEM-format change shipped.

## Phase 6 — Post-merge (operator)

- [ ] 6.1 Apply H1/H2 Doppler write (ack) OR H3 IaC apply, per verdict.
- [ ] 6.2 `inngest send cron/oauth-probe.manual-trigger`; confirm checkins API returns `ok`.
- [ ] 6.3 `gh issue close <N>` AFTER recovery confirmed (PR body uses `Ref #N`, not `Closes #N`).
