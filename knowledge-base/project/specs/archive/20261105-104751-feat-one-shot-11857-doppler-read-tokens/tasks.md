# Tasks: mint Doppler read tokens for three configs and raise the config floor to 16

Plan: `knowledge-base/project/plans/2026-11-04-infra-mint-doppler-read-tokens-and-raise-config-floor-plan.md`
Branch: `feat-one-shot-11857-doppler-read-tokens` | Draft PR #12100 | Ref #11857, Ref #10205

Hard limits (binding): the run ends at a DRAFT, UNARMED PR. No workflow dispatch, no terraform against remote state or
Doppler, no Doppler value read, no token mint, no tracker edit. Local `terraform fmt -check` only.

## Phase 0 - read-only preflight

- 0.1 Re-measure the inventory count before editing (`grep -E '^[a-z0-9_]+$' apps/web-platform/infra/doppler-config-inventory.txt | sort -u | wc -l` prints 13).
- 0.2 Re-run the open code-review overlap query over the final file list and record it in the plan.
- 0.3 Read the `on:`/`paths:`/`types:` blocks of every workflow in `.github/workflows/`, in particular `infra-validation.yml`, `apply-sentry-infra.yml`, `apply-deploy-pipeline-fix.yml` and `web-platform-release.yml`. Record whether any applies infrastructure or spends money from a feature-branch push or pull_request. Push only if none does.
- 0.4 Confirm `closingIssuesReferences` of #12100 is `[]`.
- 0.5 Confirm the body of issue #11857 lists the three names literally and quote it in the PR body.

## Phase 1 - RED (tests first)

- 1.1 `plugins/soleur/test/token-drift-workflow-causes.test.sh`: set `FLOOR_MINIMUM=16` in place, change the nine `"configs_floor":13` fixture literals to 16, fix the T6/T20 expectations and invert the T17 message (lowered floors 15 and 0); keep every edit line-count-neutral (the suite is cited at `:3`, `:55`, `:56`, `:1218` by `scripts/lib/test-affected-paths.sh`). Run the suite and record the failing assertions.
- 1.2 `plugins/soleur/test/terraform-target-parity.test.ts`: add Guard 1 (scan-derived row near the #9438 test) with its non-vacuity floor. Run it and record that it fails.

## Phase 2 - GREEN

- 2.1 Append `prd_git_data`, `prd_workspaces_luks_marker`, `prd_workspaces_luks_web` to `apps/web-platform/infra/doppler-config-inventory.txt` (bare lines, sorted position).
- 2.2 `apps/web-platform/infra/token-drift-read-tokens.tf`: add `depends_on = [doppler_config.workspaces_luks_web, doppler_config.workspaces_luks_marker]` with a comment; no edge to `doppler_config.git_data_prd`.
- 2.3 `.github/workflows/scheduled-terraform-drift.yml`: exactly three hunks - the token_drift floor comment and `DOPPLER_CONFIGS_FLOOR`, the run-time `< 13` re-assertion and its warning text, `RUNG2_CONFIGS_FLOOR`. Measure the floor with the F3 expression first (expect 16).
- 2.4 Run and confirm green: `bash plugins/soleur/test/token-drift-workflow-causes.test.sh`, `bash scripts/check-cloudflare-token-drift.test.sh`, `bun test plugins/soleur/test/terraform-target-parity.test.ts`, `bash scripts/check-web-host-escrow-config.test.sh`, `bash scripts/cf-tunnel-liveness-gate-mutations.test.sh`, `bash plugins/soleur/test/c4-count-parity.test.sh`, `terraform -chdir=apps/web-platform/infra fmt -check`.
- 2.5 Run the read-only affected-index ratchet (`python3 scripts/ci-pr-affected-replay.py ratchet`); if the new row created an unaccepted pair, remove the new path literal first, and only then add an accept row with a specific reason.
- 2.6 Run the discoverability probe `grep -c -e '^prd_git_data' -e '^prd_workspaces_luks_marker' -e '^prd_workspaces_luks_web' apps/web-platform/infra/doppler-config-inventory.txt` and confirm it prints 3.

## Phase 3 - comments and records

- 3.1 Rewrite the live comments that become false: inventory header (floor checklist, SE-4 paragraph, expected-to-drift, re-verified paragraph; stamp unchanged), `.tf` header (one dated sentence) and SE-4 paragraph, two comments in `workspaces-luks-fresh-boot.tf`, one sentence in `git-data.tf` (keep the local), P17 comment in `scripts/check-cloudflare-token-drift.test.sh`.
- 3.2 ADR-168: dated 2026-11-04 amendment under Known limitations. ADR-263: Superseded 2026-11-04 blockquote after the "deliberately not edited" sentence.
- 3.4 Sweep survivors: `rg -n '\b13\b|thirteen'` over the edited files; each remaining hit must be history, an illustrative ratio or unrelated. List them for the PR body.
- 3.5 Confirm lines 3, 55, 56 and 1218 of `token-drift-workflow-causes.test.sh` still hold the text `scripts/lib/test-affected-paths.sh` cites.

## Phase 4 - review and ship prerequisites

- 4.1 Review gates include `soleur:engineering:review:user-impact-reviewer` (threshold single-user incident) and the observability reviewer.
- 4.2 Commit; push only after 0.3 passes; the PR stays a DRAFT, auto-merge not armed.

## Phase 5 - PR body (owner-facing)

- 5.1 First line: merging this PR is itself the production change - the infra apply it triggers creates three Doppler read tokens.
- 5.2 Lead with what it does and its worst case. "Needs you": one item tagged `(operator: production-mutating)` - the merge, `gh pr merge 12100 --squash`. "What the agents already decided": the CTO rulings, the CPO advisory, the deviation from the issue text on the `git_data_prd` edge, the survivors list from 3.4.
- 5.3 `Ref #11857` and `Ref #10205` only; verify `closingIssuesReferences` is `[]` before saving.
