# Tasks: git-data-cutover CI access path (#6680, ADR-220)

Plan: `knowledge-base/project/plans/2026-09-14-fix-git-data-cutover-ci-access-path-plan.md`

## Phase 0: Preconditions

- [ ] 0.1 Re-derive the next free ADR ordinal across every pushed ref (219 was the max on 2026-09-14)
- [ ] 0.2 File the follow-up issue (root key + Doppler `prd_git_data_root` + window-scoped token + reviewer-gated environment + gate allow-sets + #8009 C1 re-approval + PA-36 update + replace; blocked by walls 4–6; gated on #7226 for populated-store rotation)
- [ ] 0.3 File wall 4 (read_flag/set_flag under a prd_terraform-scoped token)
- [ ] 0.4 File wall 5 (cutover serializes against neither web-1-swap nor git-data-state)
- [ ] 0.5 File wall 6 (ROLLBACK never releases a freeze on a default dry_run=true dispatch)

## Phase 1: Tests first (RED)

- [ ] 1.1 Create `apps/web-platform/infra/git-data-cutover-access.test.sh` with `PATH`-shimmed `ssh`/`doppler` and synthesized keys
  - [ ] 1.1.1 Guard 1 mutation rows 1–8 and harness rows H1–H4 (forward-path cases run with `GIT_DATA_SSH` set)
  - [ ] 1.1.2 Guard 2 rows 1–4 and H1–H2 (extract the bridge decode body by YAML parse; both branches)
  - [ ] 1.1.3 Test scenarios 1–10 incl. banner-with-rc=124 → ok and ROLLBACK flag-off ordering under DRY_RUN=0/1
- [ ] 1.2 Confirm the behavioral cases are RED against origin/main bytes
- [ ] 1.3 Register the suite in `.github/workflows/infra-validation.yml`

## Phase 2: Script

- [ ] 2.1 `gd_ssh`/`web_ssh`: drop `:-ssh` fallbacks; unset → stderr message + return 97
- [ ] 2.2 `access_gate`: web probe per roster member (external `timeout`, BatchMode/ConnectTimeout appended), jump banner probe via `$WEB_HOST_SSH -W`, auth (`git_data_root_key_absent` when `GIT_DATA_SSH` unset); exit 3; annotations carry role/verdict only
- [ ] 2.3 `main()`: `access_gate` as the first plain statement of the forward path; ROLLBACK order unchanged
- [ ] 2.4 Update the INVOCATION BOUNDARY header; remedy line cites the follow-up issue
- [ ] 2.5 Run the new suite + `git-data-luks.test.sh`

## Phase 3: Bridge + workflow

- [ ] 3.1 Bridge: delete the `GIT_DATA_SSH=` export; update the `server-ip` description and OUTPUTS header
- [ ] 3.2 Workflow: `WEB_HOST_PRIVATE_IP` env → `server-ip` + Run `WEB_HOSTS`; teardown step after Run (before summary); header rewrite; no new secret reference
- [ ] 3.3 Run check-cloudflare-token-drift, cf-tunnel-liveness-gate-mutations, workspaces-luks-cutover-workflow, workspaces-luks-verify-workflow, workspaces-luks-header, web-1-swap-concurrency-parity, lint-workflow-step-env-refs, actionlint, terraform-target-parity

## Phase 4: Live transport measurement

- [ ] 4.1 Push; dispatch the branch's `git-data-cutover.yml` with `dry_run=true` and arm a watch in the same turn
- [ ] 4.2 Assert web ok, git-data-jump ok, git-data-auth git_data_root_key_absent; any other result halts the PR

## Phase 5: ADR, ADR-068 note, runbook, C4

- [ ] 5.1 `/soleur:architecture` → ADR-220 (decisions 1–6, separate statuses, rejected table, residuals)
- [ ] 5.2 ADR-068: dated note under addendum D10
- [ ] 5.3 Runbook dry-run step: one line on the expected stop
- [ ] 5.4 `model.c4`: `github -> gitDataStore` edge (transport live, credential target); views include if needed; run c4 tests + count parity
- [ ] 5.5 `lint-infra-no-human-steps.py --changed --base origin/main`

## Phase 6: Invariance and ship prep

- [ ] 6.1 AC9: no hash-bound, evidence or `.tf` diff; rung-2 gate still RELEASED 5c50797be839…
- [ ] 6.2 `git merge-tree --write-tree origin/main HEAD` clean before review and before `gh pr ready`
- [ ] 6.3 PR body: `Ref #6680`, no infra applied on merge, follow-up issue named
