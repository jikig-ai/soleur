# Tasks — read-only Better Stack token for the heartbeat live-reconcile (#6635)

Lane: single-domain · Threshold: none
Plan: `knowledge-base/project/plans/2026-07-18-chore-betterstack-readonly-token-reconcile-plan.md`

## Phase 0 — Preconditions
- [ ] 0.1 Confirm `BETTERSTACK_API_TOKEN_READONLY` is absent from Doppler `soleur/prd_terraform` (skip Phase 1 if a prior run already created it).
- [ ] 0.2 Confirm workflow anchors have not drifted: reconcile step reads `doppler secrets get BETTERSTACK_API_TOKEN` (~L293) and maps `BETTERSTACK_API_TOKEN="$TOKEN"` (~L299) into `reconcile-live-heartbeats.ts`.

## Phase 1 — Mint the Read-scoped token (Playwright-first)
- [ ] 1.1 Playwright-attempt the mint at `betterstack.com/settings/global-api-tokens`; create a **Read**-scoped token (automation-status: UNVERIFIED — attempt before any operator handoff; only a real CAPTCHA/OTP/TOTP/passkey/MFA gate with `playwright-attempt:` evidence justifies handoff).
- [ ] 1.2 Capture the minted value as a secret (never echo to logs).

## Phase 2 — Store in Doppler
- [ ] 2.1 Store the value as `BETTERSTACK_API_TOKEN_READONLY` in `soleur/prd_terraform` via the Doppler CLI (additive; direct store — NOT a `doppler_secret` TF resource; mirrors how `BETTERSTACK_API_TOKEN` lives there). If the local `dp.ct.` token lacks write auth, record the gate and hold the swap PR until provisioned.
- [ ] 2.2 Verify stored: `doppler secrets get BETTERSTACK_API_TOKEN_READONLY --plain` returns a value.

## Phase 3 — Verify Read scope authorizes the reconcile
- [ ] 3.1 Run `reconcile-live-heartbeats.ts` with the readonly token as `BETTERSTACK_API_TOKEN`; expect rc in {0, 2} (auth succeeded). rc=1 `reason=auth` → re-mint with the required scope. (Or bounded curl to `GET https://uptime.betterstack.com/api/v2/heartbeats` → expect 200.)

## Phase 4 — Swap the workflow
- [ ] 4.1 Edit `.github/workflows/scheduled-terraform-drift.yml` reconcile step: `doppler secrets get BETTERSTACK_API_TOKEN` → `doppler secrets get BETTERSTACK_API_TOKEN_READONLY` (~L293).
- [ ] 4.2 Update the adjacent comment (~L297) to note the Doppler source is the Read-scoped token; script env contract name unchanged.
- [ ] 4.3 Leave `BETTERSTACK_API_TOKEN="$TOKEN"` (~L299) unchanged — the script's `process.env.BETTERSTACK_API_TOKEN` contract.

## Phase 5 — Post-merge verification (no SSH)
- [ ] 5.1 `gh workflow run scheduled-terraform-drift.yml`; confirm the `heartbeat-live-reconcile` step reports rc in {0, 2}, not rc=1.
- [ ] 5.2 Close #6635 after the post-merge run is green (`Ref #6635` in PR body, not `Closes`).

## Verification (pre-merge AC)
- [ ] `grep -c 'doppler secrets get BETTERSTACK_API_TOKEN_READONLY' .github/workflows/scheduled-terraform-drift.yml` == 1
- [ ] `grep -c 'BETTERSTACK_API_TOKEN="$TOKEN"' .github/workflows/scheduled-terraform-drift.yml` == 1
- [ ] Reconcile step contains no read/write `get BETTERSTACK_API_TOKEN ` (trailing space) read.
- [ ] `bun test plugins/soleur/test/heartbeat-live-reconcile.test.ts` green.
- [ ] `actionlint .github/workflows/scheduled-terraform-drift.yml` clean.
