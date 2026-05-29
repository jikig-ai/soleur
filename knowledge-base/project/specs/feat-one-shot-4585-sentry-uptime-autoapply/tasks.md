---
title: "Tasks — extend apply-sentry-infra.yml auto-apply to sentry_uptime_monitor.*"
issue: 4585
branch: feat-one-shot-4585-sentry-uptime-autoapply
lane: single-domain
plan: knowledge-base/project/plans/2026-05-29-infra-extend-sentry-autoapply-to-uptime-monitors-plan.md
---

# Tasks — #4585 extend sentry auto-apply to uptime monitors

## Phase 0 — Preconditions (read + grep, no edits)

- [x] 0.1 Confirm 4 resource addresses: `grep -nE 'resource "sentry_uptime_monitor"' apps/web-platform/infra/sentry/uptime-monitors.tf` → `soleur_apex`, `soleur_www`, `soleur_changelog_deep`, `soleur_acme_probe`.
- [x] 0.2 Confirm zero nested blocks: `grep -oE '^\s+[a-z_]+\s*=' apps/web-platform/infra/sentry/uptime-monitors.tf | sed 's/[[:space:]=]//g' | sort -u` → all scalar.
- [x] 0.3 Confirm apply step applies saved `tfplan` (no `-target=` re-enumeration): read the "Terraform apply (cron monitors only)" step → `terraform apply -auto-approve -input=false tfplan`. (Already verified at deepen time.)
- [x] 0.4 Confirm `actionlint` available (`command -v actionlint`); else fall back to `bash -c` on extracted `run:` snippets.
- [x] 0.5 Open Code-Review Overlap probe (plan §Open Code-Review Overlap) — record matches + disposition or `None`.

## Phase 1 — Workflow edits (`.github/workflows/apply-sentry-infra.yml`)

- [x] 1.1 Add `- "apps/web-platform/infra/sentry/uptime-monitors.tf"` to the `paths:` block (alongside `cron-monitors.tf`; keep the `destroy-guard-filter-sentry.jq` defense-in-depth path). [AC3]
- [x] 1.2 Add 4 `-target=sentry_uptime_monitor.{soleur_apex,soleur_www,soleur_changelog_deep,soleur_acme_probe}` flags to the "Terraform plan" step, after the last cron target (line 194), before `-no-color -input=false -out=tfplan`. [AC1]
- [x] 1.3 Do NOT touch the apply step (it consumes the saved `tfplan` — plan-targets == apply-targets). [AC2]
- [x] 1.4 Update stale "cron monitors only" naming: `name:` (line 33), "Terraform plan" step name (line 164), "Terraform apply" step name (line 239), Post-apply summary header (line 257), file-header comment block (lines 1–15) → "cron + uptime monitors" (or equivalent). Preserve cron-rollout history comments verbatim. [AC4]

## Phase 2 — Destroy-guard comment sync (`tests/scripts/lib/destroy-guard-filter-sentry.jq`)

- [x] 2.1 Update CURRENT SCOPE comment to name `sentry_uptime_monitor.*` as in-scope + one sentence: uptime monitors expose zero array-of-blocks (all attrs scalar incl. `assertion_json` string), so `nested_deletes: 0` stays correct; uptime removal = resource-level delete caught by `resource_deletes`. [AC5]
- [x] 2.2 Do NOT change the jq expression; do NOT add `walk()` or a `select(.type == "sentry_uptime_monitor")` clause. [AC5]

## Phase 3 — Re-capture note sync (`tests/scripts/test-destroy-guard-counter-sentry.sh`)

- [x] 3.1 Append the 4 `-target=sentry_uptime_monitor.*` flags to the header "Re-capturing baseline" `terraform plan` example block (documentation accuracy; no test-logic / fixture change). [AC8]

## Phase 4 — Verify

- [x] 4.1 `grep -cE '^\s*-target=sentry_uptime_monitor\.' .github/workflows/apply-sentry-infra.yml` == 4. [AC1]
- [x] 4.2 `grep -cE '^\s*-target=sentry_cron_monitor\.' .github/workflows/apply-sentry-infra.yml` == 17 (unchanged). [AC1]
- [x] 4.3 `grep -A4 'name: Terraform apply' .github/workflows/apply-sentry-infra.yml | grep -q 'tfplan'`. [AC2]
- [x] 4.4 `grep -q 'apps/web-platform/infra/sentry/uptime-monitors.tf' .github/workflows/apply-sentry-infra.yml`. [AC3]
- [x] 4.5 No false "cron monitors only" / "(cron monitors)" scope literals remain (only cron-block-scoped historical comments allowed). [AC4]
- [x] 4.6 `bash tests/scripts/test-destroy-guard-counter-sentry.sh` → 5 passed / 0 failed. [AC6]
- [x] 4.7 `actionlint .github/workflows/apply-sentry-infra.yml` clean; `bash -c` on extracted `run:` snippets parses. [AC7]
- [x] 4.8 Full suite (`package.json scripts.test` / repo canonical runner) green. [AC9]

## Phase 5 — Post-merge (automated by pipeline / ship — NO operator action)

- [ ] 5.1 Confirm first auto-apply ran: `gh run list --workflow=apply-sentry-infra.yml --limit 1` + `gh run view <id> --log`. [AC10]
- [ ] 5.2 API-GET probe (NOT dashboard): `GET /api/0/organizations/${SENTRY_ORG}/monitors/` greps for the 4 slugs `soleur-ai-apex`, `soleur-ai-www`, `soleur-ai-changelog-deep`, `soleur-ai-acme-carveout-probe`. (Needs `SENTRY_IAC_AUTH_TOKEN` from GH repo secret.) [AC11]
- [ ] 5.3 PR body: use `Ref #4585` + post-merge `gh issue close 4585` after AC11 green (the apply runs post-merge; do NOT `Closes #4585` which would auto-close at merge before the apply verifies — per `wg-use-closes-n-in-pr-body-not-title-to`).
