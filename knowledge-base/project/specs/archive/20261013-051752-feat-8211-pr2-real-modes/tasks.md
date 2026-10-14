# Tasks: feat-8211-pr2-real-modes (#8211 PR2 — the real modes)

Plan: `knowledge-base/project/plans/2026-09-29-feat-git-data-cutover-pr2-real-modes-plan.md`
Parent plan (PR1, merged): `knowledge-base/project/plans/2026-09-22-feat-git-data-cutover-real-modes-plan.md`

## 1. Setup

- 1.1 Re-verify the #8573 flag-write seam interface (credential name + mechanism). Until it
  exists, the plan's `flag_write_credential_absent` verdict is the honest state.
- 1.2 Confirm `SENTRY_ACTIONS_RO_TOKEN` resolves read-only and the alert-rules GET shape for
  rule 1310055 (org `jikigai-eu`, api host from `SENTRY_API_HOST`).
- 1.3 Enumerate the suites pinning the current follower + proof:
  `git grep -ln 'git-data-pin-redeploy\|dispatch-web-redeploy\|track\.sh\|source-run-gate' -- tests/ scripts/ apps/ plugins/ .github/`.
- 1.4 Enumerate the wrapper/freeze consumers:
  `git grep -ln 'cutover-freeze\|CUTVER_FREEZE\|init\.lock\|_repo_count' -- apps/web-platform/infra/ tests/ scripts/`.

## 2. Tests first (RED)

- 2.1 Mode/state matrix suite (new `git-data-cutover-real-modes.test.sh` or extension):
  every (flag × freeze × mode) cell in the plan's failure-state matrix; resume arms A/B;
  `frozen_unattributed`; `frozen_foreign`; `nothing_to_rollback`.
- 2.2 Verdict census: each precondition verdict fires on its fixture and only on it —
  `tier_b_credential_absent`, `ssh_client_absent`, `pin_absent`, `pin_fault_paging_absent`,
  `flag_write_credential_absent`, `d6_replace_stale`, `store_populated`, `live_image_stale`,
  `deploy_in_flight`; each carries a `remedy:` line.
- 2.3 Freeze: provenance content format; `unfreeze` clears same-lineage only; the proof's
  `cutover_frozen` classification; gc.timer stop + `git-data-gc.service` inactivity assert
  before freeze-write.
- 2.4 track.sh: `/hooks/deploy` POST with parity-pinned peers literal; `/hooks/deploy-status`
  frame `start_ts > PRIOR_START` (baseline read post-write); `ok`-only terminal set;
  `lock_contention`/`adr027_prod_already_running` non-terminal; stale-frame rejection.
- 2.5 Flag precheck mode-aware verdicts + write-path read-back (stdin write, stdout
  discarded).
- 2.6 Server: `git_data_store=` warn-level startup line beside `logGitDataHostKeyPinAtStartup`;
  test twins updated.
- 2.7 Payload arms: real pre-receive in the payload map + bootstrap plant order; SHA-256
  against the stripped copy; `#9066` constant-name lock + exclusion-parity across
  `_repo_count`/proof/suites; emit call sites in wrapper verdict paths; userdata budget
  re-measured.
- 2.8 Workflow: credential census (each new secret in exactly one step); `web-1-swap`
  job-level membership; `timeout-minutes` ≥120; `if: always()` finalizer; mode env mapping;
  `CONFIRM_WIPE` still refuses.
- 2.9 D6 rotate target: the `-replace` set admitted by the new typed gate arm;
  `served_repos=0` asserted before apply; the rotate refuses a passphrase-without-volume plan.
- 2.10 Register suites per convention (`apps/web-platform/infra/**/*.test.sh` glob
  self-registers; `scripts/test-all.sh` for non-infra).

## 3. Implementation (GREEN)

- 3.1 `git-data-cutover.sh`: mode dispatch, precondition chain, freeze writer, `unfreeze`,
  `redeploy` lever, resume arms.
- 3.2 `git-data-flag-precheck.sh`: mode-aware read + write-path read-back.
- 3.3 `dispatch-web-redeploy/track.sh`: webhook POST + deploy-status frame poller.
- 3.4 `apply-web-platform-infra.yml`: `git-data-host-rotate` target + typed gate arm +
  inline pin-load arm after the boot poll.
- 3.5 Delete `git-data-pin-redeploy.yml` + `source-run-gate.sh`; rewrite
  `test-dispatch-web-redeploy.sh`; reference sweep (CODEOWNERS, parity suites, runbook).
- 3.6 `.github/workflows/git-data-cutover.yml`: mode inputs, write/finalizer steps, groups,
  timeout, credential census, header rewrite.
- 3.7 Payload: `main.tf` payload map, `cloud-init-git-data.yml`, `git-data-bootstrap.sh`
  step-5 real-hook plant, wrappers' lock + emit call sites, gc/reopen emit units.
- 3.8 Server: `git_data_store=` emitter + test twins.
- 3.9 Sentry single-rule GET probe + suite.
- 3.10 `git-data-cutover.yml` real-mode unrefuse (drop `refuse_real_modes` arms the modes
  now satisfy).

## 4. Records (agent-forked)

- 4.1 ADR-237 D6 amendment (follower retired; pin-load moved inline).
- 4.2 ADR-220 D6 wording (rotate target; freshness definition).
- 4.3 ADR-239 dated amendment (freeze-writer disposition; #9066 retention end).
- 4.4 CLO agent: Article 30 F1 markers (PA-36 §(g)(1), PA-2 §(g)(17) active 2026-09-25) —
  append-only.
- 4.5 Runbook `git-data-luks-cutover-5274.md`: verdict table rows, operator sequence,
  replace-time fence note; `encryption-posture-ledger.json` `reevaluate_when`.

## 5. Ship

- 5.1 `bash -n` every touched script; YAML parse every touched workflow; suite batteries green.
- 5.2 Commit with `LEFTHOOK_EXCLUDE=bun-test,plugin-component-test`; push; PR.
- 5.3 Review panel (code class — workflows + scripts + server): resolve blocking findings.
- 5.4 Emit review trailer; required checks green on exact head SHA; merge.
- 5.5 Post-merge: record the operator sequence start state on #8211 (merge ships code only;
  the flip is a dispatch).

## Operator sequence (post-merge, NOT this PR's CI)

Per plan §"Operator sequence after merge" — deploy-arm served → rung-2 re-rehearsal +
evidence PR → proof → D6 rotate → proof → optional rehearsal → gated flip dispatch
(per-step authorization) → soak ≥7d → wipe PR.
