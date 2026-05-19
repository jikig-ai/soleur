---
issue: 4029
type: security-remediation
classification: ops-only-prod-write
threshold: single-user-incident
brand_survival_threshold: single-user-incident
requires_cpo_signoff: true
lane: cross-domain
date: 2026-05-18
status: draft
plan: ../../plans/2026-05-18-security-rotate-x-api-secret-and-widen-doppler-stdout-trap-plan.md
---

# Spec — rotate X_API_SECRET and widen the doppler-stdout-echo trap

## Summary

Issue #4029 is a follow-up to PR #3983. The post-merge cleanup ran `doppler secrets delete SUPABASE_JWT_SECRET -c prd --yes` and `doppler secrets delete SUPABASE_MGMT_API_TOKEN_DEV -c dev --yes`; both invocations echoed the **post-deletion surviving-secrets table** to stdout, dumping value chunks of `X_API_SECRET` (X/Twitter OAuth consumer secret) into the Soleur development conversation transcript. The leaked chunks are large enough that `X_API_SECRET` must be treated as compromised.

This spec covers three remediation layers, shipped in one PR:

1. **L1 — Rotate the compromised credential.** Operator regenerates at the X Developer Portal → captures via Playwright `browser_evaluate(filename:)` no-leak pattern → writes to Doppler `prd` + GitHub Actions repo secret. Runs **post-merge** via `scripts/rotate-x-api-secret-bootstrap.sh`.

2. **L2 — Widen the trap-class hook.** `.claude/hooks/prod-write-defer-gate.sh` regex widened from `doppler secrets set` / `(prd|prd_terraform)` to `doppler secrets (set|delete)` / `(prd|prd_terraform|dev|ci)`. Rule renamed `prod-write-defer-doppler-prd-secrets` → `prod-write-defer-doppler-secrets-stdout`. Read-only escape entry added for `--help` / `-h`.

3. **L3 — Update guidance.** Amend the Leak-2 learning (corrects the empirically-false "no `--silent` flag exists" claim); update the hook README starter manifest; sweep operator-facing runbooks (`stripe-live-activation.md`, `tenant-offboarding.md`, `tenant-provisioning.md`, `github-app-drift.md`) so every `doppler secrets {set,delete}` invocation pairs `--silent` with `>/dev/null 2>&1`.

## Acceptance Criteria

See plan §Acceptance Criteria. Pre-merge gates: AC1–AC7 (hook + tests + docs + plan-files + PR body). Post-merge gates (operator-driven via bootstrap script): AC8–AC15 (regenerate + Doppler write + GH write + verify + cron smoke + shred + issue close + scope-out tracking issue).

## Brand-Survival Threshold

`single-user-incident`. The Soleur X handle is a single brand-survival surface; impersonation or hostile takeover at alpha scale is brand-ending. CPO sign-off required at plan-time; `user-impact-reviewer` will be invoked at review-time per AGENTS.md `hr-weigh-every-decision-against-target-user-impact`.

## Closure Pattern

PR body uses `Ref #4029`, NOT `Closes #4029`. Auto-close at merge would produce false-resolved state because the actual rotation runs post-merge. Operator runs `gh issue close 4029` after the bootstrap script confirms all post-merge ACs.

## Non-Goals

- No Terraform / IaC changes (X_API_* secrets are pre-Doppler-IaC vintage; scope-out tracking issue filed via AC15).
- No consumer-side code changes (`plugins/soleur/skills/community/scripts/x-*.sh`, `.github/workflows/scheduled-content-publisher.yml` are correct as-written).
- No test-fixture changes (`test/x-community.test.ts:65` carries literal value `"test"`, unaffected by production rotation).
