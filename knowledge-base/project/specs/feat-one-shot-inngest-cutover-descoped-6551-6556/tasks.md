---
title: Tasks — Inngest cutover / heartbeat / observability cleanup bundle
plan: knowledge-base/project/plans/2026-07-17-fix-inngest-cutover-heartbeat-observability-cleanup-plan.md
branch: feat-one-shot-inngest-cutover-descoped-6551-6556
lane: cross-domain
closes: [6552, 6553, 6555, 6556]
investigates: [6551]
---

# Tasks

Derived from the finalized (post-plan-review) plan. Phase order is load-bearing for #6555
(contract-before-consumer: env-file writes MUST land atomically with the `--project` removals).

## Phase 0 — Preconditions (grep-verify, no code)
- [ ] 0.1 Confirm the 6 `--project` sites: `inngest-bootstrap.sh:283,523,585,737` (heredocs) + `inngest-cutover-flip.service:19` + `inngest-redis.service:23` (standalone unit files). Confirm `inngest-redis-bootstrap.sh` has NO `--project`.
- [ ] 0.2 Confirm all 6 units read `EnvironmentFile=/etc/default/inngest-server` + the scoped `DOPPLER_TOKEN` backstop (cloud-init-inngest.yml:384).
- [ ] 0.3 Confirm both sudoers copies (`deploy-inngest-bootstrap.sudoers:27`, `cloud-init.yml:83`) + AC5 byte-parity assertion (`cloud-init-inngest-bootstrap.test.sh`).
- [ ] 0.4 Locate the flip-guard test + heartbeat unit test (grep `GUARD_FLIP_FLAG`, `inngest-heartbeat`).
- [ ] 0.5 Enumerate `.service` + cloud-init `write_files` units for the #6556 P1 guard extension.

## Phase 1 — #6553 flip-guard widen + ADR-100 amend + FSM↔guard drift guard
- [ ] 1.1 `inngest-server-flip-guard.sh:40` — add `flushed` to the case allowlist.
- [ ] 1.2 Update all FOUR prose sites (`:12`, `:15-16`, `:44`, `:45`) → `{armed,flipping,flushed,done}`.
- [ ] 1.3 ADR-100:189 — widen allowlist + FSM-start rationale (cite `:163/:172/:240/:178`); target `## Considered Options` (:63) / Decision 6a-6b prose (NOT `## Alternatives Considered`).
- [ ] 1.4 Add ADR-100 class invariant: guard allowlist == {FSM states that invoke `start_server`}.
- [ ] 1.5 Add CI drift-guard test (flip-guard test surface): FAIL if the FSM `flag_set`s a pre-`start_server` state absent from the guard allowlist.
- [ ] 1.6 Test: `GUARD_FLIP_FLAG=flushed` + prod-marker URI → exit 0 (ALLOW); regression {armed,flipping,done}; block {unset,rollback,rolled-back,aborted}.

## Phase 2 — #6552 rollback deletes INNGEST_HEARTBEAT_URL (UNCONDITIONAL)
- [ ] 2.1 `cutover-inngest.yml` `op=rollback` — add idempotent `doppler secrets delete INNGEST_HEARTBEAT_URL -p soleur-inngest -c prd` (DOPPLER_TOKEN_INNGEST_ARM, no echo, absent-OK) in the UNCONDITIONAL Half-B region (after `esac`, ≥:1119), NOT the `armed|flipping|flushed|done)` case arm.
- [ ] 2.2 Test: delete is OUTSIDE the case arm; runs on an `aborted`-state rollback fixture; `op=arm` unchanged.

## Phase 3 — #6556 Part 2 OnFailure (non-templated, bare-logger, heredoc)
- [ ] 3.1 `inngest-bootstrap.sh` heartbeat `[Unit]` heredoc (:236-241) — add `OnFailure=inngest-heartbeat-failure-log.service`.
- [ ] 3.2 Render non-templated `inngest-heartbeat-failure-log.service` as a bootstrap heredoc: `SyslogIdentifier=inngest-heartbeat`, ExecStart = bare `logger -t inngest-heartbeat -p err '<fixed msg>'` (NO `doppler run` wrapper), header comment (push-less + why + post-cutover semantics).
- [ ] 3.3 Test: `OnFailure=` present; unit sets the tag; ExecStart has no `doppler`/`--project`.

## Phase 4 — #6556 Part 1 CI tag-drift guard extension
- [ ] 4.1 `vector-pii-scrub.test.sh` AC3/AC3b — extend enumeration to `.service` + `.sh`-heredoc + cloud-init `write_files` units (beyond `infra/*.sh`).
- [ ] 4.2 Add the explicit-exclusion-with-reason half; require each explicit `logger -t`/`SyslogIdentifier=` ∈ allowlist OR exclusion list. Keep `SYSTEMD_UNIT_IDENTIFIERS` only for identifiers no source line yields (webhook). Failure message stays directional.
- [ ] 4.3 Confirm the new `inngest-heartbeat-failure-log` unit passes (reuses `inngest-heartbeat`).
- [ ] 4.4 (Surfaced taste — decision-challenges T1) pick the minimal shape satisfying #6556 without a general ExecStart parser.

## Phase 5 — #6555 DOPPLER_PROJECT env-file (atomic commit)
- [ ] 5.1 `cloud-init-inngest.yml:324` — add `DOPPLER_PROJECT=soleur-inngest` to the pre-create printf.
- [ ] 5.2 `inngest-bootstrap.sh:339` heredoc — add `DOPPLER_PROJECT=$DOPPLER_PROJECT` (web-host path).
- [ ] 5.3 Remove `--project` from all 6 sites: `inngest-bootstrap.sh:283/523/585/737` + `inngest-cutover-flip.service:19` + `inngest-redis.service:23`. Keep `--config prd`. Preserve `$DOPPLER_PROJECT` render-gating logic.
- [ ] 5.4 Dead-substitution cleanup: remove `@@DOPPLER_PROJECT@@` at `inngest-bootstrap.sh:592/761/404` + `inngest-redis-bootstrap.sh:84`.
- [ ] 5.5 Fail-closed check: bootstrap asserts `DOPPLER_PROJECT` present + non-empty in the env-file before unit start.
- [ ] 5.6 Delete `DOPPLER_PROJECT` from env_keep in BOTH sudoers copies identically (`deploy-inngest-bootstrap.sudoers:27` + `cloud-init.yml:83`) + `ci-deploy.sh:2785` `--preserve-env`; reframe the `:2777-2784` comment (forward-guard superseded, not dead weight).
- [ ] 5.7 Add `SOLEUR-DEBT:` marker at `inngest-bootstrap.sh:47` pointing at the `HEARTBEAT_DARK_ARM` detector (residual dual-sourcing).
- [ ] 5.8 Update pinning tests: `inngest.test.sh:130/134/402/593` + cutover-flip + `cutover-inngest-workflow.test.sh` + `cloud-init-inngest-bootstrap.test.sh`.
- [ ] 5.9 Record preserve-branch precondition (no in-place re-bootstrap before first force-replace).

## Phase 6 — #6551 investigation write-up (+ gated instrument)
- [ ] 6.1 PR body + issue #6551 update: measured probe findings (1&2 resolved, 3 infeasible), leave OPEN, `Ref #6551`.
- [ ] 6.2 (RECOMMENDED, gated on CPO/deepen) `cat-deploy-state.sh` — add read-only `vector_config_*` Source-section hash (NOT whole-file; precedent seccomp_profile_host_sha256:314-334), with documented comparison procedure.

## Phase 7 — Verify + ship prep
- [ ] 7.1 `cd apps/web-platform && ./node_modules/.bin/vitest run` (relevant suites) — verify exact runner via `package.json`.
- [ ] 7.2 Run the infra `*.test.sh` shell suites (flip-guard, inngest, vector-pii-scrub, cloud-init-inngest-bootstrap, cutover-inngest-workflow).
- [ ] 7.3 PR body: `Closes #6552/#6553/#6555/#6556`, `Ref #6551`, inngest-base-url-repoint unblocked note. Ship renders `decision-challenges.md` → `action-required` issue.
