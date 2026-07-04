---
feature: Autonomous multi-host GA warm-standby apply + programmatic §(c) gate + de-manualization
branch: feat-one-shot-autonomous-multihost-ga-cutover
lane: cross-domain
plan: knowledge-base/project/plans/2026-07-04-feat-autonomous-multihost-ga-warm-standby-and-gate-plan.md
brand_survival_threshold: single-user incident
---

# Tasks — Autonomous multi-host GA warm-standby + §(c) gate

Derived from the finalized plan (post 5-agent review). Ordering is load-bearing: **Phase 4 lint
lands before Phase 3 verification** (producer before consumer).

## Phase 0 — Preconditions (grep/read, no mutation)

- [ ] 0.1 Read-only 6-target `terraform plan` (canonical `prd_terraform` triplet): confirm `6 add /
      0 change / 0 destroy`, `0 to create` of any non-targeted resource, no web-1
      `placement_group_id`/reboot diff. Record in PR body. The apply's created-resources output =
      attach proof.
- [ ] 0.2 Read `ci-deploy.sh:134-172,1320-1330`: confirm fan-out fires post-web-1-swap, non-202 →
      `reason=ok_peer_fanout_degraded` exit 0, and the minimal-blast deploy trigger (`POST /hooks/deploy`
      current version vs a new release); note whether a web-2-only deploy path exists (OQ2).
- [ ] 0.3 Confirm `SOLEUR_PROXY_BIND` / `SOLEUR_PROXY_PEER_ALLOWLIST` / `SOLEUR_HOST_ROSTER` /
      `GIT_DATA_STORE_ENABLED` are runtime env from Doppler `prd`.
- [ ] 0.4 `git grep -ln 'reboot_updates\|MOVED_OPERATOR_CONSUMED\|-target='` — enumerate every
      asserting suite; confirm plan-scoped `reboot_updates` jq is the real reboot guard; keep the
      parity test job-aware.
- [ ] 0.5 Run the actor+imperative candidate patterns across the scan dirs; enumerate current
      corpus matches (sizes the changed-files scope + carve-outs).
- [ ] 0.6 `wc -c AGENTS.md AGENTS.core.md` (22976/23000) + byte length of `hr-no-ssh-fallback-in-runbooks`.

## Phase 1 — Programmatic §(c) gate (fail-closed, SHAPE-ONLY)

- [ ] 1.1 (RED) Write `apps/web-platform/infra/lb-weight-gate.test.sh` first (native bash; assert
      exit codes): both-hold→0 (+ stdout `requires_runtime_bind_probe=true`); each missing/empty
      A-var→non-zero; roster missing web-2→non-zero; roster loader-rejects
      (dup-key/non-object/whitespace)→non-zero; allowlist⊄roster→non-zero;
      `GIT_DATA_STORE_ENABLED=false`→non-zero; marker absent/unparseable/future-dated→non-zero;
      `GIT_DATA_LUKS_SOAK_DAYS<=0`→non-zero; soak-not-elapsed→non-zero.
- [ ] 1.2 (GREEN) Write `apps/web-platform/infra/lb-weight-gate.sh` — pure, fail-closed over injected
      env; Condition A (proxy_bind + allowlist [parseProxyPeerAllowlist semantics] + roster
      [loadHostRoster semantics, web-2-present, allowlist⊆roster]); Condition B
      (`GIT_DATA_STORE_ENABLED==true` + `GIT_DATA_LUKS_CUTOVER_AT` soak marker; NO source-grep
      sentinel); prints `requires_runtime_bind_probe=true` + SHAPE-ONLY banner on success.
- [ ] 1.3 Suite green.

## Phase 4 — Workflow improvement (BEFORE Phase 3 verification)

- [ ] 4.1 `scripts/lint-infra-no-human-steps.py` — actor+imperative CO-OCCURRENCE model;
      `<!-- lint-infra-ignore -->` regions + fenced/backtick + `archive/`/`## Resolved`/`Last-resort`
      carve-outs; changed-files mode; scan dirs incl. legal/runbooks + engineering/architecture/decisions;
      paren-safe.
- [ ] 4.2 (RED→GREEN) `scripts/lint-infra-no-human-steps.test.sh`: human-step FAILS; orchestrator-defer
      PASSES; ignore-region PASSES; `tofu apply`-by-operator paraphrase FAILS.
- [ ] 4.3 Wire the lint into `.github/workflows/ci.yml` (lint step) + `lefthook.yml` (pre-commit).
- [ ] 4.4 Strengthen `hr-no-ssh-fallback-in-runbooks` (AGENTS.core.md:44) in place: class clause +
      `[hook-enforced: lefthook lint-infra-no-human-steps.py]`; short cross-ref on
      `hr-exhaust-all-automated-options-before` + `hr-fresh-host-provisioning-reachable-from-terraform-apply`.
      Re-measure `wc -c` ≤ 23000; `lint-agents-enforcement-tags.py` / `-rule-budget.py` / `lint-rule-ids.py` green.
- [ ] 4.5 Learning file `knowledge-base/project/learnings/workflow-patterns/2026-07-04-<topic>.md`.

## Phase 2 — Dispatchable warm-standby apply (R2-serialized; no operator-local, no SSH)

- [ ] 2.1 Add `workflow_dispatch apply_target` (enum `manual-rerun`|`warm-standby`) to
      `apply-web-platform-infra.yml`.
- [ ] 2.2 `warm-standby` job: same `terraform-apply-web-platform-host` concurrency group; `plan -out`
      `-target`ing the 6 resources; run plan-scoped destroy-guard (`reboot_updates=0`); `apply tfplan`.
- [ ] 2.3 Probe web-2 `:9000` reachability (bounded retry); trigger the minimal-blast deploy
      (`POST /hooks/deploy` current version).
- [ ] 2.4 Verify off-host, no SSH: read web-1 `/hooks/deploy-status`; **fail unless `reason=="ok"`**
      (fail on `reason=~_peer_fanout_degraded`); assert the apply output shows the 2 web-2 attach
      resources created.
- [ ] 2.5 Guard-suite test: warm-standby 6-target plan → `reboot_updates=0`; keep parity test
      job-aware. `actionlint` + `bash -c` on extracted `run:`.

## Phase 3 — De-manualize the multi-host plan + runbook (AFTER Phase 4 lint exists)

- [ ] 3.1 Rewrite the multi-host plan Phase 2 + IaC Apply path + Post-merge (operator) → the
      dispatch path (`gh workflow run … -f apply_target=warm-standby`); reference the §(c) gate.
- [ ] 3.2 Rewrite runbook Scope B pre-flight step 1 + steps 5–6 → dispatch; wrap the DEFERRED
      orchestrator steps 7–10 in `<!-- lint-infra-ignore -->`; reference `lb-weight-gate.sh`.
- [ ] 3.3 Confirm all three files (both docs + THIS plan) PASS `lint-infra-no-human-steps.py`.

## Phase 2.10 — ADR / C4

- [ ] Amend ADR-068 (autonomous warm-standby + SHAPE-ONLY gate + readyz/attach reconciliation);
      text names `requires_runtime_bind_probe` + "apply output = attach proof"; wrap
      orchestrator-quote prose in `<!-- lint-infra-ignore -->`. No C4 edit (enumeration cited).

## Phase 5 — Defer the live cutover orchestrator

- [ ] 5.1 `gh issue create` — "Live multi-host GA cutover orchestrator (Inngest-dispatched GHA
      maintenance-window)": builds `lb-weight-gate-doppler.sh` + the on-host runtime gate (in-container
      readyz, N≥2 consecutive, device-identity) as a DISTINCT condition from the SHAPE-ONLY gate;
      weight 0→1 → drain web-1 → remove `ignore_changes` → reboot drained → restore + auto-rollback.
      `Ref` not `Closes`; re-eval criteria; milestone from roadmap.md.

## Exit

- [ ] AC checklist (plan `## Acceptance Criteria` Pre-merge) all green; PR body records P0 evidence +
      before/after `wc -c`; `Ref #5887 / #5274`.
