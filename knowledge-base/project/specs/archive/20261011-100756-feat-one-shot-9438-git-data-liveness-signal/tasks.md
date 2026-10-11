---
feature: feat-one-shot-9438-git-data-liveness-signal
plan: knowledge-base/project/plans/2026-10-10-feat-git-data-host-recurring-liveness-signal-plan.md
issue: 9438
lane: cross-domain
---

# Tasks: git-data host recurring liveness signal (#9438)

Spec lacks a valid `lane:` (no spec.md for this branch), so it defaults to `cross-domain` (fail-closed). This PR uses `Refs #9438`,
`Refs #8211`, `Refs #8093`; never `Closes`. Targeted suites only. Do not touch `git-data-gc.sh`, `.gc-cursor`, PR #9466's worktree or
the main checkout's `.mcp.json`. Nothing here performs or dispatches a replace, a rehearsal, an arm, or any workflow.

## Phase 0 - Measure (read-only)

- 0.1 Re-run `bash apps/web-platform/infra/git-data-userdata-budget.sh --json`; record headroom (6788 B at plan time)
- 0.2 Baseline `bash plugins/soleur/test/c4-count-parity.test.sh` and `python3 -I scripts/lint-encryption-posture.py`
- 0.3 Read the git-data pair rows in `plugins/soleur/test/terraform-target-parity.test.ts` and pin the classification the new pair needs
- 0.4 `git grep -l prd_git_data` and sweep for a "two secrets" cardinality assumption
- 0.5 Bump `BASELINE_DECLARED_PROBES` 53 to 54 in `plugins/soleur/test/preflight-discoverability-test.test.ts` with the
  PLACEMENT / TRUTH / NO-SUBSTITUTE comment

## Phase 1 - Tests first

- 1.1 Create `apps/web-platform/infra/git-data-liveness.test.sh` (fakes on PATH for the service manager, `mountpoint`, `findmnt`, `df`,
  the loopback banner read, `curl`, `doppler`, an emit spy)
  - 1.1.1 Every gating check passes and fails; thresholds one below, at, one above
  - 1.1.2 URL shape guard; URL absent from every argv and every emitted line; xtrace refusal
  - 1.1.3 Production config versus rehearsal config (exact equality) on an absent secret; empty cache retried every tick; cache
    dropped on a ping failure; `doppler` exiting 0 with empty output
  - 1.1.4 Transition emit, 10-minute `ok` summary, failed emit still exits 0 and retries next tick, hung `doppler` and hung emit stay
    under 55 s, `unmeasured` on an empty `df`, `HOME=/root` in the unit
- 1.2 Write the Guard Contract mutation matrix rows 1 to 18 and harness rows H1 to H5 as runnable cases before the script exists
- 1.3 Add the manifest row and parity rows (RED until the TF pair and the cloud-init arming line exist)
- 1.4 Regenerate the infra shard manifest (`python3 scripts/regenerate-shard-manifest.py --group infra --incremental --write`), then
  `bash scripts/lint-orphan-test-suites.sh` once the suite file is tracked

## Phase 2 - Payload (hash-bound)

- 2.1 Create `git-data-liveness.sh`, `git-data-liveness.service`, `git-data-liveness.timer`
- 2.2 Bind the three in `modules/git-data-userdata/main.tf` (exact `file("${path.module}/../../...")` spelling, one line each, with
  `local.git_data_rationale_strip`); mirror them in `git-data-userdata-budget.sh`
- 2.3 `cloud-init-git-data.yml`: three `write_files` entries and one runcmd item AFTER the `gc_timer` item, `_rc` capture-and-`if`
  shape, `info` emit on failure, arming line spelled like the registry row's manifest pattern; no `warning` or `fatal` stage
- 2.4 Comment-only edits to `git-data-pre-receive.sh` (hash-bound) and `git-data-pre-receive-placeholder.sh` (inert)
- 2.5 Add the three payloads to `EXPECTED_PATHS` in `git-data-runcmd-rehearsal.test.sh`; add the feeder to `p_doppler_config_scope`
  in `git-data-luks.test.sh`; add the new service and timer to the `infra-validation.yml` unit-lint list and alternation
- 2.6 Delete `apps/web-platform/infra/git-data-rung2-boot-evidence.env`

## Phase 3 - Terraform, manifest, target list

- 3.1 `git-data.tf`: `betteruptime_heartbeat.git_data_host_prd` (paused, `ignore_changes=[paused]`, `push = false`) and
  `doppler_secret.git_data_host_heartbeat_url_prd` (literal `project` and `config`); update the liveness comment block
- 3.2 `git-data-luks.tf`: update the CARDINALITY comment (three secrets)
- 3.3 `heartbeat-manifest.ts`: row `git_data_host_prd` with `arming_pending: { tracking_issue: 9438 }`
- 3.4 `apply-web-platform-infra.yml`: two per-merge `-target` lines only; `terraform-target-parity.test.ts`: pair row,
  `GIT_DATA_BIRTH_REFUSED`, direct-reference pin
- 3.5 Validate workflow edits by `actionlint` and the parity tests only; never dispatch; never `--admin` merge

## Phase 4 - Runbook, ADR, C4

- 4.1 Runbook `git-data-luks-cutover-5274.md`: hard precondition item, "Liveness heartbeat" section, soak, failure branch, flip-time
  re-read, replace-window text, pre-replace read, rung-2 window owner and cap, decision table for every state and code
- 4.2 Create ADR-283 via `soleur:architecture` (status `adopting`); one-line pointers in ADR-103 and ADR-198; re-verify the ordinal
  across every `origin/*` ref
- 4.3 `model.c4` edge and container sentences; run the C4 syntax, render and count-parity tests

## Phase 5 - Verify (targeted)

- 5.1 Run the suites listed under Quality Gates in the plan
- 5.2 `git diff --name-only origin/main...HEAD` shows none of: `git-data-gc.sh`, `.gc-cursor`, `arm-heartbeats.sh`,
  `arm-heartbeats.test.sh`, the parked worktree, `.mcp.json`
- 5.3 Record the stored `user_data` headroom in the PR body
- 5.4 Ship: step 5.5 (`archive-kb.sh`) BEFORE arming auto-merge; PR body `Refs` only, lists the two merge-time production writes and
  the rung-2 window

## Follow-on PRs and owner-gated steps (not in this PR)

- PR 1b: `--status` and `--arm-one` in `arm-heartbeats.sh` with tests and the runbook arm section (refuse on an address absent from
  state; deadline 320; local TFSTATE producer command; sweep after a cancelled run). Tracked on #9438
- Owner-authorized: rehearsal dispatch on `main`, evidence-only PR, host replace with rotation, pre-replace and pre-arm reads, arm
- Dependent record PR: remove `arming_pending`, tick the runbook, refresh the ledger row, cite one delivered incident, `Closes #9438`
- #9943: machine-enforce the precondition in the cutover workflow
