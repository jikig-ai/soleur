# Tasks — feat-one-shot-8036-zot-queue

Plan: `knowledge-base/project/plans/2026-09-21-fix-zot-queue-dead-ghcr-credential-plan.md`

Issue: #8036 (the PR takes `Ref #8036 #8037 #8417 #8408 #8449 #8278`, with no closing keywords).

Draft PR: #8456

## 0. Setup

- [ ] 0.1 Re-run the two date-stamp probes, then record the date and results for the PR body:
  - `GET api.github.com/user` with `GHCR_READ_TOKEN`, expecting 401
  - an anonymous cosign manifest HEAD, expecting 200
- [ ] 0.2 Re-check the issue states with `gh issue view` (#8036, #8037, #8417, #8408, #8449,
  #8278, #8386, #7377).
- [ ] 0.3 Record the baselines:
  - `bash apps/web-platform/infra/registry-userdata-budget.sh` (15,940 / 16,828 on 2026-09-21)
  - `wc -c .github/workflows/apply-web-platform-infra.yml` (476,841)

## 1. #8036 — ci-deploy.sh

- [ ] 1.1 RED: add T-1a-1 … T-1a-5 to `ci-deploy.test.sh`, with the mock recording the
  verify-time `DOCKER_CONFIG`.
- [ ] 1.2 GREEN: add the `DOCKER_CONFIG="$anon_dir"` prefix on the verify `docker run`, with a
  mktemp fallback and cleanup.
  - Nothing new may reach stdout, because of the `VERIFIED_REF` capture.
- [ ] 1.3 RED: add T-1b-1 … T-1b-3, covering the fixture matrix, the canary, and the no-abort
  cases.
- [ ] 1.4 GREEN: emit the `SOLEUR_DEPLOY_GHCR_CONFIG` closed-vocabulary marker.
  - Every `jq -e` probe uses the rc-capture form.
- [ ] 1.5 Write the ADR-087 amendment. It records the per-deploy anonymous pull and the ENFORCE
  prerequisite.
- [ ] 1.6 Add the C4 `hetzner -> sigstore` distribution edge, rewrite the NOTE comment, and fix
  the `views.c4` include if needed.
  - Run the c4-count-parity, c4-code-syntax and c4-render tests.
- [ ] 1.7 Write the 1c recommendation text for the PR body and the #8036 comment.

## 2. #8417 — bare `$$`

- [ ] 2.1 RED: add `templatefile-bare-dollar-guard.test.sh`, with a derived file set, a
  floor ≥7, set identity, and the rendered `store_probe_rc` shape for `cs127.bkna` and `cs0.bk0`.
- [ ] 2.2 GREEN: apply the three template changes:
  - `$${PATH:+:$${PATH}}`
  - `cs$${_cs_rc}.bk$${_bk_rc}`
  - `_bk_rc=0` before blkid
- [ ] 2.3 In `zot-disk-heartbeat-redaction.test.sh`, replace the PATH spelling pin with an
  evaluation.
- [ ] 2.4 Drive each Guard 1 mutation row RED by hand, and record the commands.

## 3. #8408 — registry LUKS posture

- [ ] 3.1 (a) Add the `registry_store_not_luks` SQL local, exploration and alert, with the
  arm-(B) predicate, `value=1` and `query_period=900`.
  - Add the two `-target=` lines to the `apply` job.
  - Live-probe the three controls and record the counts.
  - Write the structural suite.
- [ ] 3.2 (b) Add the sentinel write (inside the findmnt conjunction, before the runcmd
  `docker run`) and the zot `--mount type=bind`.
  - Add the NIC-guard `.State.Running` recovery arm.
  - Add the per-arm stderr tokens in `registry-luks-open.sh`.
  - Write `registry-luks-launch-gate.test.sh`, with static asserts plus the docker-gated
    behavioural case, which fails closed with no daemon and includes the `-v` negative control.
  - [ ] 3.2.1 Confirm in CI that start and restart fail on a missing `--mount` bind source.
- [ ] 3.3 (c) Add `registry-luks-escrow.sh`:
  - a header check, a memory pre-check, and `systemd-run --scope OOMScoreAdjust=1000 --test-passphrase`
  - an atomic state write
  - a cron line and a runcmd boot call

  Then add the heartbeat `store_escrow`/`store_escrow_age_s` field, and write
  `registry-luks-escrow.test.sh`.
- [ ] 3.4 Re-run the user_data budget, confirm `stored < cap`, and record it.

## 4. #8449 UC2

- [ ] 4.1 Add `.github/workflows/inngest-host-state.yml`:
  - inputs pass through env only
  - `|| rc=$?`
  - the full exit-code summary table
  - a non-zero exit on any rc other than 0
- [ ] 4.2 Add `inngest-host-state-workflow-guard.test.sh`, which derives the exit codes from the
  script header.
- [ ] 4.3 Update the runbook `inngest-server.md` with the one-tap route.
- [ ] 4.4 Post the UC1 recommendation comment on #8449.

## 5. #8037 follow-through

- [ ] 5.1 Add `scripts/followthroughs/cosign-verify-live-8037.sh` and its `.test.sh`, following
  the per-`_MACHINE_ID` positive-OK shape and keying on SYSLOG_IDENTIFIER.
- [ ] 5.2 Add the directive and the `follow-through` label to #8037.

## 6. Verification

- [ ] 6.1 Derive the suite set mechanically with
  `git grep -ln '<changed-path>' -- 'tests/**' 'scripts/**' 'apps/**' 'plugins/**' '.github/**'`
  over every changed path, then take the union.
- [ ] 6.2 Run `scripts/test-all.sh --capacity` first. Use the lock-queued form with the rc
  written to a file, and do not commit while the battery runs.
  - `zot-config-deadlines.test.sh` fails closed with no docker daemon. It does the same on main.
- [ ] 6.3 Run the repo-global gates by hand:
  - fixture-relative-assert
  - guard-vacuity-floor
  - lint-diagnosis-claims
  - lint-window-closure-assertion
  - lint-shell-capture-exit `--baseline`
  - lint-encryption-posture `--repo-sweep`
  - lint-guard-contract on the plan

## 7. GitHub writes, in order

- [ ] 7.1 Post the #8278 re-check comment and keep `blocked`.
- [ ] 7.2 In the PR body:
  - the three merge-time deliveries
  - the 1c and UC1 recommendations
  - the 1b deviation
  - the ≤5-min gate bound
  - the `_bk_rc` change
  - no closing keywords
- [ ] 7.3 Post-merge:
  - read the `SOLEUR_DEPLOY_GHCR_CONFIG` tokens and post them to #8036
  - verify the registry-replace outcome, then close #8417 on `cs0.bk0` or comment "dormant"
  - `gh workflow run inngest-host-state.yml` once
- [ ] 7.4 The sweep issue goes LAST:
  - dedup search (`registry plaintext`, `LUKS stale`)
  - cross-reference #6897
  - CONCUR subagent
  - then `gh issue create`
