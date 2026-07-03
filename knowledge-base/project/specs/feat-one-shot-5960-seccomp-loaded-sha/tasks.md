---
issue: 5960
lane: single-domain
plan: knowledge-base/project/plans/2026-07-03-fix-seccomp-loaded-sha-deploy-status-discriminators-plan.md
brand_survival_threshold: aggregate pattern
---

# Tasks — fix(infra) #5960 seccomp redeploy loaded-sha discriminators

Derived from the finalized (post-5-agent-review) plan. Phase order is load-bearing:
producer (1) → workflow assert (2) → poll (3) → stop-asserting-recorded (4) → ADR (5) → tests (6).

## Phase 0 — Preconditions

- [x] 0.1 Confirm on branch `feat-one-shot-5960-seccomp-loaded-sha` (not main).
- [x] 0.2 Re-read `apps/web-platform/infra/audit-bwrap-uid.sh:105-146` (the docker-inspect
      + `jq -cS` + EMPTY_HASH-guard technique being reused) and
      `apps/web-platform/infra/cat-deploy-state.sh` sibling helpers
      (`container_restart_json`, `sandbox_canary_json`) + the final `jq` merge block.
- [x] 0.3 Confirm `SECCOMP_PROFILE_HOST_PATH` default at `ci-deploy.sh:195` =
      `/etc/docker/seccomp-profiles/soleur-bwrap.json`.
- [x] 0.4 Grep every `final_write_state 0` in `ci-deploy.sh` (5 hits); confirm only
      `:1211/1213` is the web-platform arm (AC4).

## Phase 1 — cat-deploy-state.sh: live loaded + host discriminators (producer)

- [x] 1.1 Add `seccomp_profile_loaded_matches_host` (bool): docker-inspect
      `HostConfig.SecurityOpt` → `sed -n 's/^seccomp=//p'` → literal-path guard →
      `jq -cS | sha256sum` of inlined vs host file (SAME host jq) → equal + non-empty-hash.
      `false` on any failure; EMPTY_HASH guard (audit-bwrap-uid.sh:137-140).
- [x] 1.2 Add `seccomp_profile_host_sha256` (RAW `sha256sum` of host file; `""` if absent).
- [x] 1.3 Add `seccomp_profile_host_present` (bool `-f`).
- [x] 1.4 Extend the final `jq` merge with the 3 keys; do NOT clobber top-level `exit_code`.
- [x] 1.5 Leave existing `seccomp_profile_sha256` (raw recorded) untouched (inert diagnostic).
      Do NOT add `seccomp_profile_host_path` or `seccomp_recorded_loaded_at`.

## Phase 2 — apply-deploy-pipeline-fix.yml: robust snapshot-bound assert (consumer)

- [x] 2.1 Keep `COMMITTED_SHA` raw `sha256sum` (`:487` unchanged).
- [x] 2.2 Fast-path: skip redeploy iff `host_present && host_sha256==COMMITTED_SHA &&
      loaded_matches_host`. On transient-empty `loaded_matches_host` at baseline, settle+re-read once.
- [x] 2.3 On terminal detection `cp /tmp/redeploy-status.json /tmp/redeploy-terminal.json`;
      read load-bearing + all discriminators from the frozen frame (AC5).
- [x] 2.4 Load-bearing assert: `host_present && host_sha256==COMMITTED_SHA && loaded_matches_host`.
- [x] 2.5 Fail-loud discriminator classes (not-delivered / host-stale / not-reloaded); no
      `.seccomp_profile_sha256` equality gate remains (AC6/AC7).
- [x] 2.6 Timeout graceful-degradation: final STATE check → PASS iff invariant holds, else
      fail-loud UNVERIFIED (AC8). No nonce.

## Phase 3 — apply-deploy-pipeline-fix.yml: poll predicate (BLOCKING behavioral fix)

- [x] 3.1 Read `component`, `tag`, `reason` from the status frame.
- [x] 3.2 Terminal acceptance: `component=="web-platform" && tag=="$TARGET_TAG" &&
      exit_code>=0 && start_ts>PRIOR_START`.
- [x] 3.3 Adjudicate: `lock_contention`/`adr027_prod_already_running`/`running`(exit -1) →
      KEEP POLLING; `ok`/`ok_peer_fanout_degraded` → assert; other genuine-failure reason →
      fail loud with reason (AC3).

## Phase 4 — Stop asserting the recorded field (no removal)

- [x] 4.1 Ensure no load-bearing/fast-path read of `.seccomp_profile_sha256` remains.
- [x] 4.2 Leave `write_seccomp_profile_hash` (ci-deploy.sh) in place as inert raw diagnostic
      (no deprecation cycle, no tracking issue).

## Phase 5 — ADR-079 amendment

- [x] 5.1 Add `### Amendment (#5960, 2026-07-03) — …` (4-6 lines): old contract → new
      (`loaded==host` live host-jq; `host==committed` raw; poll requires component+tag,
      lock_contention non-terminal; STATE-invariant timeout). Note the second docker-inspect
      per GET. No new ordinal (AC13).

## Phase 6 — Tests

- [x] 6.1 PORT `create_docker_mock` from `audit-bwrap-uid.test.sh:26` into
      `cat-deploy-state.test.sh` (suite currently mocks nothing).
- [x] 6.2 Cases: (1) loaded==host, (2) drift, (3) literal-path, (4) container-down,
      (5) host-absent, (6) merge-integrity/exit_code, (7) empty-hash guard.
- [x] 6.3 Run `cat-deploy-state.test.sh` green via the infra `.test.sh` harness (no bats).

## Phase 7 — Verify / negative-scope

- [x] 7.1 AC11 negative scope: no `seccomp-bwrap.json` byte change, no `apps/web-platform/infra/sentry/` change.
- [x] 7.2 Static AC checks (AC3 baseline-0 `.component`, AC4 grep, AC6 grep, AC13 ADR count).

## Post-merge (operator / automated)

- [ ] P.1 AC14: `apply-deploy-pipeline-fix.yml` real green run (loaded_matches_host && host==committed
      on a real swap). `gh run watch`; no SSH.
- [ ] P.2 AC15: `gh issue close 5960 --reason completed` after AC14 green. PR body uses `Ref #5960`.
