# Tasks: git-data-cutover CI access path (#6680, ADR-220)

Plan: `knowledge-base/project/plans/2026-09-14-fix-git-data-cutover-ci-access-path-plan.md`

## Phase 0: Preconditions

- [x] 0.1 Re-derive the next free ADR ordinal across every pushed ref (219 was the max on 2026-09-14)
- [x] 0.2 Filed #8189 — the follow-up issue (root key in a SEPARATE Terraform root — private half never readable by web-platform-state readers; Doppler `prd_git_data_root`; OIDC-first environment-bound read credential, else repo secret + single-reference lint + main-only policy + mint-time expiry; reviewer-gated environment; gate allow-sets; #8009 C1 re-approval; PA-36 update; replace; blocked by walls 4–6; #7226 host-key pinning precedes the credential decision's accepted status)
- [x] 0.3 (folded into #8189 as a blocking checklist item — not filed separately) wall 4 (read_flag/set_flag under a prd_terraform-scoped token)
- [x] 0.4 (folded into #8189 as a blocking checklist item — not filed separately) wall 5 (cutover serializes against neither web-1-swap nor git-data-state)
- [x] 0.5 (FIXED inline in this PR: release_freeze --ignore-dry-run; not filed) wall 6 (ROLLBACK never releases a freeze on a default dry_run=true dispatch)

## Phase 1: Tests first (RED)

- [x] 1.1 Create `apps/web-platform/infra/git-data-cutover-access.test.sh` with `PATH`-shimmed `ssh`/`doppler` and synthesized keys
  - [x] 1.1.1 Guard 1 mutation rows 1–10 and harness rows H1–H5 over a single `$TL` timeline (ssh/doppler/timeout shims), forward-path cases with `GIT_DATA_SSH` set; H5 structural plain-statement check
  - [x] 1.1.2 Guard 2 rows 1–5 and H1–H2 (extract the bridge decode body by YAML parse; parse NAME=value and NAME<<DELIM forms; both branches)
  - [x] 1.1.4 Docker runtime arm R1–R4 (pinned UBUNTU_BASE from git-data-ownership.test.sh; CI=true skip is a failure); save real stderr as shim fixtures
  - [x] 1.1.3 Test scenarios 1–17 (banner first-line rule, invalid_host, web_host_ssh_unset, forged workflow commands, notice/error levels, EXIT-trap re-exit, ROLLBACK flag-off ordering under DRY_RUN=0/1)
- [x] 1.2 Confirm the behavioral cases are RED against origin/main bytes
- [x] 1.3 Register the suite in `.github/workflows/infra-validation.yml`

## Phase 2: Script

- [x] 2.1 `gd_ssh`/`web_ssh`: drop `:-ssh` fallbacks; unset → stderr message + return 97
- [x] 2.2 `access_gate`: `read -ra` arrays, host validation `^[0-9.]+$` (`invalid_host`), `web_host_ssh_unset`, web probe per roster member (external `timeout 30`, BatchMode/ConnectTimeout appended), jump banner probe `$WEB_HOST_SSH -W host:22 <first member> </dev/null` (ok iff first line begins SSH-2.0-), auth probe; `out=$(…) || rc=$?`; exit 3; `::notice` for ok, `::error` otherwise; probe stdout/stderr to files; stderr printed only inside a random stop-commands span after `LC_ALL=C tr -cd '\40-\176'`; verdicts appended to `$GITHUB_STEP_SUMMARY`
- [x] 2.2.1 ROLLBACK/`release_freeze` `|| log WARNING` arms also emit `::warning title=git-data-cutover recovery::step=<name> rc=<n>`
- [x] 2.3 `main()`: `access_gate` as the first plain statement of the forward path; ROLLBACK order unchanged
- [x] 2.4 Update the INVOCATION BOUNDARY header; remedy line cites the follow-up issue
- [x] 2.5 Run the new suite + `git-data-luks.test.sh`

## Phase 3: Bridge + workflow

- [x] 3.1 Bridge: delete the `GIT_DATA_SSH=` export; update the `server-ip` description and OUTPUTS header
- [x] 3.2 Workflow: `WEB_HOST_PRIVATE_IP` env → `server-ip` + Run `WEB_HOSTS`; teardown step after Run (before summary); header rewrite incl. correcting the false Inngest-dispatch paragraph; no new secret reference
- [x] 3.3 Run check-cloudflare-token-drift, cf-tunnel-liveness-gate-mutations, workspaces-luks-cutover-workflow, workspaces-luks-verify-workflow, workspaces-luks-header, web-1-swap-concurrency-parity, lint-workflow-step-env-refs, actionlint, terraform-target-parity

## Phase 4: Live transport measurement

- [x] 4.1 Push; dispatch the branch's `git-data-cutover.yml` with `dry_run=true rollback=false confirm_wipe=false` and arm a watch in the same turn
- [x] 4.2 (run 34906907089: web ok, jump ok, auth git_data_root_key_absent, exit 3) Assert web ok, git-data-jump ok, git-data-auth git_data_root_key_absent; any other result halts the PR

## Phase 5: ADR, ADR-068 note, runbook, C4

- [x] 5.1 `/soleur:architecture` → ADR-220 (decisions 1–6, separate statuses, rejected table, residuals)
- [x] 5.2 ADR-068: dated note under addendum D10
- [x] 5.3 Runbook dry-run step: one line on the expected stop
- [x] 5.4 `model.c4`: `github -> gitDataStore` edge (transport live, credential target); views include if needed; run c4 tests + count parity
- [x] 5.5 `lint-infra-no-human-steps.py --changed --base origin/main`

## Phase 6: Invariance and ship prep

- [x] 6.1 AC9: no hash-bound, evidence or `.tf` diff; rung-2 gate still RELEASED 5c50797be839…
- [x] 6.2 `git merge-tree --write-tree origin/main HEAD` clean before review and before `gh pr ready`
- [ ] 6.3 PR body: `Ref #6680`, no infra applied on merge, follow-up issue named
