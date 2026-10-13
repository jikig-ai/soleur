---
title: "Tasks — fix workspaces-luks cutover SSH bridge dry-run guard"
plan: knowledge-base/project/plans/2026-07-18-fix-workspaces-luks-cutover-ssh-bridge-dryrun-guard-plan.md
branch: feat-one-shot-cutover-ssh-bridge-dryrun-guard
lane: single-domain
issue: 6649
---

# Tasks

## Phase 1 — Fix the guard (workflow-YAML-only)

- [x] 1.1 In `.github/workflows/workspaces-luks-cutover.yml`, delete the line
  `if: ${{ !inputs.dry_run || inputs.rollback }}` from the `CF Tunnel SSH bridge` step (line 86).
- [x] 1.2 Rewrite the step's leading comment (line 85) to state the bridge runs on EVERY invocation
  because the run step always SSHes to web-1 (private 10.0.1.10) and the escrow probe runs on web-1
  in the dry-run arm before the DRY_RUN freeze gate (reference run 29644526137). Keep the comment
  free of H7 cred tokens (AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY / WORKSPACES_HEADER_R2_* /
  WORKSPACES_HEADER_BUCKET).
- [x] 1.3 Confirm the `Run workspaces-luks cutover` step is untouched (still unconditional; still
  `< "${INFRA_DIR}/workspaces-cutover.sh"`).

## Phase 2 — Verify (do NOT expand scope)

- [x] 2.1 `grep -c 'if: ${{ !inputs.dry_run || inputs.rollback }}' .github/workflows/workspaces-luks-cutover.yml` → `0` (AC1).
- [x] 2.2 `bash apps/web-platform/infra/workspaces-luks-header.test.sh` → passes (AC6).
- [x] 2.3 `bash apps/web-platform/infra/web-1-swap-concurrency-parity.test.sh` → passes (AC7).
- [x] 2.4 `actionlint .github/workflows/workspaces-luks-cutover.yml` clean (fallback: python yaml.safe_load exits 0). Never `bash -n` a workflow file (AC8).
- [x] 2.5 `git diff --name-only origin/main` lists ONLY the workflow file + this plan/spec artifact set — no `git-data-cutover.yml`, no `workspaces-cutover.sh`, no `*.tf` (AC4, AC5).

## Phase 3 — Ship

- [ ] 3.1 PR body: `## Changelog` section; `Ref #6649` (NOT `Closes #6649` — closure gated on the
  post-merge green dry-run re-run); `semver:patch` label (bug fix); do not reference #6604 for closure.
- [ ] 3.2 After merge (AC10, performed by the rehearsal runner, not this PR):
  `gh workflow run workspaces-luks-cutover.yml -f confirm=CUTOVER-WORKSPACES-LUKS -f dry_run=true`,
  then `gh run view <id> --log` — confirm the run reaches `Run workspaces-luks cutover` with no
  `Connection timed out`, and shows a GREEN `escrow probe OK`. Then close #6649.
