# Tasks — feat-one-shot-3015-trigger-prod-build

Issue: #3015
Plan: `knowledge-base/project/plans/2026-04-29-chore-trigger-prod-build-after-doppler-correction-plan.md`

## Phase 1 — Pre-trigger verification (read-only)

- [x] 1.1 Confirm latest `web-platform-release.yml` run is success on `main`
  — verified 2026-04-29: 5 consecutive `success` runs, top
  `92e8b3d5` at 22:31:40Z. PR #3018 merged after but only touched
  `knowledge-base/`, no new path-trigger.
- [x] 1.2 Pull Sentry digest — verified 2026-04-29: 0 events for
  `feature:dashboard-error-boundary OR feature:supabase-validator-throw`
  over 24h. Pre-fix events `a3edfa6f`/`87ba1b0f` (TypeError: Unknown
  encoding: base64url) at 22:22:24Z were the originating regression
  PR #3017 fixed.
- [x] 1.3 Run `canary-bundle-claim-check.sh` — exit 1, `no JWT found in
  login chunk`. **False negative** — script's bundle-layout assumption
  is stale post-#3017's "Layer 2 promotion". JWT now lives in
  `/_next/static/chunks/8237-...js` and decodes to canonical
  `iss=supabase, role=anon, ref=ifsccnjhymdmidffkzhl`. Script gap +
  missing volume mount tracked by **#3033**.

## Phase 1.4 — No-op exit gate (deepen-pass)

- [x] 1.4 Exit triggered, Phase 2 skipped. Recovery attributed to
  PR #3017 auto-trigger (push-paths filter on `apps/web-platform/**`),
  release run `92e8b3d5` completed 2026-04-28 22:31:40Z, swap at
  22:37:08Z. Sentry clean + manual JWT decode is the alternative
  evidence for Phase 1.3's false-fail.

## Phase 2 — Trigger build (contingent on Phase 1.2 OR 1.3 finding fault)

Decision matrix (Plan §Phase 2):

| Sentry events | Claim-check | Action |
|---|---|---|
| 0 / pre-#3014 | pass | Phase 1.4 exit |
| present, recent | pass | STOP — re-open H3/H6 hypothesis |
| 0 / pre-#3014 | fail | CDN purge first; re-run 1.3 |
| present | fail | Proceed to Phase 2 |

- [x] 2.1 N/A (Phase 1.4 exit, Phase 2 skipped — no Doppler change needed).
- [x] 2.2 N/A (Phase 1.4 exit, Phase 2 skipped — no GH secret change needed).
- [x] 2.3 N/A (Phase 1.4 exit, Phase 2 skipped — recovery delivered by
  organic auto-trigger from PR #3017).
- [x] 2.4 N/A (no Phase 2, no rollback needed; Phase 3 confirms recovery).

## Phase 3 — Render-time verification (always runs)

- [x] 3.1 SSH `journalctl -u docker --since "2026-04-28 22:00:00"
  --until "2026-04-28 22:50:00"` shows `Canary OK` + `Canary passed,
  swapping to production` + `Deploy succeeded` + deploy-status JSON
  `{"exit_code":0,"reason":"ok","tag":"v0.58.2"}` at 22:37:08Z (deploy
  harness equivalent of `final_write_state 0 "ok"`). SSH worked first
  try via `~/.ssh/deploy_ed25519` against `root@135.181.45.178`.
- [x] 3.2 Playwright nav `https://app.soleur.ai/dashboard` → redirects
  to `/login` (auth gate working). Screenshot:
  `.playwright-mcp/3015-dashboard-redirect-login.png`. HTML lacks
  `data-error-boundary=`; body text lacks "Something went wrong /
  unexpected error"; zero console errors/warnings.
- [ ] 3.2b Signed-in render check — deferred to runbook D2 follow-up
  (synthetic auth fixture, separate effort).
- [x] 3.3 Re-run claim-check substituted by manual JWT decode of
  `/_next/static/chunks/8237-323358398e5e7317.js`: payload
  `{"iss":"supabase","ref":"ifsccnjhymdmidffkzhl","role":"anon",
  "iat":1773675703,"exp":2089251703}`, ref length 20 chars, no
  placeholder prefix → all four canonical assertions pass. Script-fix
  to make Layer 3 work natively against the post-#3017 layout
  tracked by #3033.
- [x] 3.4 Runbook Recovery Verification filled with concrete evidence;
  frontmatter `status` flipped to `closed: 2026-04-29`; Confirmed
  Root Cause section also filled (H1 — base64url decode TypeError,
  fixed by PR #3017's browser-safe decode + Layer 2 promotion).

## Phase 4 — Close follow-through

- [ ] 4.1 `gh issue close 3015 --comment <evidence summary>` — deferred
  to post-merge so the close comment can reference the merged PR.
- [ ] 4.2 Verify issue state via `gh issue view 3015 --json state` returns
  `CLOSED` — deferred to post-merge.

## Discovered side-effects

- **#3033 filed:** Layer 3 canary claim-check is silently skipped in CI
  (volume mount missing) AND its bundle-layout assumption is stale
  post-#3017. Both gaps were invisible until #3015 verification.

## Notes

- PR body MUST use `Ref #3015` (not `Closes #3015`) per AGENTS.md
  `wg-use-closes-n-in-pr-body-not-title-to` ops-remediation extension.
- Every Phase 2 / Phase 3.1 command is destructive or sensitive prod read;
  per-command ack required (AGENTS.md `hr-menu-option-ack-not-prod-write-auth`).
