---
title: "Tasks — fix(infra): mint write-capable Doppler service token for apply-web-platform-infra sync step"
date: 2026-05-20
issue: 4195
lane: single-domain
plan: knowledge-base/project/plans/2026-05-20-fix-one-shot-doppler-write-token-4195-plan.md
---

# Tasks — Doppler write-capable service token for sync step (#4195)

## Phase 1 — Setup / Preconditions

- 1.1 Verify `DOPPLER_TOKEN_WRITE` GH repo secret does NOT yet exist: `gh api repos/jikig-ai/soleur/actions/secrets/DOPPLER_TOKEN_WRITE --jq '.name' 2>&1 | head -3` should return HTTP 404.
- 1.2 Confirm `var.doppler_token_tf` is workplace-scope (read `apps/web-platform/infra/variables.tf:137`).
- 1.3 Confirm Doppler provider 1.21.2 `access` enum is `{"read","read/write"}` (NOT `"write"`).

## Phase 2 — Core Implementation

- 2.1 Create `apps/web-platform/infra/doppler-write-token.tf` with `doppler_service_token.write` (access `"read/write"`, project `"soleur"`, config `"prd_terraform"`, name `"ci-tf-write"`) and `github_actions_secret.doppler_token_write` (repository `"soleur"`, secret_name `"DOPPLER_TOKEN_WRITE"`, plaintext_value `doppler_service_token.write.key`). Header comment mirrors `apps/web-platform/infra/kb-drift.tf:1-33`.
- 2.2 Edit `.github/workflows/apply-web-platform-infra.yml` apply allow-list (lines 197-274) — append `-target=doppler_service_token.write` and `-target=github_actions_secret.doppler_token_write` after the sibling `kb_drift` targets.
- 2.3 Edit `.github/workflows/apply-web-platform-infra.yml` sync step (lines 312-345):
  - 2.3.1 Add new step `Verify DOPPLER_TOKEN_WRITE present` before the sync step; emit `::warning::` + `skip_sync=true` when empty (bootstrap-cycle guard).
  - 2.3.2 Gate sync step with `if: steps.doppler_write_check.outputs.skip_sync != 'true'`.
  - 2.3.3 Change `DOPPLER_TOKEN: ${{ secrets.DOPPLER_TOKEN }}` to `DOPPLER_TOKEN: ${{ secrets.DOPPLER_TOKEN_WRITE }}` (sync step env only).
  - 2.3.4 Remove `>/dev/null 2>&1` redirect from both `doppler secrets set CI_SSH_ACCESS_TOKEN_*` lines (keep `--silent --no-interactive`).
- 2.4 Edit `apps/web-platform/infra/scripts/sync-ci-ssh-access-token.sh` header (lines 1-12): replace "fallback IS the canonical path" implication with "Use this script only for local reprovisioning after a workstation `terraform apply`. The canonical CI path now works (#4195)."

## Phase 3 — Verification (Pre-merge)

- 3.1 Run `cd apps/web-platform/infra && terraform init -input=false` (after exporting AWS R2 backend creds from Doppler `prd_terraform`).
- 3.2 Run `doppler run -p soleur -c prd_terraform --name-transformer tf-var -- terraform validate` — expect `Success! The configuration is valid.` (this catches the `"write"` vs `"read/write"` enum trap).
- 3.3 AC1: grep proves both new resources in the new file (`grep -nE 'resource "doppler_service_token" "write"|resource "github_actions_secret" "doppler_token_write"' apps/web-platform/infra/doppler-write-token.tf | wc -l` returns `2`).
- 3.4 AC3: grep proves both new resources in the apply allow-list (`grep -nE 'target=doppler_service_token\.write|target=github_actions_secret\.doppler_token_write' .github/workflows/apply-web-platform-infra.yml | wc -l` returns `2`).
- 3.5 AC4: awk-range proves sync step env uses `DOPPLER_TOKEN_WRITE` and not the bare `DOPPLER_TOKEN` (precision-anchor pattern per `2026-05-15-plan-ac-verification-commands-awk-self-match-and-marker-conjunction.md`).
- 3.6 AC5: full-workflow grep proves other 19 references to `secrets.DOPPLER_TOKEN[^_]` are unchanged.
- 3.7 AC6 + AC7: grep proves bootstrap guard present AND redirect removed.
- 3.8 AC8: grep proves script header refresh.

## Phase 4 — Knowledge Capture

- 4.1 Write `knowledge-base/project/learnings/` learning file (topic: doppler-write-token-bootstrap-cycle-and-access-enum) with YAML frontmatter (`title`, `date`, `category: integration-issues`, `tags: [doppler, terraform, github-actions, service-tokens, bootstrap]`) and three sections: (a) access enum, (b) bootstrap cycle, (c) precedent reference.

## Phase 5 — PR + Post-merge Verification

- 5.1 PR body includes `Closes #4195`, the pre-fix grep count from AC5 (19 matches), and an operator note about the bootstrap-cycle re-fire (AC11/AC12).
- 5.2 Apply auto-fires on merge (paths-filter matches `apps/web-platform/infra/**`). Operator approves the environment gate. First apply may emit a sync-step warning (bootstrap-cycle); this is expected.
- 5.3 AC11: confirm `gh api repos/jikig-ai/soleur/actions/secrets/DOPPLER_TOKEN_WRITE --jq '.name'` returns `"DOPPLER_TOKEN_WRITE"` post-first-apply.
- 5.4 AC12: operator re-fires via `gh workflow run apply-web-platform-infra.yml --ref main -F reason='post-#4195 bootstrap second apply'`; second run shows the sync step exit 0 with the `Synced …` log line.
- 5.5 AC13: `doppler secrets get CI_SSH_ACCESS_TOKEN_ID -p soleur -c prd_terraform --plain | head -c 8` returns non-empty 8 chars (verification that the second apply did not regress operator-restored values).
- 5.6 AC14: `gh issue close 4195 --comment "Resolved via PR #<N>. <run-url>"`.
